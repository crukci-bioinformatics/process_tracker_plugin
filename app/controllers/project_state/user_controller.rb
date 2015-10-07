require 'date'
require 'project_state/utils'
require 'project_state/issue_filter'

class ProjectState::UserController < ApplicationController
  include ProjectStatePlugin::Utilities
  include ProjectStatePlugin::IssueFilter


  unloadable

  def show
    user = params[:id].to_i

    projects = collectProjects(Setting.plugin_project_state['root_projects'])
    issues = collectIssues(projects)
    if user == -1 # unassigned
      issues = issues.select{|i| i if i.assigned_to.nil?}
    else
      issues = issues.select{|i| i if i.assigned_to_id == user}
    end
    if params[:report] == 'stark'
      issues = filter_issues(issues)
    end

    @issue_hash = Hash.new
    @flags = Hash.new
    issues.each do |iss|
      @issue_hash[iss.state] = [] unless @issue_hash.has_key? iss.state
      @issue_hash[iss.state] << iss
      @flags[iss.id] = get_flags(iss)
    end
  end
end
