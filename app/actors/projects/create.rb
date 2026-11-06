module Projects
  class Create < Actor
    input :owner
    input :repository_name
    # §54: branch defaults to whatever GitHub itself reports as the
    # repository's default branch (fetched in Projects::Import) — this is
    # only for the Advanced Option override, a manual value the operator
    # explicitly chose instead of trusting GitHub's default.
    input :default_branch, default: nil, allow_nil: true
    output :project
    # True when the project was already imported — nothing new is queued, so
    # the caller must not tell the user an import has started.
    output :already_imported, default: false

    def call
      self.project = Project.find_or_initialize_by(owner: owner, repository_name: repository_name)
      if project.persisted?
        self.already_imported = true
        return
      end

      project.default_branch = default_branch if default_branch.present?

      unless project.save
        fail!(error: project.errors.full_messages.join("、"))
        return
      end

      ProjectImportJob.perform_later(project_id: project.id)
    end
  end
end
