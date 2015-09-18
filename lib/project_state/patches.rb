
module ProjectStatePlugin

  module IssuePatch
    def self.included(base)
      base.class_eval do
        has_many :state_journals

        def state
          cfid = IssueCustomField.find_by(name: 'Project State').id
          s = CustomValue.find_by(customized: self, custom_field_id: cfid)
          return s.nil? ? nil : s.value
        end

        def state_timeout
          cfid = IssueCustomField.find_by(name: 'State Timeout').id
          s = CustomValue.find_by(customized: self, custom_field_id: cfid)
          return s.nil? ? nil : s.value.to_i
        end

        def hours_limit
          cfid = IssueCustomField.find_by(name: 'Hour Limit').id
          s = CustomValue.find_by(customized: self, custom_field_id: cfid)
          return s.nil? ? nil : s.value.to_f
          return s.value
        end

        def state_last_changed
          cfid = IssueCustomField.find_by(name: 'Project State').id
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
    def self.included(base)
      base.class_eval do
        before_validation :ensure_state_change_permitted
        def ensure_state_change_permitted
          u = User.current
          sol = User.find_by(login: 'solexa')
          cfid = CustomField.find_by(name: 'Project State').id
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
    def self.included(base)
      base.class_eval do
        before_validation :ensure_state_change_permitted
        def ensure_state_change_permitted
          u = User.current
          sol = User.find_by(login: 'solexa')
          cfid = CustomField.find_by(name: 'Project State').id
          returnval = true
          if u == sol
            STDERR.printf("checking journal...\n")
            self.details.each do |d|
              STDERR.printf("checking detail... %s %s\n",d.prop_key,cfid)
              if d.prop_key.to_i == cfid
                STDERR.printf("checking values %s --> %s ...\n",d.old_value,d.value)
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
