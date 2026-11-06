require "test_helper"
require "ostruct"

class PullRequestAnalysisJobTest < ActiveSupport::TestCase
  test "runs the full pipeline, phase by phase, in sequence" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65)
    calls = []
    fake_build_result = OpenStruct.new(test_report: :fake_report, report_data: :fake_data)

    Repositories::Clone.stub :call, ->(project:) { calls << :clone } do
      PullRequests::Fetch.stub :call, ->(pull_request_analysis:) { calls << :fetch } do
        Git::Diff.stub :call, ->(pull_request_analysis:) { calls << :diff } do
          Git::ParseDiff.stub :call, ->(pull_request_analysis:) { calls << :parse_diff } do
            Graphify::AnalyzePullRequest.stub :call, ->(pull_request_analysis:) { calls << :graphify } do
              Impacts::MapCodeEntities.stub :call, ->(pull_request_analysis:) { calls << :map_code_entities } do
                Impacts::MapBusinessFeatures.stub :call, ->(pull_request_analysis:) { calls << :map_business_features } do
                  Llm::AnalyzeTestScope.stub :call, ->(pull_request_analysis:) { calls << :llm_analyze } do
                    Reports::Build.stub :call, ->(pull_request_analysis:) { calls << :report_build; fake_build_result } do
                      Reports::RenderMarkdown.stub :call, ->(pull_request_analysis:, test_report:, report_data:) {
                        calls << :render_markdown
                        assert_equal :fake_report, test_report
                        assert_equal :fake_data, report_data
                      } do
                        PullRequestAnalysisJob.new.perform(pull_request_analysis_id: pull_request_analysis.id)
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    assert_equal [
      :clone, :fetch, :diff, :parse_diff, :graphify, :map_code_entities, :map_business_features,
      :llm_analyze, :report_build, :render_markdown,
    ], calls
  end
end
