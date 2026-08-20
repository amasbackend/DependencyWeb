class PullRequestAnalysisJob < ApplicationJob
  queue_as :default

  def perform(pull_request_analysis_id:)
    pull_request_analysis = PullRequestAnalysis.find(pull_request_analysis_id)
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
