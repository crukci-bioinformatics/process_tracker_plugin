require_dependency File.expand_path(File.dirname(__FILE__)+'/../project_state/snapshot')


namespace :redmine do
  namespace :project_state do
    
    desc "Audit an issue's history of state and status changes"
    task :audit_issue, [:iss_id] => [:environment] do |t,args|
      include ProjectStatePlugin::Utilities
      id = args[:iss_id].to_i
      $pslog.debug("ID: '#{args[:iss_id]}'")
      auditor = ProjectStatePlugin::JournalAuditor.new
      auditor.audit(id)
    end

  end
end
