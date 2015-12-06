require 'redmine'
require_dependency 'project_state/hooks'
require_dependency 'project_state/patches'
require_dependency 'project_state/initialization'

Redmine::Plugin.register :project_state do
  name 'Project State plugin'
  author 'Gord Brown'
  description 'Track project states, notify if/when various conditions occur'
  version '1.1.5'
  url 'https://github.com/crukci-bioinformatics/process_tracker_plugin'
  author_url 'http://gdbrown.org/blog/'

  settings(:default => { 'root_projects' => 'Research Groups',
                         'alert_logins' => 'brown22',
                         'filter_trackers' => 'Class I - Statistics',
                         'filter_projects' => 'External; Genomics; Proteomics; Other Core Facilities',
                         'filter_keepers' => 'Class I - Analysis',
                         'ignore_trackers' => 'Bug; Feature; Support; Other',
                         'non_chargeable' => 'Experimental Design Meetings; Statistics Clinic Meeting',
                         'holiday_url' => 'https://www.gov.uk/bank-holidays.json',
                         'logfile' => '/var/log/redmine/project_state.log'},
           :partial => 'settings/project_state_settings' )

  menu :top_menu, :states, { controller: 'project_state/summary', action: 'index' }, caption: :project_state_caption, after: :myprojects
  menu :top_menu, :ps_user, '/project_state/user', caption: :project_my_state_caption, after: :states
  menu :top_menu, :reports, { controller: 'project_state/project_state_reports', action: 'index' }, caption: :project_reports_caption, after: :ps_user

end

Rails.configuration.after_initialize do
  Issue.send(:include,ProjectStatePlugin::IssuePatch)
  Project.send(:include,ProjectStatePlugin::ProjectPatch)
  CustomValue.send(:include,ProjectStatePlugin::CustomValuePatch)
  Journal.send(:include,ProjectStatePlugin::JournalPatch)
  # the following steps are necessary in case the "root_projects" variable
  # has been altered... may need to add new projects to the custom fields,
  # and if so, add default CustomField values to issues
  initr = ProjectStatePlugin::Initializer.new
  initr.init_logger
  initr.ensure_custom_fields # ensure custom fields are present (should only need to be created once)
  projSet = initr.ensure_projects_have_custom_fields
  initr.populate_reports
#  initr.ensure_issues_have_custom_fields(projSet)
end
