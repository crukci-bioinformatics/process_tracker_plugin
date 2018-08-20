require 'logger'

module ProjectStatePlugin
  module AuditUtils

    @@statusMap = {}
    @@trackerSet = {}
    @@trackerNames = {}
    @@projectSet = {}
    @@projectNames = {}
    @@projectStateId = nil
    @@hourLimitId = nil
    @@stateTimeoutId = nil

    @@logWords = { ::Logger::DEBUG => "debug",
                   ::Logger::INFO => "info",
                   ::Logger::WARN => "warn",
                   ::Logger::ERROR => "error",
                   ::Logger::FATAL => "fatal",
                   ::Logger::UNKNOWN => "unknown"
                 }

    def tidySubject(subject)
      subj = subject.gsub('%','%%')
      subj = subj.length <= 50 ? subj : subj.truncate(50)+"..."
      return subj
    end

    def header()
      return "Issue #{@issue.id}: #{tidySubject(@issue.subject)}"
    end

    def projectStateId()
      if @@projectStateId.nil?
        @@projectStateId = CustomField.find_by(name: "Project State").id
      end
      return @@projectStateId
    end

    def stateTimeoutId()
      if @@stateTimeoutId.nil?
        @@stateTimeoutId = CustomField.find_by(name: "State Timeout").id
      end
      return @@stateTimeoutId
    end

    def hourLimitId()
      if @@hourLimitId.nil?
        @@hourLimitId = CustomField.find_by(name: "Hour Limit").id
      end
      return @@hourLimitId
    end

    def status(stat)
      tag = @@statusMap.fetch(stat,nil)
      if tag.nil?
        begin
          tag = IssueStatus.find(stat).name
          @@statusMap[stat] = tag
        rescue ActiveRecord::RecordNotFound
          tag = "unknown(#{stat})"
          @@statusMap[stat] = tag
        end
      end
      return tag
    end

    def status2state(stat)
      ssm = StatusStateMapping.find_by(status: stat)
      return ssm.nil? ? nil : ssm.state
    end
      
    def trackerNeedsPS?(trackerId)
      tag = @@trackerSet.fetch(trackerId,nil)
      if tag.nil?
        begin
          trak = Tracker.find(trackerId)
          cf = trak.custom_fields.where(id: projectStateId)
          tag = ((!cf.nil?) && (cf.length > 0))
          @@trackerSet[trak.id] = tag
        rescue ActiveRecord::RecordNotFound
          STDERR.printf("Error looking up tracker #{trackerId}\n")
        end
      end
      return tag
    end

    def trackerName(trackerId)
      tag = @@trackerNames.fetch(trackerId,nil)
      if tag.nil?
        begin
          tag = Tracker.find(trackerId).name
          @@trackerNames[trackerId] = tag
        rescue ActiveRecord::RecordNotFound
          # nothing to do
        end
      end
      return tag
    end

    def projectNeedsPS?(projectId)
      tag = @@projectSet.fetch(projectId,nil)
      if tag.nil?
        begin
          proj = Project.find(projectId)
          cf = proj.issue_custom_fields.where(id: projectStateId)
          tag = !cf.nil? && cf.length > 0
          @@projectSet[proj.id] = tag
        rescue ActiveRecord::RecordNotFound
          # nothing to do
        end
      end
      return tag
    end

    def projectName(projectId)
      tag = @@projectNames.fetch(projectId,nil)
      if tag.nil?
        begin
          tag = Project.find(projectId).name
          @@projectNames[projectId] = tag
        rescue ActiveRecord::RecordNotFound
          # nothing to do
        end
      end
      return tag
    end

    def self.convertLogLev(logTxt,testing)
      loglev = nil
      if testing
        loglev = ::Logger::DEBUG
      else
        loglev = ::Logger::DEBUG if logTxt == "debug"
        loglev = ::Logger::INFO if logTxt == "info"
        loglev = ::Logger::WARN if logTxt == "warn"
        loglev = ::Logger::ERROR if logTxt == "error"
        loglev = ::Logger::FATAL if logTxt == "fatal"
        loglev = ::Logger::UNKNOWN if logTxt == "unknown"
      end
      if loglev.nil?
        loglev = ::Logger::INFO
        if !logTxt.nil?
          puts "Illegal log level '#{logTxt}'; setting to INFO"
        end
      end
      return loglev
    end
  end
end
