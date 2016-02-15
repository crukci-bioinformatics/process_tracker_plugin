require 'logger'

require_dependency File.expand_path(File.dirname(__FILE__)+'/../project_state/utils')

module ProjectStatePlugin

  class Snapshot
    include ProjectStatePlugin::Utilities

    def initialize(projects)
      @owners = {}
      @states = {}
      @statuses = {}
      @trackers = {}
      @open = IssueStatus.where(is_closed: false).map{|x| x.id}
      tnames = semiString2List(Setting.plugin_project_state['ignore_trackers'])
      @trackers_ignore = Tracker.where(name: tnames).map{|t| t.id}
      @state_field = CustomField.find_by(name: 'Project State').id.to_s
      Issue.where(project_id: projects).where(status: @open).includes(:custom_values).each do |iss|
        id = iss.id
        @owners[id] = iss.assigned_to_id
        @states[id] = iss.state
        @statuses[id] = iss.status_id
        @trackers[id] = iss.tracker_id
      end
    end

    def journal(iss,j)
      if ! @owners.has_key?(iss.id)
        @owners[iss.id] = iss.assigned_to_id
        @states[iss.id] = iss.state
        @statuses[iss.id] = iss.status_id
        @trackers[iss.id] = iss.tracker_id
      end
      j.details.each do |jd|
        if jd.property == 'cf' && jd.prop_key == @state_field
          $pslog.warn("Inconsistency: issue=#{iss.id}  jstate=#{jd.value}  istate=#{@states[iss.id]}") if jd.value != @states[iss.id]
          @states[iss.id] = jd.old_value
        elsif jd.property=='attr' && jd.prop_key=='assigned_to_id'
          $pslog.warn("Inconsistency: issue=#{iss.id}  jowner=#{jd.value}  iowner=#{@owners[iss.id]}") if ((!jd.value.nil?) && (jd.value.to_i != @owners[iss.id]))
          @owners[iss.id] = jd.old_value.to_i
        elsif jd.property=='attr' && jd.prop_key=='status_id'
          $pslog.warn("Inconsistency: issue=#{iss.id}  jstatus=#{jd.value}  istatus=#{@statuses[iss.id]}") if jd.value.to_i != @statuses[iss.id]
          @statuses[iss.id] = jd.old_value.to_i
        elsif jd.property=='attr' && jd.prop_key=='tracker_id'
          $pslog.warn("Inconsistency: issue=#{iss.id}  jtracker=#{jd.value}  itracker=#{@trackers[iss.id]}") if ((!jd.value.nil?) && (jd.value.to_i != @trackers[iss.id]))
          @trackers[iss.id] = jd.old_value.to_i
        end
      end
    end

    def snap_states
      counts = Hash.new(0)
      @states.keys.each do |k|
        next if @trackers_ignore.include? @trackers[k]
        counts[@states[k]] = counts[@states[k]] + 1 if @open.include?(@statuses[k])
      end
      return counts
    end

    def snap_people(state)
      counts = Hash.new(0)
      @states.keys.each do |k|
        next if @trackers_ignore.include? @trackers[k]
        if @states[k] == state && @open.include?(@statuses[k])
          counts[@owners[k]] = counts[@owners[k]] + 1
        end
      end
      return counts
    end
  end

  class JournalAuditor

    def audit(iss_id)
      psid = "#{CustomField.find_by(name: "Project State").id}"
      iss = Issue.find(iss_id)
      iss.journals.order(:created_on).includes(:details).each do |j|
        u = User.find(j.user_id)
        j.details.each do |jd|
          if jd.property == "cf" && jd.prop_key == psid
            STDOUT.printf("#{j.created_on} [#{j.id}]: state change: #{jd.old_value} --> #{jd.value} [#{u.firstname}]\n")
          elsif jd.property == "attr" && jd.prop_key == "status_id"
            os = IssueStatus.find(jd.old_value.to_i)
            ns = IssueStatus.find(jd.value.to_i)
            STDOUT.printf("#{j.created_on} [#{j.id}]: status change: #{os.name} --> #{ns.name} [#{u.firstname}]\n")
          end
        end
      end
    end

  end
end
