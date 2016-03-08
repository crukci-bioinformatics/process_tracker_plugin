require_dependency File.expand_path(File.dirname(__FILE__)+'/../project_state/snapshot')

namespace :redmine do
  namespace :project_state do
    
    desc "Audit an issue's history of state and status changes"
    task :audit_issue, [:iss_id] => [:environment] do |t,args|
      include ProjectStatePlugin::Utilities
      id = args[:iss_id].to_i
      auditor = ProjectStatePlugin::JournalAuditor.new
      auditor.issue_consistent?(iss_id: id)
    end

    task :audit_issues => :environment do 
      auditor = ProjectStatePlugin::JournalAuditor.new
      auditor.audit_issues(dest: STDOUT)
    end

    task :add_new, [:iss_id] => [:environment] do |t,args|
      auditor = ProjectStatePlugin::JournalAuditor.new
      id = args[:iss_id].to_i
      auditor.add_new(iss_id: id, dest: STDOUT)
    end
  end
end
