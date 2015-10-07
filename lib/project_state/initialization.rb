require_dependency File.expand_path(File.dirname(__FILE__)+'/utils')

module ProjectStatePlugin

  class Initializer
    include ProjectStatePlugin::Utilities

    def add_to_projects(cfname,projList)
      cf = IssueCustomField.where(name: cfname)[0]
      projList.each do |project|
        begin
          cf.projects<<(project)
        rescue ActiveRecord::RecordNotUnique
        end
      end
    end
  
    def addCustomFieldsToProjects
      projList = collectProjects(Setting.plugin_project_state['root_projects'])
      projSet = Project.where(id: projList)
      add_to_projects("Project State",projSet)
      add_to_projects("State Timeout",projSet)
      add_to_projects("Hour Limit",projSet)
    end

    def addCustomFieldsToIssues
      projList = collectProjects(Setting.plugin_project_state['root_projects'])
      projSet = Project.where(id: projList)
      pstate = CustomField.find_by(name: 'Project State')
      stime = CustomField.find_by(name: 'State Timeout')
      hlim = CustomField.find_by(name: 'Hour Limit')
      projSet.each do |proj|
        proj.issues.each do |iss|
          ps = CustomValue.find_or_create_by(customized_id: iss.id,
                                             customized_type: 'Issue',
                                             custom_field: pstate) do |cv|
            if ProjectStatePlugin::Defaults::PROJECT_STATE_DEFAULTS.has_key?(iss.status_id)
              cv.value = ProjectStatePlugin::Defaults::PROJECT_STATE_DEFAULTS[iss.status_id] 
            else
              cv.value = 'Ready'
            end
          end
          CustomValue.find_or_create_by(customized_id: iss.id,
                                        customized_type: 'Issue',
                                        custom_field: stime) do |cv|
            cv.value = StateTimeoutDefault.find_by(state: ps.value).timeout.to_s
          end
          CustomValue.find_or_create_by(customized_id: iss.id,
                                        customized_type: 'Issue',
                                        custom_field: hlim) do |cv|
            cv.value = TimeLimitDefault.find_by(tracker_id: iss.tracker_id).hours.to_s
          end
      
        end
      end
    end

  end
end
