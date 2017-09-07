require File.expand_path(File.dirname(__FILE__)+'/../lib/project_state/utils')

class ProjectStatePopulateDb
  include ProjectStatePlugin::Defaults
  include ProjectStatePlugin::Utilities
  include ProjectStatePlugin::Logger

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

  def ensure_state_journal_entries(args)
    psid = IssueCustomField.find_by(name: CUSTOM_PROJECT_STATE).id.to_i
    admin = User.find_by(login: 'admin')
    Journal.find_each do |j|
      next if j.journalized_type != 'Issue'
      j.details.each do |jd|
        next if jd.prop_key != 'status_id'
        old_status = jd.old_value.to_i
        new_status = jd.value.to_i
        old_val = StatusStateMapping.find_by(status: old_status)
        new_val = StatusStateMapping.find_by(status: new_status)
        if old_val.nil? || new_val.nil?
          warn("Need status=>state mapping: #{old_status} -> ?") if old_val.nil?
          warn("Need status=>state mapping: #{new_status} -> ?") if new_val.nil?
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
  def ensure_initial_journal_entries(args)
    includedProjects.each do |proj|
      proj.issues.find_each do |i|
        changes = i.journals.joins(:details).where(journal_details: { prop_key: psid}).order(:created_on)
        if changes.length > 0
          initial = changes[0].details.find_by(prop_key: psid).old_value
        else
          initial = @@project_state_defaults[i.status_id]
        end
      
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
pspd.ensure_state_journal_entries(test: true)
pspd.ensure_initial_journal_entries(test: true)
