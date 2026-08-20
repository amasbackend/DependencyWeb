module Graphify
  # Orchestrates §29 (Graphify PR Impact): creates a throwaway worktree at
  # the PR's head commit — Graphify needs real files on disk, unlike
  # Git::Diff (Phase 9), which reads the bare repo's object database
  # directly and never needs one — runs Graphify::Analyze against it, and
  # persists the result via Graphify::ParseResult. Always tears the worktree
  # down again, mirroring Projects::IndexCode's lifecycle for the
  # base-branch case (§8 — Graphify's own output must never touch the bare
  # repo or the real GitHub repository).
  class AnalyzePullRequest < Actor
    include RepositoryPaths

    input :pull_request_analysis
    output :graphify_artifacts

    def call
      pull_request_analysis.update!(status: "graphifying")

      # Defensive: a previous run that crashed after creating the worktree
      # but before the `ensure` cleanup would otherwise make CreateWorktree
      # fail with "already exists" on retry (§51).
      Repositories::RemoveWorktree.call(project: project, name: worktree_name)
      Repositories::CreateWorktree.call(project: project, name: worktree_name, ref: pull_request_analysis.head_sha)
      worktree_path = worktree_dir_for(worktree_name)

      graphify_result = Graphify::Analyze.call(path: worktree_path)
      self.graphify_artifacts = Graphify::ParseResult.call(
        pull_request_analysis: pull_request_analysis, output_dir: graphify_result.output_dir
      ).graphify_artifacts
    rescue StandardError => e
      fail_with(I18n.t("actor.graphify.analyze_pull_request.failed", message: e.message))
    ensure
      Repositories::RemoveWorktree.call(project: project, name: worktree_name)
    end

    private

    def project
      pull_request_analysis.project
    end

    def worktree_name
      "pr-#{pull_request_analysis.pr_number}"
    end

    def fail_with(message)
      pull_request_analysis.update!(status: "failed", error_message: message, error_stage: "graphifying")
      Rails.logger.error("[PRAnalysis:#{pull_request_analysis.id}] #{message}")
      fail!(error: message)
    end
  end
end
