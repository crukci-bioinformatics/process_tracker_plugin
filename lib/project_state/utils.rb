require 'date'

module ProjectStatePlugin
  module Utilities

    def semiString2List(s) 
      tags = s.split(';').map{ |t| t.strip }.select{|t| t.length > 0}
    end

    def includeProject(parent,pList)
      pList << parent
      Project.where(parent_id: parent.id).each do |proj|
        includeProject(proj,pList)
      end
    end

    def includedProjects
      roots = semiString2List(Setting.plugin_project_state['root_projects'])
      projList = Array.new
      roots.each do |root|
        Project.where(name: root).each do |p|
          includeProject(p,projList)
        end
      end
      return projList
    end

    def login2email(login)
      return User.find_by(login: login).email_address.address
    end

    def alert_emails 
      logins = semiString2List(Setting.plugin_project_state['alert_logins'])
      emails = logins.map{|u| login2email(u)}
    end

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
  end
end
