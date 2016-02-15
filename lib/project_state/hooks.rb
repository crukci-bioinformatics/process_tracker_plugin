require 'date'
require 'stringio'
require_dependency File.expand_path(File.dirname(__FILE__)+'/utils')
require_dependency File.expand_path(File.dirname(__FILE__)+'/issue_filter')

module ProjectStatePlugin
  class Hooks < Redmine::Hook::Listener

    include Redmine::I18n
    include ProjectStatePlugin::Defaults
    include ProjectStatePlugin::IssueFilter
    include ProjectStatePlugin::Utilities

#    def controller_issues_edit_before_save(**keys)
#      cvid = CustomField.find_by(name: "Project State").id
#      iss = keys[:issue]
#      cv = iss.custom_value_for(cvid)
#      $pslog.debug("CV pre: #{cv.value}")
#      cv.value = "Prepare"
#      STDERR.printf("ZORK ZORK ZORK\n")
#      keys[:params]["issue"]["custom_field_values"]["18"] = "Prepare"
      
#      iss.custom_field_values = {"18" => "Prepare"}
#      $pslog.debug("Keys:")
#      keys.each do |k,v|
#        if k == :params
#          v.each do |p,v1|
#            next if p == "issue"
#            $pslog.debug("param: '#{p}' [#{p.class}] --> #{v1}")
#          end
#        elsif k == :journal
#          $pslog.debug("journal: #{v.journalized_type}, #{v.user_id}")
#          v.details.each do |d|
#            $pslog.debug("  jd: #{d.property}:#{d.prop_key} #{old_value} -> #{new_value}")
#          end
#        elsif k == :issue
#          v.custom_values.each do |cv|
#            $pslog.debug("CV: #{cv.custom_field_id} == #{cv.value}")
#          end
#          $pslog.debug("Methods: #{v.methods.sort}")
#        elsif k == :request
#          $pslog.debug("Request: #{v.inspect}")
#        else
#          $pslog.debug("#{k} --> #{v}")
#        end
#      end
#      $pslog.debug("issue: #{issue.id}")
#      $pslog.debug("cv's: #{issue.custom_values}")
#      $pslog.debug("journal: #{journal}")
#    end

    def controller_issues_new_after_save(context={})
     begin
      psid = CustomField.find_by(name: CUSTOM_PROJECT_STATE).id
      iss = context[:issue]
      cf = iss.custom_values.find_by(custom_field_id: psid)
      journal = Journal.create(journalized_id: iss.id,
                               journalized_type: 'Issue',
                               user: User.current,
                               created_on: DateTime.now,
                               private_notes: 0) do |je|
        je.details << JournalDetail.new(property: 'cf',
                                        prop_key: psid.to_s,
                                        old_value: 'new',
                                        value: cf.value)
      end
      stid = CustomField.find_by(name: CUSTOM_STATE_TIMEOUT)
      hlid = CustomField.find_by(name: CUSTOM_HOUR_LIMIT)
      context[:issue].custom_values.each do |cval|
        if cval.custom_field_id == stid.id
          cval.value = StateTimeoutDefault.find_by(state: cf.value).timeout.to_s
          cval.save
        elsif cval.custom_field_id == hlid.id
          cval.value = TimeLimitDefault.find_by(tracker_id: iss.tracker_id).hours.to_s
          cval.save
        end
      end
     rescue
      $pslog.info("failed in save")
     end
    end

    def controller_issues_edit_after_save(context={})
     return
     begin
      j = context[:journal]
      iss = context[:issue]
      if !j.nil? && j.journalized_type == 'Issue'
        psid = CustomField.find_by(name: CUSTOM_PROJECT_STATE).id
        hlid = CustomField.find_by(name: CUSTOM_HOUR_LIMIT).id
        stid = CustomField.find_by(name: CUSTOM_STATE_TIMEOUT).id
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
            sol = User.find_by(login: 'solexa')
            u = User.current
            if sol == u
              if jd.value == 'Submit'
                # set status to 'submitted to genomics'
                iss.status = IssueStatus.find_by(name: 'Submitted to Genomics')
                iss.save
              elsif jd.value == 'Ready'
                # set status to 'Ready'
                iss.status = IssueStatus.find_by(name: 'Ready')
                iss.save
              end
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
          alist.delete(uaddr)
          if alist.length > 0
            info[:uname] = "#{u.firstname} #{u.lastname}"
            info[:days] = days_in_state(iss)
            a = iss.assigned_to
            if a.nil?
              info[:assn] = l(:text_unassigned)
            else
              info[:assn] = "#{a.firstname} #{a.lastname}"
            end
            info[:email] = alist
            ProjectStateMailer.limit_changed_mail(iss,info).deliver_now
          end
        end
      end
     rescue
       $pslog.info("failed in edit")
     end
    end
  end
end
