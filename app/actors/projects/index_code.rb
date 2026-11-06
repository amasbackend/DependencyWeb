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

      Project.transaction { replace_code_entities(entities) }

      self.code_entities_count = entities.size
      project.update!(analysis_status: "mapping_business_modules")
    rescue StandardError => e
      fail_with(I18n.t("actor.projects.index_code.failed", message: e.message))
    ensure
      Repositories::RemoveWorktree.call(project: project, name: WORKTREE_NAME)
    end

    private

    # Re-sync keeps each entity's row (matched by its file:class:method
    # signature) instead of delete-all-and-reinsert: past PR analyses
    # (changed entities, impact items) and feature links point at these rows,
    # and a bulk delete under them failed outright on the foreign keys —
    # 同步 on any already-analyzed project died at 掃描程式碼. Only entities
    # that no longer exist are removed, after their references are released.
    def replace_code_entities(entities)
      existing = project.code_entities.pluck(:signature_hash, :id).to_h
      rows = entities.map { |e| e.merge(project_id: project.id) }
      CodeEntity.upsert_all(rows, record_timestamps: true) if rows.any?

      stale_ids = existing.except(*rows.map { |r| r[:signature_hash] }).values
      return if stale_ids.empty?

      ChangedCodeEntity.where(code_entity_id: stale_ids).update_all(code_entity_id: nil)
      ImpactItem.where(code_entity_id: stale_ids).update_all(code_entity_id: nil)
      OperatorPathSegment.where(code_entity_id: stale_ids).update_all(code_entity_id: nil)
      FeatureCodeEntity.where(code_entity_id: stale_ids).delete_all
      CodeEntity.where(id: stale_ids).delete_all
    end

    def fail_with(message)
      project.update!(status: "failed", error_message: message)
      Rails.logger.error("[ProjectIndexCode:#{project.id}] #{message}")
      fail!(error: message)
    end
  end
end
