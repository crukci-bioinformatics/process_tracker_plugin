require 'project_state/defaults'
require 'project_state/utils'

module ProjectStatePlugin
  module IssueFilter

    include ActionView::Helpers::NumberHelper
    include ProjectStatePlugin::Defaults
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
      if IssueStatus.where(is_closed: true).include? issue.status
        return flags
      end
  
      # check time in state (or since last logged time, if 'Active')
      on_hold = IssueStatus.find_by(name: 'On Hold').id
      interval = days_in_state(issue)
      if interval > issue.state_timeout
        if issue.state == 'Active'
          flags << l(:flag_days_since_logged_time,
                     :state => issue.state,
                     :actual => interval,
                     :threshold => issue.state_timeout)
        elsif issue.status_id != on_hold
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
      psd = StatusStateMapping.find_by(status: issue.status_id)
      if !psd.nil? && psd.state != issue.state
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
      stat_names = semiString2List(Setting.plugin_project_state['filter_trackers'])
      stats = Tracker.where(name: stat_names)
      anal_names = semiString2List(Setting.plugin_project_state['filter_keepers'])
      anal = Tracker.where(name: anal_names)
      filt_projects = collectProjects(Setting.plugin_project_state['filter_projects'])

      # remove "statistics" issues
      filt = issues.select{|i| i if !(stats.include? i.tracker)}

      # only show "analysis" issues if not under "Research Groups"
      filt = filt.select{|i| i if !(filt_projects.include?(i.project_id)) || anal.include?(i.tracker)}

      filt = filter_on_tracker(filt)

      return filt
    end

    def filter_on_tracker(issues)
      tnames = semiString2List(Setting.plugin_project_state['ignore_trackers'])
      trackers_ignore = Tracker.where(name: tnames).map{|t| t.id}
      fissues = issues.select{|iss| iss if ! trackers_ignore.include?(iss.tracker_id)}
      return fissues
    end

  end
end
