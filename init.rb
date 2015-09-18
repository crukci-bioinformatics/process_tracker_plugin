require 'redmine'
require_dependency 'project_state/hooks'
require_dependency 'project_state/patches'
require_dependency 'project_state/initialization'

Redmine::Plugin.register :project_state do
  name 'Project State plugin'
  author 'Gord Brown'
  description 'Track project states, notify if/when various conditions occur'
  version '1.0.0'
  url 'https://github.com/crukci-bioinformatics/process_tracker_plugin'
  author_url 'http://gdbrown.org/blog/'

  settings(:default => { 'root_projects' => 'Research Groups',
                         'user_groups' => 'Bioinformatics Core' },
           :partial => 'settings/project_state_settings' )

  menu :top_menu, :states, { controller: 'states', action: 'index' }, caption: :project_state_caption, before: :help

end

Rails.configuration.after_initialize do
  Issue.send(:include,ProjectStatePlugin::IssuePatch)
  Project.send(:include,ProjectStatePlugin::ProjectPatch)
  CustomValue.send(:include,ProjectStatePlugin::CustomValuePatch)
  Journal.send(:include,ProjectStatePlugin::JournalPatch)
  initr = ProjectStatePlugin::Initializer.new
  # the following steps are necessary in case the "root_projects" variable
  # has been altered... may need to add new projects to the custom fields,
  # and if so, add default CustomField values to issues
  initr.addCustomFieldsToProjects
  initr.addCustomFieldsToIssues
end
