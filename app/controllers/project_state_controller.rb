require 'date'
require 'set'
require 'logger'

require 'project_state/defaults'
require 'project_state/utils'
require 'project_state/issue_filter'

class ProjectStateController < ApplicationController
  include ProjectStatePlugin::Defaults
  include ProjectStatePlugin::Utilities

  unloadable

  def update(params)
    update = false
    params.keys.each do |k|
      flds = k.split('_',2)
      next if flds.length != 2
      case flds[0]
        when 'tracker'
          tid = flds[1].to_i
          hours = params[k].to_i
          tval = TimeLimitDefault.find_by(tracker_id: tid)
          if tval.nil?
            TimeLimitDefault.create(tracker_id: tid, hours: hours)
            update = true
          else
            if tval.hours != hours
              tval.hours = hours
              tval.save()
              update = true
            end
          end
        when 'state'
          sid = flds[1]
          days = params[k].to_i
          sval = StateTimeoutDefault.find_by(state: sid)
          if sval.nil?
            StateTimeoutDefault.create(state: sid, timeout: days)
            update = true
          else
            if sval.timeout != days
              sval.timeout = days
              sval.save()
              update = true
            end
          end
        when 'status'
          sid = flds[1].to_i
          stat = params[k]
          sval = StatusStateMapping.find_by(status: sid)
          if sval.nil?
            StatusStateMapping.create(status: sid, state: stat)
            update = true
          else
            if sval.state != stat
              sval.state = stat
              sval.save()
              update = true
            end
          end
      end
    end
    return update
  end

  def edit
    # check if we're admin
    @is_admin = User.current.admin
    if !@is_admin
      flash[:warning] = l(:conf_not_admin)
    end

    if update(params)
      flash[:notice] = l(:conf_fields_updated)
    end

    # generate content for tables
    ps = CustomField.find_by(name: "Project State")
    @tracker2hours = {}
    @trackers = {}
    status_ids = Set.new()
    ps.trackers.each do |t|
      id = "tracker_%d" % t.id
      tld = TimeLimitDefault.find_by(tracker: t)
      val = tld.nil? ? 0 : tld.hours
      @tracker2hours[id] = val
      @trackers[id] = t
      t.workflow_rules.each do |w|
        status_ids.add(w.old_status_id) unless w.old_status_id.nil?
        status_ids.add(w.new_status_id) unless w.new_status_id.nil?
      end
    end
    @torder = @trackers.keys.sort{|a,b| @trackers[a].name <=> @trackers[b].name}
    sarray = status_ids.each.sort
    stats = IssueStatus.where(id: sarray)
    @statuses = {}
    stats.each do |st|
      @statuses[st.id] = st
    end
    @sorder = @statuses.keys.sort{|a,b| @statuses[a].position <=> @statuses[b].position}

    @state2days = {}
    @states = {}
    @state_order = []
    INTERESTING.each do |s|
      tag = "state_%s" % s
      @state_order << tag
      @states[tag] = s
      begin
        v = StateTimeoutDefault.find_by(state: s).timeout
      rescue
        v = 0
      end
      @state2days[tag] = v
    end

    @status2state = {}
    @state_options = []
    @status_tags = {}
    ps.possible_values.each do |s|
      @state_options << [s,s]
    end 
    @sorder.each do |is|
      tag = "status_%d" % is
      begin
        v = StatusStateMapping.find_by(status: is).state
      rescue
        v = "Prepare"
      end
      @status2state[is] = v
      @status_tags[is] = tag
    end
    
  end

#  def show
#    @user = User.current
#    redirect_to "/project_state/user/%d" % @user.id
#  end

end
