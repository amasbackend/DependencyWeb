module Projects
  # Re-runs the full import pipeline (§23: refetch default branch, update
  # base_sha, rebuild code index, business modules/features) for a project
  # that's already been imported once. Projects::Create's early-return for an
  # already-persisted project makes it unsuitable for this — Sync exists to
  # deliberately bypass that and re-trigger the same background job.
  class Sync < Actor
    input :project
    output :project

    # An import/sync already queued or running for this project — a second
    # click would only queue a duplicate run (seen in practice: 匯入 then
    # 同步 while no worker was up). Past this age it's treated as stuck
    # (e.g. the worker died mid-run) so the user isn't locked out forever.
    IN_PROGRESS_STATUSES = %w[pending importing syncing].freeze
    STUCK_AFTER = 30.minutes

    def call
      if IN_PROGRESS_STATUSES.include?(project.status.to_s) && project.updated_at > STUCK_AFTER.ago
        fail!(error: I18n.t("actor.projects.sync.in_progress"))
      end

      project.update!(status: "syncing")
      ProjectImportJob.perform_later(project_id: project.id)
    end
  end
end
