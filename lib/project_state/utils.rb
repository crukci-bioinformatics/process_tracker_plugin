require 'tmpdir'
require 'i18n'
require 'set'

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

    def collectActivities(names)
      acts = semiString2List(names)
      ids = []
      acts.each do |act|
        ids  = ids + Enumeration.where(name: act, type: 'TimeEntryActivity').map{|x| x.id}
      end
      return ids
    end

    def collectIssues(projects)
      closed = IssueStatus.where(is_closed: true)
      interesting = ProjectStatePlugin::Defaults::INTERESTING
      iss_set = Issue.where.not(status: closed)
                     .where(project_id: projects)
                     .select{|i| i if interesting.include?(i.state)}
      return iss_set
    end

    def collectAllOpenIssues()
      closed = IssueStatus.where(is_closed: true)
      return Issue.where.not(status: closed)
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

    # A method that gives the standard working week at (default) 7 hours per day.
    def standard_workdays()
      workingDays = ['Mon','Tue','Wed','Thu','Fri']
      days = {}
      workingDays.each do |a|
        days[Date::ABBR_DAYNAMES.find_index(a)] = ProjectStatePlugin::Defaults::HOURS_PER_DAY
      end
      return days
    end
      
    # The proportion of a full time employee this user is.
    # Returns a float between 0 and 1.
    def workproportion(u)
      cf = UserCustomField.find_by(name: 'Proportion of Full Time')
      cv = CustomValue.find_by(customized: u, custom_field: cf)
      if cv.nil?
        cv = cf.default_value
      else
        cv = cv.value
      end
      return cv.to_f
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
        # If day is in the map of days worked, add the number of hours in that day.
        wh += dmap[d.wday] if dmap.has_key? d.wday
        d += 1
      end
      wh -= bh
      return wh
    end

    # A development of the above method, this takes the proportion
    # of a full time employee a user works (see workproportion()).
    def working_hours_by_proportion(day,proportion,interval='by_month')
      return working_hours(day, standard_workdays(), interval) * proportion
    end

    def save_file(srcfd)
      bufsize = 524288 # 2**19 = 512Kb
      td = Dir.tmpdir
      tn = Dir::Tmpname.make_tmpname("finance_",1)
      tpath = File.join(td,tn)
      dstfd = File.open(tpath,"w")
      dstfd.binmode
      buffer = srcfd.read(bufsize)
      while (!buffer.nil?) && buffer.length > 0
        dstfd.write(buffer)
        buffer = srcfd.read(bufsize)
      end
      dstfd.close
      return tpath
    end

    def get_project_costcode(proj,grants,codes)
      # find proj name in grants list, return corresponding code
      # warn if proj name occurs multiple times
      pname = I18n.transliterate(proj.name).downcase.strip
      code = Set.new()
      grants.each_with_index do |g,i|
        code.add(codes[i]) if g == pname
      end
      if code.size > 1
        $pslog.error("Non-unique code for #{pname}: #{code}")
        return nil 
      elif code.size == 0
        pslog.warn("Missing code for #{pname}")
        return nil
      end
      return code.to_a[0]
    end

    def hunt_for_swag(grants,code)
      # hunt for SWAG code in the grant names
      re = /(^|\s)([^\s]+)(\s|$)/
      matches = []
      grants.each_with_index do |g,i|
        pos = re =~ g
        next if pos.nil?
        matches << i if $2 == code
      end
      if matches.length > 1
        $pslog.warning("Multiple matches to code '#{code}' in grant table, returning first")
      end
      return matches.length > 0 ? matches[0] : nil
    end

    def boxplot_values(data)
      ds = data.sort
      if data.length == 0
        return [0,0,0,0,0]
      elsif data.length == 1
        return [data[0],data[0],data[0],data[0],data[0]]
      elsif data.length == 2
        return [ds[0],ds[0],((ds[0]+ds[1])/2.0).round(2),ds[1],ds[1]]
      end
      min = ds[0]
      max = ds[-1]
      if ds.length % 2 == 1 # odd length
        med = ds[ds.length/2]
      else
        med = (ds[ds.length/2] + ds[ds.length/2+1]) / 2.0
      end
      med = med.round(2)
      quart = ds.length / 4
      first = ds[quart]
      third  = ds[quart*3]
      return [min,first,med,third,max]
    end

  end

end
