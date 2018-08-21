require 'logger'
require File.expand_path(File.dirname(__FILE__)+'/audit_utils')

module ProjectStatePlugin

  class JournalAuditor

    include AuditUtils

    def initialize(testing: false,loglev: ::Logger::INFO)
      $log = ::Logger.new(STDOUT)
      $log.formatter = proc { |sev,dt,prog,msg|
        dtStr = dt.strftime "%Y-%m-%d %H:%M:%S"
        "[#{dtStr}] %5s -- #{msg}\n" % sev
      }
      $log.level = loglev
      @testing = testing
      @debug = loglev == ::Logger::DEBUG
      $log.debug("Testing: #{@testing}  LogLev: #{@@logWords[loglev]}")
    end

    def issue_consistent?(iss,  dest: STDOUT)
      msgs = []
      @issue = iss
      cons = true

      j = PSJournal.new(iss)
      cons = j.consistent?(msgs)

      # check if actual status, state equal last journal entry
      last_status = j.last_status
      last_state = j.last_state
      if last_status != iss.status_id
        msgs << "Final journal status #{last_status} != current #{iss.status_id}"
        cons = false
      end
      current_ps = nil
      ps_obj = iss.custom_value_for(projectStateId)
      if !ps_obj.nil?
        current_ps = ps_obj.value
      end
      if last_state != current_ps
        msgs << "Final journal state #{last_state.nil? ? "nil" : last_state} != current #{current_ps.nil? ? "nil" : current_ps}"
        cons = false
      end

      cons = false if !audit_current_state(iss,msgs)
      
      # dump messages if not consistent
      if !cons
        dest.printf("\n%s\n",header())
        dest.printf("  Errors:\n")
        msgs.each {|m| dest.printf("    #{m}\n")}
#        dest.printf("  Trace:\n")
#        j.dump(dest: dest,wantHeader: false,indent: "  ")
      else
        dest.printf("Issue #{iss.id}: okay\n")
      end
      return cons
    end

    def audit_issues(dest: STDOUT)
      Issue.all.each do |iss|
        cons = issue_consistent?(iss,dest: dest)
      end
    end

    def correctProjectState(iss,journal)
      fixed = false
      last_state = journal.last_state
      current_state = iss.custom_value_for(projectStateId)
      $log.debug {"Last state (from journal): #{last_state.nil? ? 'nil' : last_state}  //  current state: #{current_state.nil? ? 'nil' : current_state}"}
      if current_state.nil?
        if last_state != nil # need to add a custom value
          $log.info {"#{iss.id}: adding custom value #{projectStateId} = #{last_state}"}
          iss.custom_field_values = { projectStateId => last_state }
          fixed = true
        else
          $log.debug {"#{iss.id}: current state okay"}
        end
      else
        if last_state == nil # need to remove custom value
          $log.info {"#{iss.id}: removing custom value"}
          current_state.delete()
          fixed = true
        elsif current_state.value != last_state
          $log.info {"#{iss.id}: correcting current state: #{current_state.value} => #{last_state}"}
          current_state.value = last_state
          current_state.save
          fixed = true
        else
          $log.debug {"#{iss.id}: current state okay"}
        end
      end
      return fixed
    end

    def correctHourLimitStateTimeout(iss,journal)
      psExists = !iss.custom_value_for(projectStateId).nil?
      currentHL = iss.custom_value_for(hourLimitId)
      currentST = iss.custom_value_for(stateTimeoutId)
      fixed = false
      if psExists # hour limit and state timeout should also exist
        if currentHL.nil? # need to add hour limit
          hl = journal.last_hour_limit
          iss.custom_field_values = { hourLimitId => hl }
          fixed = true
        end
        if currentST.nil?
          st = journal.last_state_timeout
          iss.custom_field_values = { stateTimeoutId => st }
          fixed = true
        end
        iss.save if fixed
      else # hour limit and state timeout should not exist
        if !currentHL.nil?
          currentHL.delete
          fixed = true
        end
        if !currentST.nil?
          currentST.delete
          fixed = true
        end
      end
    end

    def correctIssue(iss,dest)
      @issue = iss
      $log.debug {"Correcting #{header}"}

      # state correction: add, remove, or bring into sync with status
      # -- log action if any taken
      fixed = correctProjectState(iss)
      
      # hour limit, state timeout:
      # -- remove if state not present
      # -- flag problem if not present but state is (shouldn't happen)
      fixed = true if correctHourLimitStateTimeout(iss,journal)

      # fix journal to be consistent with status, state, HL, ST
