namespace :redmine do
  namespace :project_state do
    
    desc "Populate status timeout defaults table from known statuses"
    task :populate_timeouts => [:environment] do
      StatusTimeoutDefault.populate_from_statuses()
    end
  end
end
