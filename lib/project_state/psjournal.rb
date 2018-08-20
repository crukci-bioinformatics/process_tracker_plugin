require File.expand_path(File.dirname(__FILE__)+'/audit_utils')

module ProjectStatePlugin

  class JournalEntry < Struct.new(:journal,:when,:who,:details)
  end
  class JournalDetailFT < Struct.new(:id,:from,:to)
  end
  class IssueState < Struct.new(:status,:state,:timeout,:hours,:project,:tracker,:journal)
  end

  class PSJournal
    include AuditUtils

    def initialize(issue)
#      setup
      @issue = issue
      @trail = []
      @states = []
#      if @@projectStateId.nil?
#        @@projectStateId = CustomField.find_by(name: "Project State").id
#      end
      populateTrail
      calculateInitialState
      calculateStates
    end

    # read journal entries for this issue, make a local copy (simplified)
    def populateTrail()
      psid = projectStateId.to_s
      stid =  CustomField.find_by(name: "State Timeout").id.to_s
      hlid =  CustomField.find_by(name: "Hour Limit").id.to_s
      attrs = ["tracker_id","project_id","status_id"]

      @issue.journals.each do |j|
        t = JournalEntry.new(j.id,j.created_on,j.user_id,{})
        j.details.each do |jd|
          if jd.property == 'cf' && jd.prop_key == psid
            t.details['state'] = JournalDetailFT.new(jd.id,jd.old_value,jd.value)
          elsif jd.property == 'cf' && jd.prop_key == stid
            t.details['timeout'] = JournalDetailFT.new(jd.id,jd.old_value,jd.value)
          elsif jd.property == 'cf' && jd.prop_key == hlid
            t.details['hours'] = JournalDetailFT.new(jd.id,jd.old_value,jd.value)
          elsif  jd.property == 'attr' && attrs.include?(jd.prop_key)
            tag = jd.prop_key.gsub("_id","")
            t.details[tag] = JournalDetailFT.new(jd.id,jd.old_value.to_i,jd.value.to_i)
          end
        end
        if t.details.length > 0
          @trail << t
        end
      end
      @trail.sort!{|a,b| a.when <=> b.when}
    end

    # calculate initial state:
    #   - look for journal entries for each of the fields, oldest to newest
    #   - use the oldest that includes this field, using the "old_value"
    #     as the initial value
    #   - If you don't find a journal entry referring to this field, then
    #     use the value from the issue itself.
    def calculateInitialState()
      first = IssueState.new(nil,nil,nil,nil,nil,nil,nil)
      isSet = IssueState.new(false,false,false,false,false,false,false)

      # try to populate from journal entries
      @trail.each do |entry|
        entry.details.each_pair do |k,v|
#          puts "found transition: #{k}: #{v.from} -> #{v.to}"
          if !isSet[k]
            first[k] = v.from
            isSet[k] = true
          end
        end
#        puts "intermediate state: #{first.to_s}"
      end
#      puts "first state: #{first.to_s}"
   
      # for ones that are still nil, populate from the issue itself
      first.status = @issue.status_id if !isSet.status
      first.project = @issue.project_id if !isSet.project
      first.tracker = @issue.tracker_id if !isSet.tracker
      # have to work a bit harder for the state etc
      if !isSet.state
        ps_obj = @issue.custom_value_for(projectStateId)
        if !ps_obj.nil?
          first.state = ps_obj.value
        end
      end
      if !isSet.timeout
        st_obj = @issue.custom_value_for(stateTimeoutId)
        if !st_obj.nil?
          first.timeout = st_obj.value
        end
      end
      if !isSet.hours
        hl_obj = @issue.custom_value_for(hourLimitId)
        if !hl_obj.nil?
          first.hours = hl_obj.value
        end
      end
      first.journal = "00000"
