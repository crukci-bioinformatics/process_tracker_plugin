require 'project_state/utils'

class ProjectState::ProjectStateReportsController < ApplicationController
  include ProjectStatePlugin::Utilities
  include ProjectStatePlugin::Logger

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
          if @okay
            @intervaltitle = "#{@from.strftime('%Y %b %-d')} to #{@to.strftime('%Y %b %-d')}"
          end
        rescue ArgumentError
          flash[:error] = l(:report_date_format_error)
          okay = false
        end
      end
    end
    @periods = ps_options_for_period
    @intervals = ps_options_for_interval
    return okay
  end

  def make_intervals
    current = @from
    @ends = []
    @labels = []
    okay = true
    case @params['interval_type']
    when 'by_month'
      while current < @to
        @labels << Date::ABBR_MONTHNAMES[current.month]
        current = current >> 1
        @ends << current
      end
    when 'by_week'
      while current < @to
        @labels << "W#{current.cweek}, #{Date::ABBR_MONTHNAMES[current.month]} #{current.day}"
        current = current + 7
        @ends << current
      end
    when 'by_quarter'
      while current < @to
        q = ((current.month - 1) / 3)
        q = 4 if q == 0
        @labels << "Q#{q}"
        current = current >> 3
        @ends << current
      end
    else
      okay = false
      $pslog.error{"Unknown interval range '#{@params['interval_type']}'"}
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
    TimeEntry.where(spent_on: @from..(@to-1)).order(:spent_on).each do |log|
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
    projlist = collectProjects('Research Groups')
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
    TimeEntry.where(spent_on: @from..(@to-1)).order(:spent_on).each do |log|
      u = log.user_id
      next unless @users.has_key? u
      while log.spent_on >= @ends[ind]
        ind += 1
      end
      if projlist.include? log.project_id
        @times[u][ind] += log.hours
      elsif leavelist.include? log.project_id
        @absent[u][ind] += log.hours
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
#        if @frac[u][i] >= 100.0
#          $pslog.warn("user: #{u}  hours: #{hours}  expected: #{expected}  wh: #{wh}  absent: #{@absent[u][i]}  date: #{@ends[i]}")
#        end
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

  def current_count_in_state
    projlist = collectProjects(Setting.plugin_project_state['root_projects'])
    nc = IssueStatus.where(is_closed: false)
    issues = Issue.where(status: nc).where(project_id: projlist)
    cf = CustomField.find_by(name: 'Project State')
    counts = Hash.new(0)
    CustomValue.where(customized: issues).where(custom_field_id: cf.id).each do |cv|
      counts[cv.value] = counts[cv.value] + 1
    end
    return counts
  end

  def number_in_state
    current = current_count_in_state()
    fid = CustomField.find_by(name: 'Project State').id.to_s
    today = Date.today
    ind = @ends.length - 1
    @counts = {}
    ProjectStatePlugin::Defaults::INTERESTING.each do |s|
      @counts[s] = []
      $pslog.info{"Current #{s}: #{current[s]}"}
    end
    Journal.where(created_on: @from..today).order(created_on: :desc).each do |j|
      if j.created_on < @ends[ind]
        ind -= 1
        @counts.keys.each do |s|
          @counts[s] << current[s]
        end
        break if ind < 0
      end
      j.details.each do |jd|
        if jd.property == 'cf' && jd.prop_key == fid
          if @counts.keys.include? jd.value
            current[jd.value] -= 1
            $pslog.info("Decrementing '#{jd.value} (#{current[jd.value]})")
          end
          if @counts.keys.include? jd.old_value
            current[jd.old_value] += 1
            $pslog.info("Incrementing '#{jd.old_value} (#{current[jd.old_value]})")
          end
        end
      end
    end
    @counts.keys.each do |s|
      @counts[s] = @counts[s].reverse
    end
    @make_plot = true
  end

  def active_by_analyst
    current = current_count_in_state()
    fid = CustomField.find_by(name: 'Project State').id.to_s
    today = Date.today
    ind = @ends.length - 1
    @counts = {}
    ProjectStatePlugin::Defaults::INTERESTING.each do |s|
      @counts[s] = []
      $pslog.info{"Current #{s}: #{current[s]}"}
    end
    Journal.where(created_on: @from..today).order(created_on: :desc).each do |j|
      if j.created_on < @ends[ind]
        ind -= 1
        @counts.keys.each do |s|
          @counts[s] << current[s]
        end
        break if ind < 0
      end
      j.details.each do |jd|
        if jd.property == 'cf' && jd.prop_key == fid
          if @counts.keys.include? jd.value
            current[jd.value] -= 1
            $pslog.info("Decrementing '#{jd.value} (#{current[jd.value]})")
          end
          if @counts.keys.include? jd.old_value
            current[jd.old_value] += 1
            $pslog.info("Incrementing '#{jd.old_value} (#{current[jd.old_value]})")
          end
        end
      end
    end
    @counts.keys.each do |s|
      @counts[s] = @counts[s].reverse
    end
    @make_plot = true
  end

  def index
    @reports = ProjectStateReport.all
    @reports.sort{|a,b| a.ordering <=> b.ordering}
  end

  def show
    flash.clear
    @report = ProjectStateReport.find(params[:id].to_i)
    @params = params
    @okay = set_up_time(params,false)
    @make_plot = false
  end

  def update
    flash.clear
    @report = ProjectStateReport.find(params[:id].to_i)
    @params = params
    @okay = set_up_time(params,true)
    if @okay && @report.want_interval
      @okay = make_intervals
    end
    if @okay
      send(@report.view)
    end
  end

end
