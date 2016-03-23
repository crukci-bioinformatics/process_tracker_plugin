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

  def was_updated(params)
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
          sval = StatusTimeoutDefault.find_by(status: sid)
          if sval.nil?
            StatusTimeoutDefault.create(status: sid, timeout: days)
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

    if was_updated(params)
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
    end
    @torder = @trackers.keys.sort{|a,b| @trackers[a].name <=> @trackers[b].name}

    @status2days = {}
    @statuses = {}
    @statusTimeout_labels = {}
    @statusTimeout_tags = {}
    StatusTimeoutDefault.all.each do |s|
      stat = IssueStatus.find(s.status)
      @statuses[s.status] = stat
      @status2days[s.status] = s.timeout
      @statusTimeout_labels[s.status] = "%s (%s)" % [stat.name,StatusStateMapping.find_by(status: stat.id).state]
      @statusTimeout_tags[s.status] = "state_%d" % s.status
    end
    @sorder = @statuses.keys.sort{|a,b| @statuses[a].position <=> @statuses[b].position}

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

end
