require 'date'
require 'project_state/utils'
require 'project_state/issue_filter'

class ProjectState::UsersController < ApplicationController
  include ProjectStatePlugin::Utilities
  include ProjectStatePlugin::IssueFilter


  unloadable

  def show
    has_id = params.has_key? :id
    if has_id
      @user = params[:id] == '-1' ? nil : params[:id].to_i
    else
      @user = User.current.id
    end
    
    if params[:all] == 'true'
      issues = collectAllOpenIssues()
      issues = issues.select{|i| i if i.assigned_to_id == @user}
      show_all = true 
    else
      projects = collectProjects(Setting.plugin_project_state['root_projects'])
      issues = collectIssues(projects)
      issues = issues.select{|i| i if i.assigned_to_id == @user}
      if params[:report] == 'stark'
        issues = filter_issues(issues)
      else
        issues = filter_on_tracker(issues)
      end
      show_all = false 
    end

    @issue_hash = Hash.new
    @flags = Hash.new
    issues.each do |iss|
      @issue_hash[iss.state] = [] unless @issue_hash.has_key? iss.state
      @issue_hash[iss.state] << iss
      @flags[iss.id] = get_flags(iss)
    end

    @toggle_text = l(:my_state_filtered_link)
    @toggle_link = "/project_state/user"
    if has_id
      @toggle_link += "?id=#{params[:id]}"
    end
    if not show_all
      @toggle_text = l(:my_state_all_link)
      @toggle_link += (has_id ? "&" : "?") + "all=true"
    end
  end
end
