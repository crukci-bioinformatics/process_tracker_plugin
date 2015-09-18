module ProjectStatePlugin
  module Utilities

    def semiString2List(s) 
      tags = s.split(';').map{ |t| t.strip }.select{|t| t.length > 0}
    end

    def includeProject(parent,pList)
      pList << parent
      Project.where(parent_id: parent.id).each do |proj|
        includeProject(proj,pList)
      end
    end

    def includedProjects
      roots = semiString2List(Setting.plugin_project_state['root_projects'])
      projList = Array.new
      roots.each do |root|
        Project.where(name: root).each do |p|
          includeProject(p,projList)
        end
      end
      return projList
    end
  end
end
