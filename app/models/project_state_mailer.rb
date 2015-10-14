class ProjectStateMailer < ActionMailer::Base

  include Redmine::I18n
  include ProjectStatePlugin::Utilities

  default from: "redmine-notlistening@cruk.cam.ac.uk"
  layout 'mailer'

  def limit_changed_mail(issue,notes)
    @issue = issue
    @notes = notes
    @url = url_for(host: Setting.host_name, controller: 'issues', action: 'show', id: issue.id, only_path: false)
    begin
      subs = []
      if notes.has_key?(:hours_new)
        subs << l(:email_hour_limit_subj,:hours_old => notes[:hours_old],
                                         :hours_new => notes[:hours_new])
      end
      if notes.has_key?(:timeout_new)
        subs << l(:email_state_timeout_subj,:timeout_old => notes[:timeout_old],
                                            :timeout_new => notes[:timeout_new])
      end
      sub = l(:text_issue) + " #{issue.id}: " + subs.join(', ')
      mail(to: notes[:email], subject: sub)
    rescue Exception => e
      STDERR.printf("%s\n",e)
    end
  end

end