#      puts "first state: #{first.to_s}"
      @states.clear
      @states << first
    end

    # calculate "current" state after each journal entry:
    #   status, state, project, tracker, hour limit, state timeout
    def calculateStates()
      @trail.each do |entry|
        previous = @states[-1]
        nextState = IssueState.new(*previous)
        nextState.journal = entry.journal
        entry.details.each_pair do |k,v|
          nextState[k] = v.to
        end
        @states << nextState
      end
    end

    def dumpJEntry(entry,dest,indent)
      who = User.find(entry.who).firstname
      dest.printf("#{indent}      [#{entry.when}]  #{entry.journal}  #{who}\n")
      entry.details.each_pair do |k,v|
        f,t = (v.from.nil? ? "nil" : status(v.from)),(v.to.nil? ? "nil" : status(v.to)) if k == "status"
        f,t = trackerName(v.from),trackerName(v.to) if k == "tracker"
        f,t = projectName(v.from),projectName(v.to) if k == "project"
        f,t = v.from.nil? ? "nil" : v.from,v.to.nil? ? "nil" : v.to if k == "state"
        f,t = v.from.nil? ? "nil" : v.from,v.to.nil? ? "nil" : v.to if k == "timeout"
        f,t = v.from.nil? ? "nil" : v.from,v.to.nil? ? "nil" : v.to if k == "hours"
        dest.printf("#{indent}        #{k} : #{f} -> #{t}\n")
      end
    end

    def dumpTrail(dest: STDOUT)
      dest.printf("Issue #{@issue.id}: #{tidySubject(@issue.subject)}\n")
      @trail.each do |t|
        dumpJEntry(t,dest)
      end
    end

    def dumpState(s,dest,indent)
      msg = sprintf("%s  %s:  %s / %s / %s / %s / %s / %s\n",\
                    indent, \
                    s.journal, \
                    status(s.status).nil? ? "unknown" : status(s.status), \
                    s.state.nil? ? "nil" : s.state, \
                    s.timeout.nil? ? "nil" : s.timeout, \
                    s.hours.nil? ? "nil" : s.hours, \
                    trackerName(s.tracker), \
                    projectName(s.project))
      dest.printf(msg)
    end

    def dumpStates(dest: STDOUT)
      dest.printf("Issue #{@issue.id}: #{tidySubject(@issue.subject)}\n")
      @states.each do |s|
        dumpState(s,dest,"  ")
      end
    end

    def dump(dest: STDOUT,wantHeader: true,indent: "  ")
      dest.printf("%s\n" % header()) if wantHeader
      index = 0
      @states.each do |s|
        dumpState(s,dest,indent)
        if index < @trail.length
          dumpJEntry(@trail[index],dest,indent)
        end
        index = index + 1
      end
    end

    def last_status()
      st = nil
      if @states.length > 0
        st = @states[-1].status
      else
        STDERR.write("Issue #{@issue.id}: no states found (status)\n")
      end
      return st
    end

    def last_state()
      st = nil
      if @states.length > 0
        st = @states[-1].state
      else
        STDERR.write("Issue #{@issue.id}: no states found (state)\n")
      end
      return st
    end

    def last_hourLimit()
      hl = nil
      if @states.length > 0
        hl = @states[-1].hours
      else
        STDERR.write("Issue #{@issue.id}: no states found (hour limit)\n")
      end
      return hl
    end

    def last_stateTimeout()
      st = nil
      if @states.length > 0
        st = @states[-1].timeout
      else
        STDERR.write("Issue #{@issue.id}: no states found (state timeout)\n")
      end
      return st
    end

    def consistent?(messages)
      # for each journal state, check that
      #   - state is nil or not nil correctly, depending on project and tracker
      #   - status and state match, or state is nil
      #   - transitions leading to this state correctly match previous and
      #     current states / statuses (i.e. if transition from X to Y, make
      #     sure previous was X, and current is Y)
      @trail.each_index do |idx|
        entry = @trail[idx]
        state = @states[idx+1]
        prev = @states[idx]
        pfx = "Journal #{state.journal}: "
        
        # check state is nil or not nil, depending on project and tracker
        # and status
        needsPS = projectNeedsPS?(state.project) && trackerNeedsPS?(state.tracker) && !status(state.status).nil?
        if needsPS && state.state.nil?
          messages << "#{pfx}state=nil but tracker=#{trackerName(state.tracker)} && project=#{projectName(state.project)}"
        elsif !needsPS && !state.state.nil?
          messages << "#{pfx}state=#{state.state} but should be nil: tracker=#{trackerName(state.tracker)} && project=#{projectName(state.project)}"
        end

        # check status, state match (status may no longer exist)
        ssm = StatusStateMapping.find_by(status: state.status)
        if ssm.nil? # status is unknown, state should be nil
          if !state.state.nil?
            messages << "#{pfx}status=#{state.status} (unknown) but state=#{state.state}"
          end
        elsif needsPS
          if !(state.state == ssm.state)
            messages << "#{pfx}status=#{status(state.status)} but state=#{state.state} (should be #{ssm.state})"
          end
        end

        # check that HL, ST are consistent with PS
        if needsPS
          if state.timeout.nil? || state.hours.nil?
            messages << "#{pfx}need project state but timeout=#{state.timeout.nil? ? "nil" : state.timeout}, hour limit=#{state.hours.nil? ? "nil" : state.hours}"
          end
        else # don't want PS
          if !state.timeout.nil? || !state.hours.nil?
            messages << "#{pfx}no project state but timeout=#{state.timeout.nil? ? "nil" : state.timeout}, hour limit=#{state.hours.nil? ? "nil" : state.hours}"
          end
        end

        # check transtion(s) match before and after states
        entry.details.each_pair do |tag,transition|
          if prev[tag] != transition.from
            messages << "#{pfx}#{tag}: prev=#{prev[tag]} but from=#{transition.from}"
          end
          if state[tag] != transition.to
            messages << "#{pfx}#{tag}: current=#{state[tag]} but to=#{transition.to}"
          end
        end
      end
      return messages.length == 0
    end

    # remove "new -> state" transition if present
    def removeNewTransition(testing,debug)
      changed = false
      if @trail.length == 0
        return changed
      end
      first = @trail[0]
      detailCount = first.details.length
      first.details.each_pair do |k,v|
        if k == "state" && v.from == "new"
          jd = JournalDetail.find(v.id)
          $log.info "Deleting JD #{jd.id}: '#{v.from}' => #{v.to}"
          changed = true
          jd.delete if !testing
          first.details.delete(k) if !testing
          detailCount = detailCount - 1
        end
      end
      if detailCount == 0
        $log.info "Deleting J #{first.journal}"
        changed = true
        j = Journal.find(first.journal)
        j.delete if !testing
        @trail.delete_at(0) if !testing
      end
      if changed
        calculateInitialState
        calculateStates
        if debug
          $log.debug {"#{@issue.id}: after correctNew"}
          dump
        end
      end
      return changed
    end

    # calculate correct state, update if necessary
    def correctStates(testing,debug)
      changed = false
      @states.each_index do |ind|
        st = @states[ind]
        details = ind == 0 ? nil : @trail[ind-1].details
        needsPS = projectNeedsPS?(st.project) && trackerNeedsPS?(st.tracker)
        if needsPS
          statusName = status(st.status)
          if statusName.nil?
            needsPS = false
            nstate = nil
          else
            nstate = status2state(st.status)
          end
        else
          nstate = nil
        end
        if st.state != nstate
          $log.debug {"#{@issue.id}: journal #{st.journal}: state #{st.state.nil? ? "nil" : st.state} ==> #{nstate.nil? ? "nil" : nstate}"}
          changed = true
          st.state = nstate if !testing
        end

        if st.state.nil?
          # set st, hl to nil as well (shouldn't be necessary to remove
          # objects themselves... but check.)
          if st.hours != nil
            st.hours = nil
            changed = true
          end
          if st.timeout != nil
            st.timeout = nil
            changed = true
          end
        else
          # if st, hl are set (in details) then use those values
          # otherwise use defaults based on current status
          if !details.nil? && details.has_key?("hours")
            htemp = details["hours"].to
          else
            tlDefault = TimeLimitDefault.find_by(tracker_id: st.tracker)
            if !tlDefault.nil?
              htemp = tlDefault.hours
            else
              htemp = nil
            end
          end
          if htemp != st.hours
            st.hours = htemp
            changed = true
          end
          if !details.nil? && details.has_key?("timeout")
            stemp = details["timeout"].to
          else
            stDefault = StatusTimeoutDefault.find_by(status: st.status)
            if !stDefault.nil?
              stemp = stDefault.timeout
            else
              stemp = nil
            end
          end
          if stemp != st.timeout
            st.timeout = stemp
            changed = true
          end
        end
      end

      if changed && debug
        $log.debug {"#{@issue.id}: after correctStates"}
        dump
      end
    end

    # check whether transitions reflect actual change from previous state
    # to current state:
    #  - <state1> to <state2>: ensure state transition is present
    #    (either state1 or state2 may be nil)
    #  - <state1> to <state1>: ensure no state transition is present
    def correctLogs(testing,debug)
      changed = false
      @trail.each_index do |ind|
        prevState = @states[ind].state
        currState = @states[ind+1].state
        transition = @trail[ind]
        # get state transition, if any
        stateChange = transition.details.fetch("state",nil)

        if prevState == currState && !stateChange.nil?
          # we shouldn't see a state transition
          $log.debug {"#{@issue.id}: journal #{transition.journal}: removing #{stateChange.id} [#{prevState} => #{currState}] because no state change occurs"}
          jd = JournalDetail.find(stateChange.id)
          transition.details.delete("state") if !testing
          jd.delete if !testing
          changed = true

        elsif prevState != currState && stateChange.nil?
          # need to add a state transition
          $log.debug {"#{@issue.id}: journal #{transition.journal}: adding #{prevState} => #{currState}"}
          j = Journal.find(transition.journal)
          j.details << JournalDetail.new(property: 'cf',
                                         prop_key: projectStateId,
                                         old_value: prevState,
                                         value: currState)
          j.save if !testing
          transition.details["state"] = JournalDetailFT.new(0,prevState,currState)
          changed = true

        elsif prevState != currState && !stateChange.nil?
          # check that the state change is correct, update if not
          $log.debug {"#{@issue.id}: journal #{transition.journal}: checking #{prevState.nil? ? "nil" : prevState} => #{currState.nil? ? "nil" : currState}"}
          if prevState != stateChange.from
            $log.debug {"#{@issue.id}: journal #{transition.journal}: updating 'from': #{stateChange.from} => #{prevState}"}
            jd = JournalDetail.find(stateChange.id)
            jd.old_value = prevState
            jd.save if !testing
            stateChange.from = prevState if !testing
            changed = true
          end
          if currState != stateChange.to
            $log.debug {"#{@issue.id}: journal #{transition.journal}: updating 'to': #{stateChange.to} => #{currState}"}
            jd = JournalDetail.find(stateChange.id)
            jd.value = currState
            jd.save if !testing
            stateChange.to = currState if !testing
            changed = true
          end
        end
      end
      if changed
        calculateInitialState
        calculateStates
        if debug
          $log.debug {"#{@issue.id}: after correctLogs"}
          dump
        end
      end
    end

    def correctJournal(testing,debug)
      $log.debug("#{@issue.id}: correcting journal...")

      changedNew = removeNewTransition(testing,debug)
      changedState = correctStates(testing,debug)
      changedLog = correctLogs(testing,debug)

      return (changedNew || changedState || changedLog)
    end
  end
end
