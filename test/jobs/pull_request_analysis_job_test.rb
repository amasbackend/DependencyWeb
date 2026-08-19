require "test_helper"

class PullRequestAnalysisJobTest < ActiveSupport::TestCase
  test "runs fetch, diff, and parse_diff in sequence" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65)
    calls = []

    PullRequests::Fetch.stub :call, ->(pull_request_analysis:) { calls << :fetch } do
      Git::Diff.stub :call, ->(pull_request_analysis:) { calls << :diff } do
        Git::ParseDiff.stub :call, ->(pull_request_analysis:) { calls << :parse_diff } do
          PullRequestAnalysisJob.new.perform(pull_request_analysis_id: pull_request_analysis.id)
        end
      end
    end

    assert_equal [ :fetch, :diff, :parse_diff ], calls
  end
end
