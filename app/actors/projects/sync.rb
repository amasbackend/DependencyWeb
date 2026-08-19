module Projects
  # Re-runs the full import pipeline (§23: refetch default branch, update
  # base_sha, rebuild code index, business modules/features) for a project
  # that's already been imported once. Projects::Create's early-return for an
  # already-persisted project makes it unsuitable for this — Sync exists to
  # deliberately bypass that and re-trigger the same background job.
  class Sync < Actor
    input :project
    output :project

    def call
      project.update!(status: "syncing")
      ProjectImportJob.perform_later(project_id: project.id)
    end
  end
end
