class StatusTimeoutDefault < ActiveRecord::Base
  unloadable

  IRRELEVANT = ['Closed','Ongoing','Resolved']

  def self.populate_from_statuses()
    def_map = Hash.new()
    StatusTimeoutDefault.all.each do |d|
      def_map[d.status] = d
    end
    IssueStatus.all.each do |is|
      next if IRRELEVANT.include? is.name
      StatusTimeoutDefault.find_or_create_by(status: is.id) do |std|
        std.timeout = 0
        $pslog.info("Adding default timeout 0 for status #{is.name}")
      end
    end
  end

end
