require 'date'

module ProjectStatePlugin
  module Utilities

    def semiString2List(s) 
      tags = s.split(';').map{ |t| t.strip }.select{|t| t.length > 0}
    end

    def includeProject(parent,pList)
      pList << parent.id
      Project.where(parent_id: parent.id).each do |proj|
        includeProject(proj,pList)
      end
    end

    def collectProjects(names)
      roots = semiString2List(names)
      projList = Array.new
      roots.each do |root|
        Project.where(name: root).each do |p|
          includeProject(p,projList)
        end
      end
      return projList
    end

    def collectIssues(projects)
      closed = IssueStatus.find_by(name: 'Closed').id
      interesting = ProjectStatePlugin::Defaults::INTERESTING
      iss_set = Issue.where.not(status_id: closed)
                     .where(project_id: projects)
                     .select{|i| i if interesting.include?(i.state)}
      return iss_set
    end

    def login2email(login)
      return User.find_by(login: login).email_address.address
    end

    def alert_emails 
      logins = semiString2List(Setting.plugin_project_state['alert_logins'])
      emails = logins.map{|u| login2email(u)}
    end

    def url_params(params)
      parms = {}
      if params.has_key? :id
        parms[:id] = params[:id]
      end
      if params[:report] == 'stark'
        parms[:stark]
      end
      return parms
    end
  end
end
