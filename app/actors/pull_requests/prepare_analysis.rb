module PullRequests
  # Fast, synchronous, controller-called — mirrors Projects::Create/Import's
  # split (Phase 2): this actor only implements re-run idempotency (§51) and
  # enqueues the background job; PullRequests::Fetch does the actual GitHub
  # API call. head_sha isn't known yet at this point (only Fetch retrieves
  # it), so idempotency is keyed on [project, pr_number] + non-terminal
  # status only — not the [project, pr_number, head_sha] triple originally
  # sketched in docs/architecture_plan.md §15, since that data doesn't exist
  # until the very call this actor is trying to avoid duplicating.
  class PrepareAnalysis < Actor
    input :project
    input :pr_number
    output :pull_request_analysis

    def call
      existing = project.pull_request_analyses
        .where(pr_number: pr_number)
        .where.not(status: PullRequestAnalysis::TERMINAL_STATUSES)
        .order(created_at: :desc)
        .first

      self.pull_request_analysis = existing || project.pull_request_analyses.create!(pr_number: pr_number)

      PullRequestAnalysisJob.perform_later(pull_request_analysis_id: pull_request_analysis.id)
    end
  end
end
