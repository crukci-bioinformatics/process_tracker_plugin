require 'date'
require 'project_state/utils'

class StatesController < ApplicationController
  include ProjectStatePlugin::Utilities
  include ActionView::Helpers::NumberHelper

  unloadable

  INTERESTING = ['Prepare','Submit','Ready','Active','Hold','Post']
  ORDERING = {'Ongoing' => 0,
              'Prepare' => 1,
              'Submit' => 2,
              'Ready' => 3,
              'Active' => 4,
              'Hold' => 5,
              'Post' => 6}

  def get_flags(issue)

    flags = []
    if issue.status_id == IssueStatus.find_by(name: 'Closed').id
      return flags
    end

    # check time in state (or since last logged time, if 'Active')
    seconds = 60 * 60 * 24
    j = issue.state_last_changed
    if j.nil?
     return flags
    end
    ch = j.to_i / seconds
    now = DateTime.now.to_i / seconds
    interval = now - ch
    if issue.state == 'Active'
      begin
        last_logged = issue.time_entries.order(:spent_on).last.spent_on.to_time.to_i / seconds
      rescue NoMethodError => e
        last_logged = 0
      end
      log_i = now - last_logged
      interval = [interval,log_i].min
    end
    if interval > issue.state_timeout
      if issue.state == 'Active'
        flags << l(:flag_days_since_logged_time,
                   :state => issue.state,
                   :actual => interval,
                   :threshold => issue.state_timeout)
      else
        flags << l(:flag_days_in_state,
                   :state => issue.state,
                   :actual => interval,
                   :threshold => issue.state_timeout)
      end
    end

    # logged time exceeds limits
    if issue.spent_hours > issue.hours_limit
      flags << l(:flag_hours_logged,
                 :logged => number_with_precision(issue.spent_hours,precision: 2),
                 :threshold => number_with_precision(issue.hours_limit,precision: 2))
    end

    # unassigned but past Prepare
    if issue.assigned_to.nil? && issue.state != 'Prepare'
      flags << l(:flag_analyst_unassigned,
                 :state => issue.state)
    end

    return flags
  end

  def is_flagged(issue)
    return (get_flags(issue).length > 0)
  end

  def process_project(project,issues,flags)
    closed = IssueStatus.find_by(name: 'Closed').id
    Issue.where(project_id: project.id).find_each do |iss|
      next unless iss.status_id != closed
      if iss.assigned_to_id.nil?
        issues[-1][iss.state] += 1
      else
        begin
          issues[iss.assigned_to_id][iss.state] += 1
        rescue
#          STDERR.printf("iss: %d  assigned_to %d  state: %s  status: %d\n",iss.id,iss.assigned_to_id,iss.state,iss.status_id)
        end
      end
      if is_flagged(iss)
        if iss.assigned_to_id.nil?
          flags[-1][iss.state] += 1
        else
          if flags.has_key? iss.assigned_to_id
            flags[iss.assigned_to_id][iss.state] += 1
          end
        end
      end
    end

  end

  def index
    groups = semiString2List(Setting.plugin_project_state['user_groups'])
    uset = {}
    iset = {}
    fset = {}
    groups.each do |gr|
      Group.find_by(lastname: gr).users.find_each do |u|
        if not uset.has_key?(u.id)
          uset[u.id] = u
          iset[u.id] = Hash.new(0)
          fset[u.id] = Hash.new(0)
        end
      end
    end
    iset[-1] = Hash.new(0) # for "unassigned" projects
    fset[-1] = Hash.new(0)
    includedProjects.each do |p|
      process_project(p,iset,fset)
    end
    iset.keys.each do |k|
      uset.delete(k) if iset[k].values.sum == 0
    end
    @issues = iset
    @users = uset
    @states = IssueCustomField.find_by(name: 'Project State').possible_values[0..-3]
    @flags = fset
  end

  def show
    user = params[:id].to_i
    closed = IssueStatus.find_by(name: 'Closed').id
    projIds = includedProjects.map{|p| p.id}
    
    if user == -1 # unassigned
      issue_set = Issue.where(assigned_to: nil)
    else
      issue_set = Issue.where(assigned_to_id: user)
    end
    issue_set = issue_set.select{|i| i if (i.status_id != closed) && projIds.include?(i.project_id) }
    @issue_hash = Hash.new
    @flags = Hash.new
    issue_set.each do |iss|
      @issue_hash[iss.state] = [] unless @issue_hash.has_key? iss.state
      @issue_hash[iss.state] << iss
      @flags[iss.id] = get_flags(iss)
    end
  end
end
