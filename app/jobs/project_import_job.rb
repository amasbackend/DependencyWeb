class ProjectImportJob < ApplicationJob
  queue_as :default

  # Import/sync and PR analysis of one project all clone/fetch into, and
  # create worktrees in, the same repository directory — two of them running
  # at once (e.g. 匯入 then 同步 clicked before a worker picked the first up)
  # race on it. One per project at a time; later ones wait their turn.
  limits_concurrency to: 1, key: ->(project_id:) { project_id }, group: "ProjectRepository", duration: 30.minutes

  def perform(project_id:)
    project = Project.find(project_id)
    Projects::Import.call(project: project)
    Repositories::Clone.call(project: project)
    Projects::IndexCode.call(project: project)
    modules_result = Projects::BuildBusinessModules.call(project: project)
    Projects::BuildBusinessFeatures.call(project: project, parsed_routes: modules_result.parsed_routes)
  end
end
