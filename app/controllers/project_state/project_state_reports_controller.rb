require 'logger'
require 'i18n'
require 'set'

require 'simple_xlsx_reader'
require 'project_state/utils'
require 'project_state/finance'
require 'project_state/snapshot'

class ProjectState::ProjectStateReportsController < ApplicationController
  include ProjectStatePlugin::Utilities

  unloadable

  def ps_options_for_period
    return [[l(:label_last_12),"last_12"],
            [l(:label_last_6),"last_6"],
            [l(:label_last_3),"last_3"],
            [l(:label_this_year),"this_year"],
            [l(:label_last_year),"last_year"],
            [l(:label_this_fiscal),"this_fiscal"],
            [l(:label_last_fiscal),"last_fiscal"],
            [l(:label_this_quarter),"this_quarter"],
            [l(:label_last_quarter),"last_quarter"],
            [l(:label_this_month),"this_month"],
            [l(:label_last_month),"last_month"]]
  end

  def ps_options_for_interval
    return [[l(:label_by_month),"by_month"],
            [l(:label_by_week),"by_week"],
            [l(:label_by_quarter),"by_quarter"]]
  end

  def set_up_time(params,update)
    okay = true
    if update
      if ! params.has_key? "date_type"
        flash[:warning] = l(:report_choose_radio_button)
        okay = false
      elsif params['date_type'] == '1'
        case params['period_type']
        when 'last_12'
          @to = Date.today.beginning_of_month
          @from = @to << 12
          @intervaltitle = "#{@from.strftime('%Y %b')} to #{@to.strftime('%Y %b')}"
        when 'last_6'
          @to = Date.today.beginning_of_month
          @from = @to << 6
          @intervaltitle = "#{@from.strftime('%Y %b')} to #{@to.strftime('%Y %b')}"
        when 'last_3'
          @to = Date.today.beginning_of_month
          @from = @to << 3
          @intervaltitle = "#{@from.strftime('%Y %b')} to #{@to.strftime('%Y %b')}"
        when 'last_month'
          @to = Date.today.beginning_of_month
          @from = @to << 1
          @intervaltitle = "#{@from.strftime('%Y %b %-d')} to #{@to.strftime('%Y %b %-d')}"
        when 'this_month'
          @to = Date.today.end_of_month + 1
          @from = Date.today.beginning_of_month
          @intervaltitle = "#{@from.strftime('%Y %b %-d')} to #{@to.strftime('%Y %b %-d')}"
        when 'this_year'
          @to = Date.today.end_of_year + 1
          @from = Date.today.beginning_of_year
          @intervaltitle = "#{@from.strftime('%Y')}"
        when 'last_year'
          @to = Date.today.beginning_of_year
          @from = @to << 12
          @intervaltitle = "#{@from.strftime('%Y')}"
        when 'this_fiscal'
          t = Date.today
          apr = Date.new(year=t.year,month=4)
          offset = t < apr ? -1 : 0
          @from = Date.new(year=t.year+offset,month=4)
          @to = Date.new(year=t.year+offset+1,month=4)
          @intervaltitle = "#{@from.strftime('%Y %b')} to #{@to.strftime('%Y %b')}"
        when 'last_fiscal'
          t = Date.today
          apr = Date.new(year=t.year,month=4)
          offset = t < apr ? -2 : -1
          @from = Date.new(year=t.year+offset,month=4)
          @to = Date.new(year=t.year+offset+1,month=4)
          @intervaltitle = "#{@from.strftime('%Y %b')} to #{@to.strftime('%Y %b')}"
        when 'this_quarter'
          @to = Date.today.end_of_quarter+1
          @from = Date.today.beginning_of_quarter
          @intervaltitle = "#{@from.strftime('%Y %b')} to #{@to.strftime('%Y %b')}"
        when 'last_quarter'
          @to = Date.today.beginning_of_quarter
          @from = @to << 3
          @intervaltitle = "#{@from.strftime('%Y %b')} to #{@to.strftime('%Y %b')}"
        else
          $pslog.error("Unexpected period description: '#{params['period_type']}'")
          flash[:error] = l(:report_bad_period_descr,:period => params['period_type'])
          okay = false
        end
        if okay
          params['report_date_to'] = "%s" % @to
          params['report_date_from'] = "%s" % @from
        end
      elsif params['date_type'] == '2'
        begin
          if !params.has_key?('report_date_from') or params['report_date_from'].blank?
            flash[:warning] = l(:report_choose_from_date)
            okay = false
          else
            @from = Date.parse(params['report_date_from'])
          end
          if !params.has_key?('report_date_to') or params['report_date_to'].blank?
            flash[:notice] = l(:report_choose_to_date)
            @to = Date.today
          else
            @to = Date.parse(params['report_date_to'])
          end
          if okay
            @intervaltitle = "#{@from.strftime('%Y %b %-d')} to #{@to.strftime('%Y %b %-d')}"
          end
        rescue ArgumentError
          flash[:error] = l(:report_date_format_error)
          okay = false
        end
      else
        $pslog.error("Unexpected date type '#{date_type}'")
        flash[:error] = l(:report_bad_date_type,:datetype => params['date_type'])
        okay = false
      end
    end
    @periods = ps_options_for_period
    @intervals = ps_options_for_interval
    return okay
  end

  def set_up_months(params,update)
    tod = Date.today
    @fin_list = (0..11).each.map do |i|
      m = tod << i
      tag = "#{Date::ABBR_MONTHNAMES[m.month]}-#{m.strftime("%Y")}"
    end
  end

  def make_intervals
    current = @from
    @ends = []
    @labels = []
    okay = true
    real_to = [@to,Date.today].min
    case @params['interval_type']
    when 'by_month'
      while current < real_to
        @labels << Date::ABBR_MONTHNAMES[current.month]
        current = current >> 1
        @ends << current
      end
      @interval_label = 'month'
    when 'by_week'
      current = current.beginning_of_week
      @from = current
      while current < (real_to - 7)
        lweek = current + 6
        @labels << "W#{lweek.cweek}, #{Date::ABBR_MONTHNAMES[lweek.month]} #{lweek.day}"
        current = current + 7
        @ends << current
      end
      @interval_label = 'week'
    when 'by_quarter'
      while current < real_to
        q = ((current.month - 1) / 3)
        q = 4 if q == 0
        @labels << "Q#{q}"
        current = current >> 3
        @ends << current
      end
      @interval_label = 'quarter'
    else
      okay = false
      $pslog.error{"Unknown interval range '#{@params['interval_type']}'"}
      flash[:error] = l(:report_bad_interval_type,:inttype => params['interval_type'])
    end
    return okay
  end

  def time_logged_by_group()
    @times = {}
    @projects = {}
    projlist = collectProjects(Setting.plugin_project_state['root_projects'])
    Project.where(id: projlist).each do |proj|
      @projects[proj.id] = proj
      @times[proj.id] = [0] * @ends.length
    end
    ind = 0
    # can't use "find_each" here because it is incompatible with "order"
    TimeEntry.where(spent_on: @from..(@ends[-1]-1)).order(:spent_on).each do |log|
      pid = log.project_id
      if projlist.include? pid
        while log.spent_on >= @ends[ind]
          ind += 1
        end
        @times[pid][ind] += log.hours
      end
    end
    totals = @times.keys.map{|k| @times[k].sum}.sort
    @threshold = totals[-10]
    @pids = @times.keys.sort{|a,b| @projects[a].name <=> @projects[b].name}
    @make_plot = true
  end

  def billable_time()
