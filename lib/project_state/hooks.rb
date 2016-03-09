require 'date'
require 'stringio'

require_dependency File.expand_path(File.dirname(__FILE__)+'/utils')
require_dependency File.expand_path(File.dirname(__FILE__)+'/issue_filter')

# Various actions must be taken when issues are created or edited.  This
# description attempts to capture that.
#
# When an issue is created:
#   before save:
#     1) set the state to match the status, disregarding its set value.
#     2) state timeout:
#        a) if it was set, allow and notify
#        b) if not set, set to match the state.
#     3) hour limit
#        a) if set, allow and notify
#        b) if not, set to match the tracker.
#   after save:
#     1) generate a journal entry indicating the creation of the issue,
#        in particular reporting its state changing from 'new' to the actual
#        state.
#     2) If notify flag is set, send email
#        Note that we wait until after the save to send the email, in case the
#        save fails for other reasons.
#
# When an issue is edited:
#   before save:
#     1) State versus status:
#        a) If state has changed, but status hasn't, reject.
#        b) If status has changed but not state
#           i) if new status still matches state, do nothing
#           ii) otherwise, alter state to follow status, set state_changed flag
#        c) if both have changed, set state_changed flag
#           i) if they do not match, alter state to match status
#     2) State timeout
#        a) if set, allow and set notify flag
#        b) if not set
#           i) if state has changed, set timeout to default for state
#     3) Hours limit
#        a) if set, allow and set notify flag
#        b) if not set
#           i) if tracker has changed, set to match tracker
#   after save:
#     1) If notify flag is set, send email

module ProjectStatePlugin
  class Hooks < Redmine::Hook::Listener

    include Redmine::I18n
    include ProjectStatePlugin::Defaults
    include ProjectStatePlugin::IssueFilter
    include ProjectStatePlugin::Utilities

    def whats_manually_set(issue)
      manual = {}
      if issue.tracker_id_changed?
        manual['tracker'] = {old: issue.tracker_id_was, new: issue.tracker_id}
        $pslog.debug("tracker: was: #{issue.tracker_id_was}  is: #{issue.tracker_id}")
      end
      if issue.status_id_changed?
        manual['status'] = {old: issue.status_id_was, new: issue.status_id}
        $pslog.debug("status: was: #{issue.status_id_was}  is: #{issue.status_id}")
      end

      issue.custom_field_values.each do |cfv|
        if cfv.value_was != cfv.value
          manual[cfv.custom_field_id.to_s] = {old: cfv.value_was, new: cfv.value}
          $pslog.debug("cfv: #{cfv.custom_field_id}  was: #{cfv.value_was.nil? ? 'nil' : cfv.value_was}  is: #{cfv.value.nil? ? 'nil' : cfv.value}")
        end
      end
      return manual
    end

    def send_the_mail(info,u,issue,alist)
      info[:uname] = "#{u.firstname} #{u.lastname}"
      info[:days] = days_in_state(issue)
      a = issue.assigned_to
      if a.nil?
        info[:assn] = l(:text_unassigned)
      else
        info[:assn] = "#{a.firstname} #{a.lastname}"
      end
      info[:email] = alist
      ProjectStateMailer.limit_changed_mail(issue,info).deliver_now
    end

    def email_notification(issue,notify,is_new)
      info = { is_new_issue: is_new }
      if notify.include?(:state_timeout)
        info[:timeout_new] = notify[:state_timeout][:new]
        info[:timeout_old] = notify[:state_timeout][:old]
      end
      if notify.include?(:hour_limit)
        info[:hours_new] = notify[:hour_limit][:new]
        info[:hours_old] = notify[:hour_limit][:old]
      end
      alist = alert_emails
      u = User.current
      uaddr = u.email_address.address
      alist.delete(uaddr)
      if alist.length > 0
        send_the_mail(info,u,issue,alist)
      end
    end
 
    def autoupdate_from_lims(issue,submission,ps_obj)
      nstate = submission["custom_fields"][0]["value"]
      $pslog.debug("new state: #{nstate}")
      want_change = !ps_obj.nil? && ORDERING[ps_obj.value] < ORDERING[nstate]

      if want_change && nstate == 'Submit'
        issue.status = IssueStatus.find_by(name: 'Submitted to Genomics')
        $pslog.debug("In edit_before_save, status to #{issue.status}")
      elsif want_change && nstate == 'Ready'
        issue.status = IssueStatus.find_by(name: 'Ready')
        $pslog.debug("In edit_before_save, status to #{issue.status}")
      else
        $pslog.debug("In edit_before_save, status mismatch: '#{ps_obj}' [#{ps_obj.class}]")
      end
    end

    def update_status_from_user(issue,submission,ps_obj,custom_values)
      nstate = StatusStateMapping.find_by(status: issue.status_id).state
      if nstate != ps_obj.value
        stid = CustomField.find_by(name: "State Timeout").id
        new_st = StateTimeoutDefault.find_by(state: nstate).timeout
        custom_vals[psid] = nstate
        custom_vals[stid] = new_st
        req_state = submission["custom_field_values"][psid.to_s]
        if req_state != nstate
          iss.warnings.add("State", "State set to #{nstate} to match status.")
        end
      end
    end

    def update_tracker_from_user(issue,custom_vals)
      hlid = CustomField.find_by(name: "Hour Limit").id
      hlcv = iss.custom_value_for(hlid)
      if !hlcv.nil?
        new_limit = TimeLimitDefault.find_by(tracker_id: iss.tracker_id).hours
        custom_vals[hlid] = new_limit
      end
    end

    def controller_issues_edit_before_save(**keys)
      $pslog.debug("edit before save")
      iss = keys[:issue]
      psid = CustomField.find_by(name: CUSTOM_PROJECT_STATE).id.to_s
      hlid = CustomField.find_by(name: CUSTOM_HOUR_LIMIT).id.to_s
      stid = CustomField.find_by(name: CUSTOM_STATE_TIMEOUT).id.to_s
      manual = whats_manually_set(iss)
      manual.each do |k,v|
        $pslog.debug("k: #{k}  was: #{v[:old].nil? ? 'nil' : v[:old]}  is: #{v[:new].nil? ? 'nil' : v[:new]}")
      end

      @project_state_notify = {}
      ps_custom = {}

      # Cases

      st_changed = false
      # state changed but not status: don't do that (unless moving an issue
      # to a new project, where it now needs a state)!
      # Otherwise, this case is handled elsewhere, in the validation
      # method patched into "Issue"
      if iss.project_id_changed? && manual.include?(psid) && manual[psid][:old].nil?
        # was not formerly set, so set up with defaults
        $pslog.debug("Setting state, etc to defaults...")
        st_changed = true
        st_val = StatusStateMapping.find_by(status: iss.status_id).state
        ps_custom[psid] = st_val

      # state change and status change: see if they match
      elsif manual.include?(psid) && manual.include?("status")
        nstatus = manual["status"][:new]
        nstate = manual[psid][:new]
        target = StatusStateMapping.find_by(status: nstatus).state
        if target != nstate
          ps_custom[psid] = target
        end
        st_changed = true
        st_val = target
 
      # State did not change and status did: relatively simple
      elsif !manual.include?(psid) && manual.include?("status")
        nstatus = manual["status"][:new]
        target = StatusStateMapping.find_by(status: nstatus).state
        cstate = iss.state
        if cstate != target
          ps_custom[psid] = target
          st_changed = true
          st_val = target
        end
      end

      if manual.include?(stid) && !manual[stid][:new].blank?
        @project_state_notify[:state_timeout] = manual[stid]
      else
        if st_changed
          ps_custom[stid] = StateTimeoutDefault.find_by(state: st_val).timeout.to_s
        end
      end

