require 'date'
require 'project_state/utils'
require 'project_state/issue_filter'

class ProjectState::StateController < ApplicationController
  include ProjectStatePlugin::Utilities
  include ProjectStatePlugin::IssueFilter

  unloadable

  def show
    state = params[:id]

    projects = collectProjects(Setting.plugin_project_state['root_projects'])
    issues = collectIssues(projects).select{|i| i if i.state == state}
    if params[:report] == 'stark'
      issues = filter_issues(issues)
    else
      issues = filter_on_tracker(issues)
    end

    @issues = Hash.new
    @flags = Hash.new
    @users = Hash.new
    issues.each do |iss|
      u = iss.assigned_to_id
      @issues[u] = [] unless @issues.has_key? u
      @issues[u] << iss
      @flags[iss.id] = get_flags(iss)
      @users[u] = User.find(u) unless u.nil?
    end
    @usort = @issues.keys.sort{|a,b| a.nil? ? 1 : (b.nil? ? -1 : @users[a].firstname <=> @users[b].firstname)}
  end
end
