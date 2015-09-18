require_dependency File.expand_path(File.dirname(__FILE__)+'/defaults')
require_dependency File.expand_path(File.dirname(__FILE__)+'/utils')

module ProjectStatePlugin

  class Initializer
    include ProjectStatePlugin::Defaults
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
      projList = includedProjects
      add_to_projects("Project State",projList)
      add_to_projects("State Timeout",projList)
      add_to_projects("Hour Limit",projList)
    end

    def addCustomFieldsToIssues
      projList = includedProjects
      pstate = CustomField.find_by(name: 'Project State')
      stime = CustomField.find_by(name: 'State Timeout')
      hlim = CustomField.find_by(name: 'Hour Limit')
      projList.each do |proj|
      projList = includedProjects
        proj.issues.each do |iss|
          ps = CustomValue.find_or_create_by(customized_id: iss.id,
                                             customized_type: 'Issue',
                                             custom_field: pstate) do |cv|
            if @@project_state_defaults.has_key?(iss.status_id)
              cv.value = @@project_state_defaults[iss.status_id] 
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
