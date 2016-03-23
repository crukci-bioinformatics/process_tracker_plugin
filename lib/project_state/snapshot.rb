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

  class HistEntry < Struct.new(:journal,:when,:details)
  end
  class HistDetail < Struct.new(:from,:to)
  end

  class History
    include ProjectStatePlugin::Utilities
    @@statusMap = {}
    
    def initialize(issue)
      if @@statusMap.length == 0
        IssueStatus.all.each{|is| @@statusMap[is.id] = is.name}
      end
      psid = CustomField.find_by(name: "Project State").id.to_s
      stid = "status_id"
      @issue = issue
      @trail = []
      issue.journals.each do |j|
        t = HistEntry.new(j.id,j.created_on,{})
        j.details.each do |jd|
          if jd.property == 'cf' && jd.prop_key == psid
            t.details['state'] = HistDetail.new(jd.old_value,jd.value)
          elsif  jd.property == 'attr' && jd.prop_key == stid
            t.details['status'] = HistDetail.new(@@statusMap[jd.old_value.to_i],@@statusMap[jd.value.to_i])
          end
        end
        if t.details.length > 0
          @trail << t
        end
      end
      @trail.sort!{|a,b| a.when <=> b.when}
    end

    def dump(dest: STDOUT)
      @trail.each do |j|
        dstr = "#{j.when} [#{j.journal}]: "
        blank = ' ' * dstr.length
#        dest.printf "#{j.when}:\n"
        first = true
        j.details.each do |k,v|
          dest.printf("#{dstr}#{k} : #{v.from} => #{v.to}\n") if first
          dest.printf("#{blank}#{k} : #{v.from} => #{v.to}\n") if !first
          first = false
        end
      end
    end

    def first()
      ind = 0
      while !@trail[ind].details.include?('state')
        ind += 1
      end
      return @trail[ind]
    end

    def consistent?(dest: STDOUT)
      state = "new"
      status = nil
      cons = true
      @trail.each do |j|
        j.details.each do |k,v|
          if k == 'state'
            if v.from != state
              cons = false
              dest.printf("Iss #{@issue.id} journal #{j.journal} state: expected=#{state} from=#{v.from}\n")
            end
            state = v.to
          elsif k == 'status'
            if !status.nil? && v.from != status
              cons = false
              dest.printf("Iss #{@issue.id} journal #{j.journal} status: expected=#{status} from=#{v.from}\n")
            end
            status = v.to
          end
        end
      end
      return cons
    end
  end

  class JournalAuditor

    def issue_consistent?(iss: nil, iss_id: nil, dest: STDOUT)
      iss = Issue.find(iss_id) if iss.nil?
      h = History.new(iss)
      cons = h.consistent?(dest: dest)
      h.dump(dest: dest) if !cons
      return cons
    end

    def audit_issues(dest: STDOUT)
      closed = IssueStatus.where(is_closed: true)
      proj_state = CustomField.find_by(name: 'Project State').id
      Issue.where.not(status: closed).each do |iss|
        next if iss.custom_value_for(proj_state).nil?
        dest.printf("Issue #{iss.id}: #{iss.subject.truncate(50)}\n")
        cons = issue_consistent?(iss: iss,dest: dest)
        add_new(iss_id: iss.id) if !cons
      end
    end

    def add_new(iss_id: nil, dest: STDOUT)
      return if iss_id.nil?
      iss = Issue.find(iss_id)
      return if iss.nil?
      h = History.new(iss)
      hentry = h.first
      thing = hentry.details['state']
      if thing.from != "new"
        psid = CustomField.find_by(name: ProjectStatePlugin::Defaults::CUSTOM_PROJECT_STATE).id.to_s
        journal = Journal.create(journalized_id: iss_id,
                                 journalized_type: 'Issue',
                                 user: User.current,
                                 created_on: iss.created_on,
                                 private_notes: 0) do |je|
          je.details << JournalDetail.new(property: 'cf',
                                          prop_key: psid,
                                          old_value: 'new',
                                          value: thing.from)
        end
      end
    end
      
  end
end
