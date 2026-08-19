class PullRequestAnalysisJob < ApplicationJob
  queue_as :default

  def perform(pull_request_analysis_id:)
    pull_request_analysis = PullRequestAnalysis.find(pull_request_analysis_id)
    PullRequests::Fetch.call(pull_request_analysis: pull_request_analysis)
    Git::Diff.call(pull_request_analysis: pull_request_analysis)
    Git::ParseDiff.call(pull_request_analysis: pull_request_analysis)
  end
end
