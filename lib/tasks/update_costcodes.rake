require 'i18n'

require 'simple_xlsx_reader'
require_dependency File.expand_path(File.dirname(__FILE__)+'/../project_state/finance')
require_dependency File.expand_path(File.dirname(__FILE__)+'/../project_state/utils')


namespace :redmine do
  namespace :project_state do
    
    desc "Update research group cost centres from spreadsheet"
    task :update_costcodes, [:filename,:year,:month] => [:environment] do |t,args|
      include ProjectStatePlugin::Utilities

      # load spreadsheet, get results for year, month
      sheet = FinanceSheet.new(args[:filename])
      data =  sheet.retrieve(args[:year],args[:month])
      @grants = data[0].each.map{|g| g.nil? ? nil : I18n.transliterate(g).downcase}
      @codes = data[1]
      # test uniqueness of funding source column
      # retrieve 1st block only (up to 1st gap?)
      # turn into map: src -> cost code

      # retrieve Research Group projects
      cfid = CustomField.find_by(type: 'ProjectCustomField', name: 'Cost Centre').id
      pset = collectProjects("Research Groups")
      Project.where(id: pset).each do |proj|
        code = get_project_costcode(proj,@grants,@codes)
        if !code.nil?
          cfs = proj.custom_values.select{|x| x.customized_type=="Project" && x.custom_field_id == cfid}
          if cfs.length == 0
            proj.custom_values << CustomValue.create(customized: proj, custom_field_id: cfid, value: code)
            $pslog.info("Project #{proj.name}: added cost centre '#{code}'")
          elsif cfs.length == 1
            ocode = cfs[0].value
            if ocode != code
              cfs[0].value = code
              cfs[0].save
              $pslog.info("Project #{proj.name}: updated cost centre '#{ocode}' ==> '#{code}'")
            end
          else
            $pslog.error("Project '#{proj.name}': #{cfs.length} custom values for 'Cost Centre'... please investigate.")
          end
        end
      end
    end

  end
end
