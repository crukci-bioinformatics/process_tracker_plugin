require_dependency File.expand_path(File.dirname(__FILE__)+'/utils')

module ProjectStatePlugin

  class Initializer
    include Redmine::I18n
    include ProjectStatePlugin::Defaults
    include ProjectStatePlugin::Utilities
    include ProjectStatePlugin::Logger

    def add_to_trackers(cf)
      omit = Tracker.where(name: semiString2List(Setting.plugin_project_state['ignore_trackers']))
      Tracker.all.each do |t|
        if cf.trackers.include? t
          if omit.include? t
            cf.trackers.delete(t)
            info("Removing '%s' from tracker '%s'" % [cf.name,t.name])
          end
        else
          if ! omit.include? t
            cf.trackers<<(t)
            info("Adding '%s' to tracker '%s'" % [cf.name,t.name])
          end
        end
      end
    end

    def ensure_custom_fields
      nm = CUSTOM_PROJECT_STATE
      ps = IssueCustomField.find_or_create_by(name: nm) do |icf|
        info("Creating custom field '%s'" % nm)
        icf.field_format = 'list'
        icf.possible_values = ["Prepare", "Submit", "Ready", "Active", "Hold", "Post", "Ongoing"]
        icf.is_required = false
        icf.is_filter = true
        icf.searchable = true
        icf.default_value = 'Prepare'
        icf.format_store = {"url_pattern"=>"", "edit_tag_style"=>""}
        icf.description = l(:custom_var_project_state)
      end

      nm = CUSTOM_STATE_TIMEOUT
      st = IssueCustomField.find_or_create_by(name: nm) do |icf|
        info("Creating custom field '%s'" % nm)
        icf.field_format = 'int'
        icf.min_length = 0
        icf.is_required = false
        icf.is_filter = true
        icf.default_value = "0"
        icf.format_store = {"url_pattern"=>""}
        icf.description = l(:custom_var_state_timeout)
      end
  
      nm = CUSTOM_HOUR_LIMIT
      hl = IssueCustomField.find_or_create_by(name: nm) do |icf|
        info("Creating custom field '%s'" % nm)
        icf.field_format = 'int'
        icf.min_length = 0
        icf.is_required = false
        icf.is_filter = true
        icf.default_value = "0"
        icf.format_store = {"url_pattern"=>""}
        icf.description = l(:custom_var_hour_limit)
      end
  
      nm = CUSTOM_RESEARCHER_EMAIL
      rm = IssueCustomField.find_or_create_by(name: nm) do |icf|
        info("Creating custom field '%s'" % nm)
        icf.field_format = 'string'
        icf.regexp = "^\\s*[\\w.%+-]+@[\\w.-]+\\.[A-Za-z]{2,4}(\\s*;\\s*[\\w.%+-]+@[\\w.-]+\\.[A-Za-z]{2,4})*\s*$"
        icf.is_filter = true
        icf.is_for_all = true
        icf.default_value = ""
        icf.format_store = {"text_formatting"=>"", "url_pattern"=>""}
        icf.description = l(:custom_var_researcher)
      end

      nm = CUSTOM_ANALYST
      an = IssueCustomField.find_or_create_by(name: nm) do |icf|
        info("Creating custom field '%s'" % nm)
        icf.field_format = 'user'
        icf.regexp = ""
        icf.is_filter = true
        icf.is_for_all = false
        icf.default_value = ""
        icf.format_store = {"user_role"=>["6"], "edit_tag_style"=>""},
        icf.description = l(:custom_var_analyst)
      end

      add_to_trackers(ps)
      add_to_trackers(st)
      add_to_trackers(hl)
      add_to_trackers(rm)
      add_to_trackers(an)

    end


    def add_to_projects(cfname,projList,antiList)
      cf = IssueCustomField.where(name: cfname)[0]
      projList.each do |p|
        if !cf.projects.include? p
          cf.projects<< p
          info("Adding '%s' to project '%s'" % [cfname,p.name])
        end
      end
      antiList.each do |p|
        if cf.projects.include? p
          cf.projects.delete p
          info("Removing '%s' from project '%s'" % [cfname,p.name])
        end
      end
    end
  
    def ensure_projects_have_custom_fields
      projList = collectProjects(Setting.plugin_project_state['root_projects'])
      projSet = Project.where(id: projList)
      antiSet = Project.where.not(id: projList)
      add_to_projects(CUSTOM_PROJECT_STATE,projSet,antiSet)
      add_to_projects(CUSTOM_STATE_TIMEOUT,projSet,antiSet)
      add_to_projects(CUSTOM_HOUR_LIMIT,projSet,antiSet)
      add_to_projects(CUSTOM_ANALYST,projSet,antiSet)
      return projSet
    end


    def ensure_issues_have_custom_fields(projSet)
      pstate = CustomField.find_by(name: CUSTOM_PROJECT_STATE)
      stime = CustomField.find_by(name: CUSTOM_STATE_TIMEOUT)
      hlim = CustomField.find_by(name: CUSTOM_HOUR_LIMIT)
      projSet.each do |proj|
        proj.issues.each do |iss|
          ps = CustomValue.find_or_create_by(customized_id: iss.id,
                                             customized_type: 'Issue',
                                             custom_field: pstate) do |cv|
            psd = StatusStateMapping.find_by(status: iss.status_id)
            if !psd.nil?
              cv.value = psd.state
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
