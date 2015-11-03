require 'open-uri'
require 'json'

namespace :redmine do
  namespace :project_state do
    
    desc "Retrieve bank holidays from gov.uk."
    task :bank_holidays => :environment do
      url = Setting.plugin_project_state['holiday_url']   
      text = open(url) do |fd|
        lines = fd.readlines
        data = JSON.parse(lines.join(""))
        events = data['england-and-wales']['events']
        events.each do |event|
          d = Date.parse(event['date'])
          BankHoliday.find_or_create_by(holiday: d) do |h|
            h.name = event['title']
            h.notes = event['notes']
            STDERR.printf("Adding #{d}: #{h.name}\n")
          end
        end
      end
    end

  end
end
