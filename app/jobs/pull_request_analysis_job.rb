class PullRequestAnalysisJob < ApplicationJob
  queue_as :default

  # Same group as ProjectImportJob: one repository-touching job per project.
  limits_concurrency to: 1, group: "ProjectRepository", duration: 30.minutes,
    key: ->(pull_request_analysis_id:) { PullRequestAnalysis.where(id: pull_request_analysis_id).pick(:project_id) }

  def perform(pull_request_analysis_id:)
    pull_request_analysis = PullRequestAnalysis.find(pull_request_analysis_id)
    # Defensive, not redundant: Repositories::Clone already clones-if-missing/
    # fetches-if-present (used today by Projects::Sync) — a project can reach
    # "ready" in the DB while its bare repo is absent from disk (e.g. moved
    # environments, or storage/ cleared independently of the DB), which would
    # otherwise only surface as a "not a git repository" failure deep inside
    # Git::Diff. Running it here means "分析 PR" never requires a separate
    # manual "同步母分支" first.
    Repositories::Clone.call(project: pull_request_analysis.project)
    PullRequests::Fetch.call(pull_request_analysis: pull_request_analysis)
    Git::Diff.call(pull_request_analysis: pull_request_analysis)
    Git::ParseDiff.call(pull_request_analysis: pull_request_analysis)
    Graphify::AnalyzePullRequest.call(pull_request_analysis: pull_request_analysis)
    Impacts::MapCodeEntities.call(pull_request_analysis: pull_request_analysis)
    Impacts::MapBusinessFeatures.call(pull_request_analysis: pull_request_analysis)
    Llm::AnalyzeTestScope.call(pull_request_analysis: pull_request_analysis)
    build = Reports::Build.call(pull_request_analysis: pull_request_analysis)
    Reports::RenderMarkdown.call(
      pull_request_analysis: pull_request_analysis, test_report: build.test_report, report_data: build.report_data
    )
  end
end