#    projlist = collectProjects(Setting.plugin_project_state['billable'])
    leavelist = collectProjects('Leave')
    @users = {}
    @times = {}
    @absent = {}
    @frac = {}
    @wmap = {}
    Group.find_by(lastname: 'Bioinformatics Core').users.each do |u|
      next unless u.status == Principal::STATUS_ACTIVE
      @users[u.id] = u
      @times[u.id] = [0] * @ends.length
      @absent[u.id] = [0] * @ends.length
      @frac[u.id] = [0] * @ends.length
      @wmap[u.id] = workdays(u)
    end
    ind = 0
    # can't use "find_each" here because it is incompatible with "order"
    TimeEntry.where(spent_on: @from..(@ends[-1]-1)).order(:spent_on).includes(:issue).each do |log|
      u = log.user_id
      next unless @users.has_key? u
      begin
        while log.spent_on >= @ends[ind]
          ind += 1
        end
      rescue ArgumentError => ae
        $pslog.warn("AE: log.id=#{log.id}  ind=#{ind}  ends[ind]=#{@ends[ind]}  elen=#{@ends.length}")
        $pslog.warn("AE: ends[-1]=#{@ends[-1]}  logdate=#{log.spent_on}")
        next
      end
#      if projlist.include? log.project_id
#        @times[u][ind] += log.hours
#      elsif leavelist.include? log.project_id
#        @absent[u][ind] += log.hours
      if leavelist.include? log.project_id
        @absent[u][ind] += log.hours
      else
        cc = log.issue.cost_centre
        if !cc.nil? && !(cc == "")
          @times[u][ind] += log.hours
        end
      end
    end
    (0..(@ends.length - 1)).each do |i|
      @users.keys.each do |u|
        wh = working_hours(@ends[i]-1,@wmap[u],@params['interval_type'])
        hours = @times[u][i]
        expected = wh - @absent[u][i]
        if expected > 0
          @frac[u][i] = (hours / expected * 1000).to_i / 10.0
        else
          @frac[u][i] = 0.0
        end
      end
    end
    @uids = @users.keys.sort{|a,b| @users[a].firstname <=> @users[b].firstname}
    @make_plot = true
  end

  def limit_changes()
    fields = CustomField.where(name: ['Hour Limit','State Timeout'])
    fmap = {}
    fields.each {|f| fmap[f.id] = f}
    jset = Journal.where(created_on: @from..(@to - 1))
    jdetails = JournalDetail.where(journal: jset)
    jmap = {}
    jset.each {|j| jmap[j.id] = j}
    @records = []
    jdetails.each do |jd|
      next unless ((jd.property == 'cf') && fmap.has_key?(jd.prop_key.to_i))
      j = jmap[jd.journal_id]
      iss = Issue.find(j.journalized_id)
      @records << {user: j.user, when: j.created_on, field: fmap[jd.prop_key.to_i].name,
                   from: jd.old_value, to: jd.value, state: iss.state, project: iss.project.name,
                   issue: iss.id, description: iss.subject, pid: iss.project.id}
    end
    @records.sort{|a,b| a[:when] <=> b[:when]}
    @make_plot = false
  end

  def number_in_state
    projects = collectProjects(Setting.plugin_project_state['root_projects'])
    snapshot = ProjectStatePlugin::Snapshot.new(projects)
    fid = CustomField.find_by(name: 'Project State').id.to_s
    today = Date.today
    ind = @ends.length - 1
    @counts = {}
    ProjectStatePlugin::Defaults::INTERESTING.each do |s|
      @counts[s] = []
    end
    Journal.where(created_on: @from..today).includes(:journalized,:details).order(created_on: :desc).each do |j|
      next if ! projects.include?(j.journalized.project_id)
      if j.created_on < @ends[ind]
        ind -= 1
        # following is a kludge to account for the possibility that this journal entry may in fact
        # be earlier than the current interval, i.e. that the current interval contains no
        # jounals.  This seems unlikely, but still... and this doesn't cope with two empty
        # intervals.  But that's even less likely.
        if ind > 0 && j.created_on < @ends[ind]
          $pslog.info("Number in State: empty interval ending #{@ends[ind+1]}")
          ind -= 1
        end
        snap = snapshot.snap_states()
        @counts.keys.each do |s|
          if snap.has_key?(s)
            @counts[s] << snap[s]
          else
            @counts[s] << 0
          end
        end
        break if ind < 0 # skip the first interval, because we report at the end, not start,so
                         # we don't need to run through these.  Could just not load them, but
                         # I'm confused enough already.
      end
      snapshot.journal(j.journalized,j)
    end
    @counts.keys.each do |s|
      @counts[s] = @counts[s].reverse
    end
    @make_plot = true
  end

  def state_by_analyst(state)
    projects = collectProjects(Setting.plugin_project_state['root_projects'])
    today = Date.today
    ind = @ends.length - 1
    snap = ProjectStatePlugin::Snapshot.new(projects)
    @counts = {}
    @analysts = {}
    Group.find_by(lastname: 'Bioinformatics Core').users.each do |u|
      @counts[u.id] = []
      @analysts[u.id] = u
    end
    Journal.where(created_on: @from..today).includes(:journalized,:details).order(created_on: :desc).each do |j|
      next if ! projects.include?(j.journalized.project_id)
      if j.created_on < @ends[ind]
        ind -= 1
        # following is a kludge to account for the possibility that this journal
        # entry may in fact be earlier than the current interval, i.e. that the
        # current interval contains no journals.  This seems unlikely, but
        # still... and this doesn't cope with two empty intervals.  But that's
        # even less likely.
        if ind > 0 && j.created_on < @ends[ind]
          $pslog.info("Number in State: empty interval ending #{@ends[ind+1]}")
          ind -= 1
        end
        shot = snap.snap_people(state)
        @counts.keys.each do |u|
          if shot.has_key?(u)
            @counts[u] << shot[u]
          else
            @counts[u] << 0
          end
        end
        break if ind < 0
      end
      snap.journal(j.journalized,j)
    end
    @counts.keys.each do |s|
      @counts[s] = @counts[s].reverse
    end
    @keys = @counts.keys.sort{|a,b| @analysts[a].firstname <=> @analysts[b].firstname}
    @make_plot = true
  end

  def active_by_analyst
    state_by_analyst("Active")
  end

  def hold_by_analyst
    state_by_analyst("Hold")
  end

  def collapse_project(p)
    p.children.each do |kid|
      collapse_project(kid)
      src = @times[kid.id]
      dst = @times[p.id]
      (0..(src.length-1)).each {|i| dst[i] = dst[i] + src[i]}
      @projects.delete(kid.id)
    end
  end

  def collapse_projects(rg_pid)
    @projects.each do |pid,proj|
      if proj.parent_id == rg_pid
        collapse_project(proj)
      end
    end
  end

  def hours_current_and_average_csv
    io = StringIO.new(string="",mode="w")
    io.printf(",#{@avg_tag},#{@cur_tag}\n")
    (0..(@labels.length-1)).each do |i|
      tag = I18n.transliterate(@labels[i])
      io.printf("#{tag},#{@average[i]},#{@current[i]}\n")
    end
    fn = "#{@report.view}_#{@cur_tag}.csv"
    send_data(io.string,filename: fn)
  end

  def hours_current_and_average
    @times = {}
    @projects = {}
    rg_pid = Project.find_by(name: 'Research Groups').id
    projlist = collectProjects(Setting.plugin_project_state['billable'])
    projlist.delete(rg_pid)
    Project.where(id: projlist).each do |proj|
      @projects[proj.id] = proj
      @times[proj.id] = [0.0] * @ends.length
    end
    ind = 0
    # can't use "find_each" here because it is incompatible with "order"
    TimeEntry.where(spent_on: @from..(@ends[-1]-1)).order(:spent_on).each do |log|
      pid = log.project_id
      if projlist.include? pid
        begin
          while log.spent_on >= @ends[ind]
            ind += 1
          end
        rescue
          $pslog.error("ind=#{ind} len=#{@ends.length} log=#{log.spent_on} to=#{@to} ends[-1]=#{@ends[-1]}")
          break
        end
        @times[pid][ind] += log.hours
      end
    end
    collapse_projects(rg_pid)
    @current = []
    @average = []
    @pids = @projects.keys.sort{|a,b| @projects[a].name <=> @projects[b].name}
    @current_show = []
    @average_show = []
    @labels_show = []
    @pids.each do |pid|
      @current << @times[pid][-1]
      @average << (@times[pid].sum / @times[pid].length).round(2)
      if @current[-1] >= 1.0 || @average[-1] >= 1.0
        @current_show << @current[-1]
        @average_show << @average[-1]
        @labels_show << @projects[pid].name
      end
    end
    @avg_tag = "#{@labels.length} #{@interval_label} average"
    @cur_tag = @labels[-1]
    @labels = @pids.each.map{|p| @projects[p].name}
    if @params['format'] == 'csv'
      hours_current_and_average_csv
    end
    @make_plot = true
  end

  class StateChange < Struct.new(:projid,:issue,:from,:to,:when)
  end

  def state_changes(iss,state_prop_key)
    changes = []
    iss.journals.includes(:details).each do |j|
      j.details.each do |jd|
        if jd.property == 'cf' && jd.prop_key == state_prop_key
          changes << StateChange.new(iss.project_id,iss,jd.old_value,jd.value,j.created_on)
        end
      end
    end
    return changes
  end

  def find_previous_change(issue,finish,psid)
    jlist = issue.journals.where("created_on < ?",finish).order(created_on: :desc).includes(:details)
    jlist.each do |j|
      j.details.each do |jd|
        if jd.property == 'cf' && jd.prop_key == psid
          return j.created_on
        end
      end
    end
    return issue.created_on
  end

  def time_waiting()
    @projects = {}
    projlist = collectProjects(Setting.plugin_project_state['billable'])
    Project.where(id: projlist).each do |proj|
      @projects[proj.id] = proj
    end
    state_prop_key = CustomField.find_by(name: 'Project State').id.to_s
    interesting = ["Ready","Hold"]
    start = @from
    rlist = []
    hlist = []
    @ready = []
    @hold = []
    @ends.each do |fin|
      Journal.where(created_on: start..(fin-1)).includes(:details).each do |j|
        iss = j.issue
        next unless @projects.include? iss.project_id
        j.details.each do |jd|
          if jd.property == 'cf' && jd.prop_key == state_prop_key && interesting.include?(jd.old_value)
            # it's a candidate
            prev = find_previous_change(j.issue,j.created_on,state_prop_key)
            interval = ((j.created_on - prev).to_i / 86400.0).round(2)
            $pslog.debug("From: #{prev}  To: #{j.created_on}  Interval: #{interval}")
            $pslog.debug("From: #{prev.class}  To: #{j.created_on.class}  Interval: #{interval.class}")
            if jd.old_value == 'Ready'
              rlist << interval
            else
              hlist << interval
            end
          end
        end
      end
      @ready << boxplot_values(rlist)
      @hold << boxplot_values(hlist)
      rlist = []
      hlist = []
      start = fin
    end
    @make_plot = true
  end

  def opening_closing()
    start = @from
    @opening = []
    @closing = []
    @reopening = []
    state_prop_key = CustomField.find_by(name: 'Project State').id.to_s
    @ends.each do |fin|
      s = Set.new
      f = Set.new
      r = Set.new
      Journal.where(created_on: start..(fin-1)).each do |j|
        j.details.each do |jd|
          if jd.property == 'cf' && jd.prop_key == state_prop_key
