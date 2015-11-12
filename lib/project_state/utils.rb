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
      closed = IssueStatus.where(is_closed: true)
      interesting = ProjectStatePlugin::Defaults::INTERESTING
      iss_set = Issue.where.not(status: closed)
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

    def workdays(u)
      cf = UserCustomField.find_by(name: 'Working Week')
      cv = CustomValue.find_by(customized: u, custom_field: cf)
      if cv.nil?
        cv = cf.default_value
      else
        cv = cv.value
      end
      days = {}
      cv.split(";").each do |dv|
        (a,b) = dv.split(":")
        days[Date::ABBR_DAYNAMES.find_index(a)] = b.to_f
      end
      return days
    end

    def working_hours(day,dmap,interval='by_month')
      # returns number of working hours in period that includes this day
      # recognized periods are "by_week", "by_month", "by_quarter"
      case interval
      when 'by_week'
        first = day - day.wday
        last = first + 7
      when 'by_month'
        first = day.beginning_of_month
        last = first.next_month
      when 'by_quarter'
        first = day.beginning_of_quarter
        last = day.end_of_quarter + 1
      else
        $pslog.error{"Illegal interval '#{interval}', cannot continue."}
        abort("Goodbye...")
      end
      bh = BankHoliday.where(holiday: first..(last-1)).length * ProjectStatePlugin::Defaults::HOURS_PER_DAY
      d = first
      wh = 0
      while d < last
        wh += dmap[d.wday] if dmap.has_key? d.wday
        d += 1
      end
      wh -= bh
      return wh
    end

  end

end
