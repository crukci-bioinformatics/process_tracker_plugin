require File.expand_path(File.dirname(__FILE__)+'/../project_state/psjournal')
require File.expand_path(File.dirname(__FILE__)+'/../project_state/audit')
require File.expand_path(File.dirname(__FILE__)+'/../project_state/audit_utils')

namespace :redmine do
  namespace :project_state do
    
    desc "Audit an issue's history of state and status changes"
    task :audit_issue, [:iss_id,:loglev] => [:environment] do |t,args|
      loglev = ProjectStatePlugin::AuditUtils::convertLogLev(args[:loglev],false)
      id = args[:iss_id].to_i
      iss = Issue.find(id)
      auditor = ProjectStatePlugin::JournalAuditor.new(loglev: loglev)
      auditor.issue_consistent?(iss)
    end

    task :audit_issues, [:loglev] => :environment do |t,args|
      loglev = ProjectStatePlugin::AuditUtils::convertLogLev(args[:loglev],false)
      auditor = ProjectStatePlugin::JournalAuditor.new(loglev: loglev)
      auditor.audit_issues(dest: STDOUT)
    end

    task :audit_current_state => :environment do
      auditor = ProjectStatePlugin::JournalAuditor.new
      auditor.audit_current_state(dest: STDOUT)
    end

    task :dump, [:iss_id] => [:environment] do |t,args|
      id = args[:iss_id].to_i
      iss = Issue.find(id)
      hist = ProjectStatePlugin::PSJournal.new(iss)
      hist.dump(dest: STDOUT,indent: "")
    end

    task :auditJournal, [:iss_id] => [:environment] do |t,args|
      id = args[:iss_id].to_i
      iss = Issue.find(id)
      hist = ProjectStatePlugin::PSJournal.new(iss)
      messages = []
      okay = hist.consistent?(messages)
      STDOUT.print("Issue #{id} #{okay ? "okay" : "bad"}\n")
      messages.each {|x| STDOUT.printf("    %s\n",x)}
    end

    task :bad_project_state => :environment do
      auditor = ProjectStatePlugin::JournalAuditor.new
      auditor.extra_project_states(dest: STDOUT)
    end

    task :correct_issue, [:iss_id,:testing,:loglev] => :environment do |t,args|
      testing = args[:testing] == "test"
      loglev = ProjectStatePlugin::AuditUtils::convertLogLev(args[:loglev],testing)
      id = args[:iss_id].to_i
      iss = Issue.find_by(id: id)
      if iss.nil?
        puts "Issue #{id} not found"
      else
        auditor = ProjectStatePlugin::JournalAuditor.new(testing: testing,loglev: loglev)
        auditor.correctIssue(iss,STDOUT)
      end
    end

    task :correct_issues, [:testing,:loglev] => :environment do |t,args|
      testing = args[:testing] == "test"
      loglev = ProjectStatePlugin::AuditUtils::convertLogLev(args[:loglev],testing)
      auditor = ProjectStatePlugin::JournalAuditor.new(testing: testing,loglev: loglev)
      Issue.all.each do |iss|
        auditor.correctIssue(iss,STDOUT)
      end
    end
  end
end
