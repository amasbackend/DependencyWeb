class ProjectImportJob < ApplicationJob
  queue_as :default

  def perform(project_id:)
    project = Project.find(project_id)
    Projects::Import.call(project: project)
    Repositories::Clone.call(project: project)
    Projects::IndexCode.call(project: project)
    modules_result = Projects::BuildBusinessModules.call(project: project)
    Projects::BuildBusinessFeatures.call(project: project, parsed_routes: modules_result.parsed_routes)
  end
end
