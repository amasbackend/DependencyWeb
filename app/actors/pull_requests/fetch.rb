module PullRequests
  class Fetch < Actor
    input :pull_request_analysis
    output :pull_request_analysis

    def call
      pull_request_analysis.update!(status: "fetching_pr")

      client = GithubClient.build
      full_name = pull_request_analysis.project.github_full_name
      pr = client.pull_request(full_name, pull_request_analysis.pr_number)

      pull_request_analysis.update!(
        pr_title: pr.title,
        pr_description: pr.body,
        pr_author: pr.user&.login,
        base_branch: pr.base.ref,
        base_sha: pr.base.sha,
        head_branch: pr.head.ref,
        head_sha: pr.head.sha,
        merge_base_sha: merge_base_sha(client, full_name, pr),
      )
    rescue Octokit::NotFound
      fail_with(I18n.t("actor.pull_requests.fetch.not_found", pr_number: pull_request_analysis.pr_number))
    rescue Octokit::Unauthorized, Octokit::Forbidden
      fail_with(I18n.t("actor.pull_requests.fetch.unauthorized"))
    rescue StandardError => e
      fail_with(I18n.t("actor.pull_requests.fetch.failed", message: e.message))
    end

    private

    # GitHub's compare API returns the merge-base directly, so this needs no
    # local git access at all (unlike a plain `git merge-base` — Phase 8 has
    # no worktree yet; that's Phase 9). Best-effort: a failure here shouldn't
    # fail the whole metadata fetch, since it's independently recomputable
    # once a local worktree exists later.
    def merge_base_sha(client, full_name, pr)
      client.compare(full_name, pr.base.sha, pr.head.sha).merge_base_commit.sha
    rescue StandardError => e
      Rails.logger.warn("[PRAnalysis:#{pull_request_analysis.id}] could not resolve merge_base_sha: #{e.message}")
      nil
    end

    def fail_with(message)
      pull_request_analysis.update!(status: "failed", error_message: message, error_stage: "fetching_pr")
      Rails.logger.error("[PRAnalysis:#{pull_request_analysis.id}] #{message}")
      fail!(error: message)
    end
  end
end
