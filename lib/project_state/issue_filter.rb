require 'project_state/defaults'
require 'project_state/utils'

module ProjectStatePlugin
  module IssueFilter

    include ActionView::Helpers::NumberHelper
    include ProjectStatePlugin::Utilities

    def days_in_state(issue)
      seconds = 60 * 60 * 24
      j = issue.state_last_changed
      if j.nil?
       return 0
      end
      ch = j.to_i / seconds
      now = DateTime.now.to_i / seconds
      interval = now - ch
      if issue.state == 'Active'
        begin
          last_logged = issue.time_entries.order(:spent_on).last.spent_on.to_time.to_i / seconds
        rescue NoMethodError => e
          last_logged = 0
        end
        log_i = now - last_logged
        interval = [interval,log_i].min
      end
      return interval
    end

    def get_flags(issue)
  
      flags = []
      if issue.status_id == IssueStatus.find_by(name: 'Closed').id
        return flags
      end
  
      # check time in state (or since last logged time, if 'Active')
      interval = days_in_state(issue)
      if interval > issue.state_timeout
        if issue.state == 'Active'
          flags << l(:flag_days_since_logged_time,
                     :state => issue.state,
                     :actual => interval,
                     :threshold => issue.state_timeout)
        else
          flags << l(:flag_days_in_state,
                     :state => issue.state,
                     :actual => interval,
                     :threshold => issue.state_timeout)
        end
      end
  
      # logged time exceeds limits
      if issue.spent_hours > issue.hours_limit
        flags << l(:flag_hours_logged,
                   :logged => number_with_precision(issue.spent_hours,precision: 2),
                   :threshold => number_with_precision(issue.hours_limit,precision: 2))
      end
  
  
      # unassigned but past Prepare
      if issue.assigned_to.nil? && issue.state != 'Prepare'
        flags << l(:flag_analyst_unassigned,
                   :state => issue.state)
      end
  
      # status / state mismatch
      if ProjectStatePlugin::Defaults::PROJECT_STATE_DEFAULTS[issue.status_id] != issue.state
        flags << l(:flag_status_state_mismatch,
                   :status => issue.status.name,
                   :state => issue.state)
      end
  
      return flags
    end

    def is_flagged(issue)
      return (get_flags(issue).length > 0)
    end

    def filter_issues(issues)
      stats = Tracker.find_by(name: 'Class I - Statistics').id
      anal = Tracker.find_by(name: 'Class I - Analysis').id
      filt_projects = collectProjects(Setting.plugin_project_state['filter_projects'])

      # remove "statistics" issues
      filt = issues.select{|i| i if i.tracker_id != stats}

      # only show "analysis" issues if not under "Research Groups"
      filt = filt.select{|i| i if !(filt_projects.include?(i.project_id)) || i.tracker_id == anal}

      return filt
    end

  end
end