#      journal = PSJournal.new iss 
#      fixed = true if  journal.correctJournal(@testing,@debug)

      if fixed
        $log.info {"#{iss.id}: repaired"}
      else
        $log.info {"#{iss.id}: okay"}
      end
      return fixed
    end

    def audit_current_state(iss,msgs)
      cons = true

      # check correct presence/absence of project state based on
      # project and tracker
      needsPS = projectNeedsPS?(iss.project_id) && trackerNeedsPS?(iss.tracker_id)
#      $log.info "#{header()} projPS: #{projectNeedsPS?(iss.project_id)}  trakPS: #{trackerNeedsPS?(iss.tracker_id)}"
      hasPS = !iss.custom_value_for(projectStateId).nil?
      if needsPS && !hasPS
        msgs << "Issue #{iss.id}: needs PS (#{projectName(iss.project_id)} / #{trackerName(iss.tracker_id)})"
        cons = false
      elsif !needsPS && hasPS
        msgs << "Issue #{iss.id}: should not have PS (#{projectName(iss.project_id)} / #{trackerName(iss.tracker_id)})"
        cons = false
      end

      # if present, check whether state matches status
      if needsPS && hasPS
        psVal = iss.custom_value_for(projectStateId).value
        expected = status2state(iss.status_id)
        if psVal != expected
          msgs << "Issue #{iss.id}: status=#{status(iss.status_id)} but state=#{psVal}"
          cons = false
        end
      end

      # If hasPS, check whether also has hour limit, state timeout.
      # Similarly, if !hasPS, ensure no hour limit, state timeout.
      if hasPS
        # ensure we have ST, HL
        hasST = !(iss.custom_value_for(stateTimeoutId).nil?)
        hasHL = !(iss.custom_value_for(hourLimitId).nil?)
        if !hasST || !hasHL
          msgs << "Issue #{iss.id}: has project state but ST = #{hasST}, HL = #{hasHL}"
          cons = false
        end
      else # no PS
        # ensure we don't have ST, HL
        hasST = !(iss.custom_value_for(stateTimeoutId).nil?)
        hasHL = !(iss.custom_value_for(hourLimitId).nil?)
        if hasST || hasHL
          msgs << "Issue #{iss.id}: no project state but ST = #{hasST}, HL = #{hasHL}"
          msgs << "    project: #{projectName(iss.project_id)}"
          msgs << "    tracker: #{trackerName(iss.tracker_id)}"
          cons = false
        end
      end
      return cons
    end

    def extra_project_states(dest: STDOUT)
      ps_id =  CustomField.find_by(name: 'Project State').id

      # make a tracker map: which ones should NOT have a project state
      trackersNoPS = {}
      Tracker.all.each do |trak|
        if trak.custom_fields.where(id: ps_id).length == 0
          trackersNoPS[trak.id] = trak
        end
      end

      Project.all.each do |proj|
        # for projects which should not have a project state
        if proj.issue_custom_fields.where(id: ps_id).length == 0
          dest.printf("Project #{proj.name} (no project state)\n")
          # for each such project, list issues which have project state
          proj.issues.each do |iss|
            ps_value = iss.custom_value_for(ps_id)
            if !ps_value.nil?
              dest.printf("   #{iss.id} #{ps_value.value} #{iss.subject.truncate(30).gsub('%','%%')}\n")
            end
          end
        else
          # for projects which might have a project state
          dest.printf("Project #{proj.name} (may have project state)\n")
          proj.issues.each do |iss|
            ps_value = iss.custom_value_for(ps_id)
            # check the tracker to see whether it should *not* have a project state
            if trackersNoPS.has_key?(iss.tracker_id) && !ps_value.nil?
              dest.printf("   #{iss.id} #{ps_value.value} #{trackersNoPS[iss.tracker_id].name} #{iss.subject.truncate(30).gsub('%','%%')}\n")
              ps_value.destroy
            end
          end
        end
      end
    end
  end
end