#      $pslog.debug("hlid: is: #{manual[hlid][:new].nil? ? 'nil' : manual[hlid][:new]} was: #{manual[hlid][:old].nil? ? 'nil' : manual[hlid][:old]}")
      if manual.include?(hlid) && !manual[hlid][:new].blank?
        @project_state_notify[:hour_limit] = manual[hlid]
      else
        if manual.include?("tracker") || (manual.include?(hlid) && manual[hlid][:new].blank?)
          ps_custom[hlid] = TimeLimitDefault.find_by(tracker_id: iss.tracker_id).hours.to_s
        end
      end

      # explicitly set the fields we need to.
      iss.custom_field_values = ps_custom
    end

    def controller_issues_edit_after_save(context={})
      $pslog.debug("edit after save")
      iss = context[:issue]
      email_notification(iss,@project_state_notify,false) if @project_state_notify.size > 0
    end

    def controller_issues_new_before_save(context={})
      $pslog.debug("new before save")
      iss = context[:issue]
      manual = whats_manually_set(iss)

      stid = CustomField.find_by(name: CUSTOM_STATE_TIMEOUT).id.to_s
      hlid = CustomField.find_by(name: CUSTOM_HOUR_LIMIT).id.to_s
      psid = CustomField.find_by(name: CUSTOM_PROJECT_STATE).id.to_s

      @project_state_notify = {}
      ps_custom = {}

      # logic: state always follows status, with no notification.
      # But hour limit and state timeout are either
      #  a) preserved but notified if the change was manual, or
      #  b) reset to the defaults with no notif.
      ps_custom[psid] = StatusStateMapping.find_by(status: iss.status_id).state
      if manual.include?(stid) && manual[stid][:old].to_i < manual[stid][:new].to_i
        @project_state_notify[:state_timeout] = manual[stid]
      else
        ps_custom[stid] = StateTimeoutDefault.find_by(state: ps_custom[psid]).timeout.to_s
      end
      if manual.include?(hlid) && manual[hlid][:old].to_i < manual[hlid][:new].to_i
        @project_state_notify[:hour_limit] = manual[hlid]
      else
        ps_custom[hlid] = TimeLimitDefault.find_by(tracker_id: iss.tracker_id).hours.to_s
      end

      # explicitly set the fields we need to.
      iss.custom_field_values = ps_custom
    end

    def controller_issues_new_after_save(context={})
      $pslog.debug("new after save")
      iss = context[:issue]
      psid = CustomField.find_by(name: CUSTOM_PROJECT_STATE).id.to_s
      cf = iss.custom_value_for(psid)
      return if cf.nil?

      journal = Journal.create(journalized_id: iss.id,
                               journalized_type: 'Issue',
                               user: User.current,
                               created_on: DateTime.now,
                               private_notes: 0) do |je|
        je.details << JournalDetail.new(property: 'cf',
                                        prop_key: psid,
                                        old_value: 'new',
                                        value: cf.value)
      end

      email_notification(iss,@project_state_notify,true) if @project_state_notify.size > 0
    end

  end
end
