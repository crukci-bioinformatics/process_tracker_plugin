require 'date'
require 'project_state/defaults'
require 'project_state/utils'
require 'project_state/issue_filter'

class ProjectState::SummaryController < ApplicationController
  include ProjectStatePlugin::Utilities
  include ProjectStatePlugin::IssueFilter

  unloadable

  def index
    @stark = params[:report] == 'stark'
    @states = ProjectStatePlugin::Defaults::INTERESTING

    projects = collectProjects(Setting.plugin_project_state['root_projects'])
    issues = collectIssues(projects)
    if @stark
      issues = filter_issues(issues)
    end

    @users = {}
    issues.each do |iss|
      @users[iss.assigned_to_id] = iss.assigned_to unless iss.assigned_to.nil?
    end
    @usort = @users.keys.sort{|a,b| a.nil? ? 1 : (b.nil? ? -1 : @users[a].firstname <=> @users[b].firstname)}
      
    @count = {}
    @flags = {}
    @users.keys.each do |u|
      @count[u] = Hash.new(0)
      @flags[u] = Hash.new(0)
    end
    @count[nil] = Hash.new(0) # for "unassigned" projects
    @flags[nil] = Hash.new(0)

    @rowcountsum = Hash.new(0)
    @rowflagsum = Hash.new(0)
    @colcountsum = Hash.new(0)
    @colflagsum = Hash.new(0)

    issues.each do |iss|
      @count[iss.assigned_to_id][iss.state] += 1
      @rowcountsum[iss.assigned_to_id] += 1
      @colcountsum[iss.state] += 1
      if is_flagged(iss)
        @flags[iss.assigned_to_id][iss.state] += 1
        @rowflagsum[iss.assigned_to_id] += 1
        @colflagsum[iss.state] += 1
      end
    end

    @totalsum = @rowcountsum.values.sum
    @totalflagsum = @rowflagsum.values.sum
  end

end
