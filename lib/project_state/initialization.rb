require 'logger'

require_dependency File.expand_path(File.dirname(__FILE__)+'/utils')

module ProjectStatePlugin

  class Initializer
    include Redmine::I18n
    include ProjectStatePlugin::Defaults
    include ProjectStatePlugin::Utilities

    def add_to_trackers(cf)
      begin
        omit = Tracker.where(name: semiString2List(Setting.plugin_project_state['ignore_trackers']))
      rescue
        return
      end
      Tracker.all.each do |t|
        if cf.trackers.include? t
          if omit.include? t
            cf.trackers.delete(t)
            $pslog.info("Removing '%s' from tracker '%s'" % [cf.name,t.name])
          end
        else
          if ! omit.include? t
            cf.trackers<<(t)
            $pslog.info("Adding '%s' to tracker '%s'" % [cf.name,t.name])
          end
        end
      end
    end

    def ensure_custom_fields
      nm = CUSTOM_PROJECT_STATE
      ps = IssueCustomField.find_or_create_by(name: nm) do |icf|
        $pslog.info("Creating custom field '%s'" % nm)
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
        $pslog.info("Creating custom field '%s'" % nm)
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
        $pslog.info("Creating custom field '%s'" % nm)
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
        $pslog.info("Creating custom field '%s'" % nm)
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
        $pslog.info("Creating custom field '%s'" % nm)
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
          $pslog.info("Adding '%s' to project '%s'" % [cfname,p.name])
        end
      end
      antiList.each do |p|
        if cf.projects.include? p
          cf.projects.delete p
          $pslog.info("Removing '%s' from project '%s'" % [cfname,p.name])
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
            cv.value = StatusTimeoutDefault.find_by(status: iss.status_id).timeout.to_s
          end
          CustomValue.find_or_create_by(customized_id: iss.id,
                                        customized_type: 'Issue',
                                        custom_field: hlim) do |cv|
            cv.value = TimeLimitDefault.find_by(tracker_id: iss.tracker_id).hours.to_s
          end
      
        end
      end
    end

    def populate_reports
      begin
        ProjectStateReport.find_or_create_by(name: "Percent Billable Time") do |ps|
          $pslog.info("Creating Percent Billable Time Report")
          ps.ordering = 1
          ps.view = "billable_time"
          ps.dateview = 'form_dates'
          ps.want_interval = true
        end
        ProjectStateReport.find_or_create_by(name: "Logged Time by Group") do |ps|
          $pslog.info("Creating Logged Time by Group Report")
          ps.ordering = 2
          ps.view = "time_logged_by_group"
          ps.dateview = 'form_dates'
          ps.want_interval = true
        end
        ProjectStateReport.find_or_create_by(name: "Limit Changes") do |ps|
          $pslog.info("Creating Limit Changes Report")
          ps.ordering = 3
          ps.view = "limit_changes"
          ps.dateview = 'form_dates'
          ps.want_interval = false
        end
        ProjectStateReport.find_or_create_by(name: "Number in State") do |ps|
          $pslog.info("Creating Number In State Report")
          ps.ordering = 4
          ps.view = "number_in_state"
          ps.dateview = 'form_dates'
          ps.want_interval = true
        end
        ProjectStateReport.find_or_create_by(name: "Active by Analyst") do |ps|
          $pslog.info("Creating Active by Analyst Report")
          ps.ordering = 5
          ps.view = "active_by_analyst"
          ps.dateview = 'form_dates'
          ps.want_interval = true
        end
        ProjectStateReport.find_or_create_by(name: "Hold by Analyst") do |ps|
          $pslog.info("Creating Hold by Analyst Report")
          ps.ordering = 6
          ps.view = "hold_by_analyst"
          ps.dateview = 'form_dates'
          ps.want_interval = true
        end
        ProjectStateReport.find_or_create_by(name: "Hours Logged: Current and Average") do |ps|
          $pslog.info("Creating Current and Average Report")
          ps.ordering = 7
          ps.view = "hours_current_and_average"
          ps.dateview = 'form_dates'
          ps.want_interval = true
        end
        ProjectStateReport.find_or_create_by(name: "Finance Report") do |ps|
          $pslog.info("Creating Finance Report")
          ps.ordering = 8
          ps.view = "finance_report"
          ps.dateview = 'form_charging'
          ps.want_interval = false
        end
        ProjectStateReport.find_or_create_by(name: "Time Waiting") do |ps|
          $pslog.info("Creating Time Waiting Report")
          ps.ordering = 9
          ps.view = "time_waiting"
          ps.dateview = 'form_dates'
          ps.want_interval = true
        end
        ProjectStateReport.find_or_create_by(name: "Opening and Closing") do |ps|
          $pslog.info("Creating Opening/Closing Report")
          ps.ordering = 10
          ps.view = "opening_closing"
          ps.dateview = 'form_dates'
          ps.want_interval = true
        end
      rescue
        $pslog.debug("Populate reports later.")
      end
    end

    def init_logger
      logfile = Setting.plugin_project_state['log_file']
      $pslog = ::Logger.new(logfile,10,10000000)
      $pslog.level = ::Logger::DEBUG
    end

    def init_random
      $psrand = Random.new
    end

  end
end
