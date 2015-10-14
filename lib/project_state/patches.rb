
module ProjectStatePlugin

  module IssuePatch
    include ProjectStatePlugin::Defaults

    def self.included(base)
      base.class_eval do
        has_many :state_journals

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

      end
    end
  end

  module ProjectPatch
    def self.included(base)
      base.class_eval do
        def proj_ids
          ids = [self.id]
          ids = ids.concat(Project.where(parent: self).map{|p| p.proj_ids})
          return ids.flatten
        end
      end
    end
  end

  module CustomValuePatch
    include ProjectStatePlugin::Defaults

    def self.included(base)
      base.class_eval do
        before_validation :ensure_state_change_permitted
        def ensure_state_change_permitted
          u = User.current
          sol = User.find_by(login: 'solexa')
          cfid = CustomField.find_by(name: CUSTOM_PROJECT_STATE).id
          returnval = true
          if u == sol && self.custom_field_id == cfid
            o = CustomValue.find(self.id)
            returnval = StatesController::ORDERING[o.value] < StatesController::ORDERING[self.value]
          end
          return returnval
        end
      end
    end
  end

  module JournalPatch
    include ProjectStatePlugin::Defaults
    def self.included(base)
      base.class_eval do
        before_validation :ensure_state_change_permitted
        def ensure_state_change_permitted
          u = User.current
          sol = User.find_by(login: 'solexa')
          cfid = CustomField.find_by(name: CUSTOM_PROJECT_STATE).id
          returnval = true
          if u == sol
            self.details.each do |d|
              if d.prop_key.to_i == cfid
                returnval = StatesController::ORDERING[d.old_value] < StatesController::ORDERING[d.value]
              end
            end
          end
          return returnval
        end
      end
    end
  end

end
