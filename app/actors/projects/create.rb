module Projects
  class Create < Actor
    input :owner
    input :repository_name
    output :project

    def call
      self.project = Project.find_or_initialize_by(owner: owner, repository_name: repository_name)
      return if project.persisted?

      unless project.save
        fail!(error: project.errors.full_messages.join("、"))
        return
      end

      ProjectImportJob.perform_later(project_id: project.id)
    end
  end
end
