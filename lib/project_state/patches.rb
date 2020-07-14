
module ProjectStatePlugin

  module IssuePatch
    include ProjectStatePlugin::Defaults

    def self.included(base)
      base.class_eval do
        has_many :state_journals

        before_validation :ensure_valid_project_state
        def ensure_valid_project_state
          psid = CustomField.find_by(name: CUSTOM_PROJECT_STATE).id
          cf = custom_field_values.select{|x| x.custom_field_id == psid}
          return if cf.nil?
          return if cf.is_a?(Array) && cf.length == 0
          cf = cf[0] if cf.is_a?(Array)
          cf_changed = cf.value_was != cf.value
          if cf_changed && !status_id_changed? && !cf.value_was.nil?
            errors.add("Project State"," must not be changed directly.")
          end
        end

        def state
          cfid = IssueCustomField.find_by(name: CUSTOM_PROJECT_STATE).id
          s = CustomValue.find_by(customized: self, custom_field_id: cfid)
          return s.nil? ? nil : s.value
        end

        def state_timeout
          cfid = IssueCustomField.find_by(name: CUSTOM_STATE_TIMEOUT).id
          s = CustomValue.find_by(customized: self, custom_field_id: cfid)
          return s.nil? ? nil : s.value.to_i
        end

        def hours_limit
          cfid = IssueCustomField.find_by(name: CUSTOM_HOUR_LIMIT).id
          s = CustomValue.find_by(customized: self, custom_field_id: cfid)
          return s.nil? ? nil : s.value.to_f
          return s.value
        end

        def state_last_changed
          cfid = IssueCustomField.find_by(name: CUSTOM_PROJECT_STATE).id
          return self.journals.joins(:details).where(journal_details: { prop_key: cfid}).maximum(:created_on)
        end

        def cost_centre
          cf = IssueCustomField.find_by(name: CUSTOM_ISS_COSTCODE)
          cv_code = self.custom_values.find_by(custom_field: cf)
          if cv_code.nil? || cv_code.value == ""
            proj = self.project
            code = proj.ppms_cost_centre
            if code.nil? || code == ""
              while (! proj.parent_id.nil?) && (code.nil? || code == "")
                proj = proj.parent
                code = proj.ppms_cost_centre
              end
            end
          else
            code = cv_code.value
          end
          return nil if code.nil?
          return code == "" ? nil : code
        end

        def researcher
          cf = IssueCustomField.find_by(name: CUSTOM_RESEARCHER_EMAIL)
          email = self.custom_values.find_by(custom_field: cf)
          return nil if email.nil?
          elist = email.value.split(';').map{ |t| t.strip }.select{|t| t.length > 0}
          email = elist.length == 0 ? nil : elist[0]
          return email == "" ? nil : email
        end
      end
    end
  end

  module ProjectPatch
    include ProjectStatePlugin::Defaults

    def self.included(base)
      base.class_eval do
        def proj_ids
          ids = [self.id]
          ids = ids.concat(Project.where(parent: self).map{|p| p.proj_ids})
          return ids.flatten
        end
        def cost_centre
          cf = ProjectCustomField.find_by(name: CUSTOM_PROJ_COSTCODE)
          code = self.custom_values.find_by(custom_field: cf)
          if code.nil? || code.value == ""
            proj = self
            while (! proj.parent_id.nil?) && (code.nil? || code.value == "")
              proj = proj.parent
              code = proj.custom_values.find_by(custom_field: cf)
            end
          end
          return code
        end
      end
    end
  end

#########
# No longer used, but we might want it back someday.
#
#  module CustomValuePatch
#    include ProjectStatePlugin::Defaults
#
#    def self.included(base)
#      base.class_eval do
#        before_validation :ensure_state_change_permitted
#        def ensure_state_change_permitted
#          u = User.current
#          sol = User.find_by(login: 'solexa')
#          cfid = CustomField.find_by(name: CUSTOM_PROJECT_STATE).id
#          returnval = true
#          if u == sol && self.custom_field_id == cfid
#            o = CustomValue.find(self.id)
#            returnval = ORDERING[o.value] < ORDERING[self.value]
#          end
#          return returnval
#        end
#      end
#    end
#  end

#########
# No longer used, but we might want it back someday.
#
#  module JournalPatch
#    include ProjectStatePlugin::Defaults
#    def self.included(base)
#      base.class_eval do
#        before_validation :ensure_state_change_permitted
#        def ensure_state_change_permitted
#          u = User.current
#          sol = User.find_by(login: 'solexa')
#          cfid = CustomField.find_by(name: CUSTOM_PROJECT_STATE).id
#          returnval = true
#          if u == sol
#            self.details.each do |d|
#              if d.prop_key.to_i == cfid
#                returnval = ORDERING[d.old_value] < ORDERING[d.value]
#              end
#            end
#          end
#          return returnval
#        end
#      end
#    end
#  end

end