#            s += 1 if jd.old_value == 'new'
#            f += 1 if jd.value == 'Post'
#            r += 1 if jd.old_value == 'Post'
            s.add(j.journalized_id) if jd.old_value == 'new'
            f.add(j.journalized_id) if jd.value == 'Post'
            r.add(j.journalized_id) if jd.old_value == 'Post'
          end
        end
      end
      @opening << s.size
      @closing << f.size
      @reopening << r.size
      start = fin
    end
    @make_plot = true
  end

  def finance_report_csv
    io = StringIO.new(string="",mode="w")
    io.printf("Grant,Code,Hours\n")
    @grants.each_with_index do |g,i|
      tag = g.nil? ? nil : I18n.transliterate(g)
      io.printf("\"#{tag}\",#{@codes[i]},#{@costs[i]}\n")
    end

    if @orphans.length > 0
      io.printf("\n\nOrphans\n")
      io.printf("\nCode,Project,Issue,User,Activity,Hours,Date,Subject\n")
      @orphans.each do |orph|
        io.printf("#{orph.code},#{orph.project},#{orph.issue},#{orph.user},#{orph.activity},#{orph.hours},#{orph.date},#{orph.descr}\n")
      end
    end

    fn = "Core_finance_#{@default_month}.csv"
    send_data(io.string,filename: fn)
  end

  class Orphan < Struct.new(:code,:project,:issue,:descr,:user,:activity,:hours,:date)
  end

  def finance_report
    if params['spreadsheet'].nil?
      flash[:error] = 'Please choose a spreadsheet.'
      @okay = false
      return
    end
     
    if params['spreadsheet'].class == String
      @tmp_spreadsheet = params['spreadsheet']
    else
      @tmp_spreadsheet = save_file(params['spreadsheet'])
    end
    @default_month = params['report_fin_interval']
    (month,year) = params['report_fin_interval'].split('-')
    sheet = FinanceSheet.new(@tmp_spreadsheet)
    data = sheet.retrieve(year[2..3],month)
    @grants = data[0]
    @codes = data[1]
    codemap = {}
    @codes.each_with_index{|c,i| codemap[c]=i}
    @costs = [0.0] * @codes.length

    projects = collectProjects(Setting.plugin_project_state['billable'])
    pstr = (projects.map{|x| sprintf("%d",x) }).join(",")
    nc_activities = collectActivities(Setting.plugin_project_state['non_chargeable'])
    cfid = CustomField.find_by(type: 'IssueCustomField', name: 'Cost Centre').id
    p = Date.parse(params['report_fin_interval'])
    @from = p.beginning_of_month
    @to = p.end_of_month + 1
    @orphans = []
    TimeEntry.where(spent_on: @from..(@to-1)).includes(:project, :issue).each do |log|
      next unless projects.include? log.project_id
      next if nc_activities.include? log.activity_id
      iss = log.issue
      code = iss.cost_centre
      ind = @codes.index(code)
      if code.nil?
        $pslog.warn("Nobody to charge for time entry #{log.id}.")
        pn = Project.find(log.project_id).name
        un = User.find(log.user_id).firstname
        an = Enumeration.find(log.activity_id).name
        @orphans << Orphan.new("",pn,log.issue_id,iss.subject,un,an,log.hours,log.spent_on)
      elsif !ind.nil?
        @costs[ind] += log.hours
      else
        row = hunt_for_swag(@grants,code)
        if row.nil?
          $pslog.warn("No cost code matching #{code}, log=#{log.id}")
          pn = Project.find(log.project_id).name
          un = User.find(log.user_id).firstname
          an = Enumeration.find(log.activity_id).name
          @orphans << Orphan.new(code,pn,log.issue_id,iss.subject,un,an,log.hours,log.spent_on)
        else
          @costs[row] += log.hours
        end
      end
    end
    if @params['format'] == 'csv'
      finance_report_csv
    end
    make_plot = false
  end

  def index
    @reports = ProjectStateReport.all
    @reports.sort{|a,b| a.ordering <=> b.ordering}
  end

  def show
    flash.clear
    @report = ProjectStateReport.find(params[:id].to_i)
    @params = params
    if @report.dateview == 'form_dates'
      @okay = set_up_time(params,false)
    else
      @okay = set_up_months(params,false)
      @default_month = @fin_list[1]
    end
    @make_plot = false
  end

  def update
#    $pslog.warn("In the update controller...")
    flash.clear
    @report = ProjectStateReport.find(params[:id].to_i)
    @params = params
#    @params.keys.each do |x|
#      $pslog.warn("param: #{x} == #{@params[x]}")
#    end
#    if params.has_key? "format"
#      $pslog.info("Before!")
#      send_data("zork",filename: "thing.txt")
#      $pslog.info("After!")
#    end
    if @report.dateview == 'form_dates'
      @okay = set_up_time(params,true)
    else
      @okay = set_up_months(params,false)
    end
    if @okay && @report.want_interval
      @okay = make_intervals
    end
    if @okay
      send(@report.view)
    end
  end

end
