require 'date'
require_dependency File.expand_path(File.dirname(__FILE__)+'/utils')
require_dependency File.expand_path(File.dirname(__FILE__)+'/issue_filter')

module ProjectStatePlugin
  class Hooks < Redmine::Hook::Listener

    include ProjectStatePlugin::IssueFilter
    include ProjectStatePlugin::Utilities

    def controller_issues_new_after_save(context={})
      psid = CustomField.find_by(name: 'Project State').id
      iss = context[:issue]
      cf = iss.custom_values.where(custom_field_id: psid)
      stid = CustomField.find_by(name: 'State Timeout')
      hlid = CustomField.find_by(name: 'Hour Limit')
      context[:issue].custom_values.each do |cval|
        if cval.custom_field_id == stid.id
          if cf.length > 0
            cval.value = StateTimeoutDefault.find_by(state: cf[0].value).timeout.to_s
          elsif
            cval.value = StateTimeoutDefault.find_by(state: 'Prepare').timeout.to_s
          end
          cval.save
        elsif cval.custom_field_id == hlid.id
          cval.value = TimeLimitDefault.find_by(tracker_id: iss.tracker_id).hours.to_s
          cval.save
        end
      end
    end

    def controller_issues_edit_after_save(context={})
      j = context[:journal]
      iss = context[:issue]
      if !j.nil? && j.journalized_type == 'Issue'
        psid = CustomField.find_by(name: 'Project State').id
        hlid = CustomField.find_by(name: 'Hour Limit').id
        stid = CustomField.find_by(name: 'State Timeout').id
        info = {}
        j.details.each do |jd|
          if jd.property == 'cf' && jd.prop_key == psid.to_s
            if jd.old_value.nil?
              jd.old_value = 'new'
            end
            # update state timeout
            cvals = CustomValue.where(customized: iss).where(custom_field_id: stid)
            if cvals.length > 0
              cval = cvals[0]
              begin
                ndef = StateTimeoutDefault.find_by(state: jd.value).timeout.to_s
              rescue NoMethodError
                ndef = 20
              end
              cval = CustomValue.where(customized: iss).find_by(custom_field_id: stid)
              cval.value = ndef
              cval.save
            end
          elsif jd.property == 'attr' && jd.prop_key == 'tracker_id'
            # update time limit
            cvals = CustomValue.where(customized: iss).where(custom_field_id: hlid)
            if cvals.length > 0
              cval = cvals[0]
              ndef = TimeLimitDefault.find_by(tracker_id: iss.tracker_id).hours.to_s
              cval.value = ndef
              cval.save
            end
          elsif jd.property == 'cf' && jd.prop_key == hlid.to_s
            if jd.value.to_i > jd.old_value.to_i
              info[:hours_old] = jd.old_value
              info[:hours_new] = jd.value
            end
          elsif jd.property == 'cf' && jd.prop_key == stid.to_s
            if jd.value.to_i > jd.old_value.to_i
              info[:timeout_old] = jd.old_value
              info[:timeout_new] = jd.value
            end
          end
        end
        if info.has_key?(:hours_new) || info.has_key?(:timeout_new)
          alist = alert_emails
          u = User.current
          uaddr = u.email_address.address
          if !(alist.include?(uaddr))
            info[:uname] = "#{u.firstname} #{u.lastname}"
            info[:days] = days_in_state(iss)
            a = iss.assigned_to
            if a.nil?
              info[:assn] = "Unassigned"
            else
              info[:assn] = "#{a.firstname} #{a.lastname}"
            end
            info[:email] = alist
            ProjectStateMailer.limit_changed_mail(iss,info).deliver_now
          end
        end
      end
    end
  end
end
