require_dependency File.expand_path(File.dirname(__FILE__)+'/../lib/project_state/utils')

class ProjectStatePopulateDb
  include ProjectStatePlugin::Utilities

  def add_to_trackers(cf)
    Tracker.all.each do |t|
      begin
        cf.trackers<<(t)
      rescue ActiveRecord::RecordNotUnique
      end
    end
  end

  def create_custom_fields
    nm = 'Project State'
    ps = IssueCustomField.find_or_create_by(name: nm) do |icf|
      STDOUT.printf("Creating custom field '%s'\n",nm)
      icf.field_format = 'list'
      icf.possible_values = ["Prepare", "Submit", "Ready", "Active", "Hold", "Post", "Ongoing"]
      icf.is_required = false
      icf.is_filter = true
      icf.searchable = true
      icf.default_value = 'Prepare'
      icf.format_store = {"url_pattern"=>"", "edit_tag_style"=>""}
      icf.description = l(:custom_var_project_state)
    end

    nm = 'State Timeout'
    st = IssueCustomField.find_or_create_by(name: nm) do |icf|
      STDOUT.printf("Creating custom field '%s'\n",nm)
      icf.field_format = 'int'
      icf.min_length = 0
      icf.is_required = false
      icf.is_filter = true
      icf.default_value = "0"
      icf.format_store = {"url_pattern"=>""}
      icf.description = l(:custom_var_state_timeout)
    end

    nm = 'Hour Limit'
    hl = IssueCustomField.find_or_create_by(name: nm) do |icf|
      STDOUT.printf("Creating custom field '%s'\n",nm)
      icf.field_format = 'int'
      icf.min_length = 0
      icf.is_required = false
      icf.is_filter = true
      icf.default_value = "0"
      icf.format_store = {"url_pattern"=>""}
      icf.description = l(:custom_var_hour_limit)
    end

    nm = 'Researcher Email'
    rm = IssueCustomField.find_or_create_by(name: nm) do |icf|
      STDOUT.printf("Creating custom field '%s'\n",nm)
      icf.field_format = 'string'
      icf.regexp = "^\\s*[\\w.%+-]+@[\\w.-]+\\.[A-Za-z]{2,4}(\\s*;\\s*[\\w.%+-]+@[\\w.-]+\\.[A-Za-z]{2,4})*\s*$"
      icf.is_filter = true
      icf.is_for_all = true
      icf.default_value = ""
      icf.format_store = {"text_formatting"=>"", "url_pattern"=>""}
      icf.description = l(:custom_var_researcher)
    end

    add_to_trackers(ps)
    add_to_trackers(st)
    add_to_trackers(hl)
    add_to_trackers(rm)

  end

  def populate_default_state_timeouts
    ProjectStatePlugin::Defaults::STATE_TIMEOUT_DEFAULTS.keys.each do |s|
      StateTimeoutDefault.find_or_create_by(state: s) do |std|
        STDOUT.printf("State Timeout: %s --> %d\n",s,@@state_timeout_defaults[s])
        std.timeout = @@state_timeout_defaults[s]
      end
    end
  end

  def populate_default_hour_limits
    ProjectStatePlugin::Defaults::HOUR_LIMIT_DEFAULTS.keys.each do |k|
      tkset = Tracker.where(name: k)
      if tkset.length != 0
        TimeLimitDefault.find_or_create_by(tracker: tkset[0]) do |tld|
          STDOUT.printf("Tracker '%s': --> %d\n",k,@@hour_limit_defaults[k])
          tld.hours = @@hour_limit_defaults[k]
        end
      else
        STDERR.printf("ERROR: no tracker found with name '%s'\n",k)
      end
    end
  end

  def populate_state_journal_entries
    psid = IssueCustomField.find_by(name: 'Project State').id.to_i
    admin = User.find_by(login: 'admin')
    Journal.find_each do |j|
      next if j.journalized_type != 'Issue'
      j.details.each do |jd|
        next if jd.prop_key != 'status_id'
        old_val = @@project_state_defaults[jd.old_value.to_i]
        new_val = @@project_state_defaults[jd.value.to_i]
        if old_val.nil? or new_val.nil?
          next
        end
        if old_val != new_val
          JournalDetail.find_or_create_by(journal_id: jd.journal_id,
                                          property: 'cf',
                                          prop_key: psid) do |njd|
            printf("issue %d: %s -> %s at %s\n",j.journalized_id,old_val,new_val,j.created_on)
            njd.old_value = old_val
            njd.value = new_val
          end
        end
      end
    end
    includedProjects.each do |proj|
      proj.issues.find_each do |i|
        changes = i.journals.joins(:details).where(journal_details: { prop_key: psid}).order(:created_on)
        if changes.length > 0
          initial = changes[0].details.find_by(prop_key: psid).old_value
        else
          initial = @@project_state_defaults[i.status_id]
        end
      
        STDERR.printf("i.id: %d\n",i.id)
        STDERR.printf("user: %s\n",admin)
        STDERR.printf("crea: %s\n",i.created_on)
        je = Journal.find_or_create_by(journalized_id: i.id,
                                       journalized_type: 'Issue',
                                       user: admin,
                                       created_on: i.created_on) do |je|
          je.private_notes = 0
          je.details << JournalDetail.new(property: 'cf',
                                          prop_key: psid.to_s,
                                          old_value: 'new',
                                          value: initial)
        end
      end
    end
  end

end

pspd = ProjectStatePopulateDb.new
pspd.create_custom_fields
pspd.populate_default_state_timeouts
pspd.populate_default_hour_limits
pspd.populate_state_journal_entries
