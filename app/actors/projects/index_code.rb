module Projects
  class IndexCode < Actor
    include RepositoryPaths

    WORKTREE_NAME = "index"

    input :project
    output :code_entities_count

    def call
      project.update!(analysis_status: "scanning_code")

      # Defensive: a previous run that crashed after creating the worktree but
      # before reaching the `ensure` cleanup would otherwise make CreateWorktree
      # fail with "already exists" on retry — RemoveWorktree is a no-op if
      # there's nothing to remove, so this keeps the whole actor safely re-runnable (§51).
      Repositories::RemoveWorktree.call(project: project, name: WORKTREE_NAME)
      Repositories::CreateWorktree.call(project: project, name: WORKTREE_NAME, ref: project.base_sha)
      worktree_path = worktree_dir_for(WORKTREE_NAME)

      graphify_result = Graphify::Analyze.call(path: worktree_path)
      entities = CodeEntityExtractor.call(
        graph_json_path: File.join(graphify_result.output_dir, "graph.json"),
        worktree_path: worktree_path,
      )

      Project.transaction do
        project.code_entities.delete_all
        CodeEntity.insert_all!(entities.map { |e| e.merge(project_id: project.id) }, record_timestamps: true) if entities.any?
      end

      self.code_entities_count = entities.size
      project.update!(analysis_status: "mapping_business_modules")
    rescue StandardError => e
      fail_with(I18n.t("actor.projects.index_code.failed", message: e.message))
    ensure
      Repositories::RemoveWorktree.call(project: project, name: WORKTREE_NAME)
    end

    private

    def fail_with(message)
      project.update!(status: "failed", error_message: message)
      Rails.logger.error("[ProjectIndexCode:#{project.id}] #{message}")
      fail!(error: message)
    end
  end
end
