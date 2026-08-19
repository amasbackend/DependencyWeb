module Git
  class Diff < Actor
    include RepositoryPaths

    input :pull_request_analysis
    output :changed_files

    def call
      pull_request_analysis.update!(status: "creating_workspace")
      Repositories::FetchPullRequestRef.call(project: project, pr_number: pull_request_analysis.pr_number)

      pull_request_analysis.update!(status: "diffing")
      files = GitDiffParser.call(name_status_z: name_status_output, full_diff: full_diff_output)

      PullRequestAnalysis.transaction do
        pull_request_analysis.changed_files.destroy_all
        pull_request_analysis.changed_files.create!(files) if files.any?
      end

      self.changed_files = pull_request_analysis.changed_files.to_a
    rescue StandardError => e
      fail_with(I18n.t("actor.git.diff.failed", message: e.message))
    end

    private

    def project
      pull_request_analysis.project
    end

    def name_status_output
      GitCommand.run(
        "diff", "--name-status", "-M", "-z", base_ref, head_ref, git_dir: bare_repo_path
      )
    end

    def full_diff_output
      GitCommand.run("diff", "--no-color", "-M", base_ref, head_ref, git_dir: bare_repo_path)
    end

    # merge_base_sha (from GitHub's compare API, Phase 8) is the correct
    # comparison point (§26) — not base_sha itself, which is just wherever
    # the base branch happened to be at PR-fetch time and may have moved
    # since the PR was opened. Falls back to base_sha only if merge_base_sha
    # somehow wasn't resolved (Phase 8's compare-API call is best-effort).
    def base_ref
      pull_request_analysis.merge_base_sha.presence || pull_request_analysis.base_sha
    end

    def head_ref
      pull_request_analysis.head_sha
    end

    def fail_with(message)
      pull_request_analysis.update!(status: "failed", error_message: message, error_stage: "diffing")
      Rails.logger.error("[PRAnalysis:#{pull_request_analysis.id}] #{message}")
      fail!(error: message)
    end
  end
end
