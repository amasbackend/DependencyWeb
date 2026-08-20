require "test_helper"

class Graphify::AnalyzePullRequestTest < ActiveSupport::TestCase
  def add_pr_commit(fixture_dir, pr_number)
    Dir.chdir(fixture_dir) do
      system("git", "checkout", "-q", "-b", "pr-branch", exception: true)
      File.write("app/models/comment.rb", <<~RUBY)
        class Comment < ApplicationRecord
          belongs_to :user
        end
      RUBY
      system("git", "add", "-A", exception: true)
      system("git", "commit", "-qm", "add comment model", exception: true)
      head_sha = `git rev-parse HEAD`.strip
      system("git", "update-ref", "refs/pull/#{pr_number}/head", head_sha, exception: true)
      head_sha
    end
  end

  def build_scenario(pr_number)
    fixture_dir = build_fixture_rails_repo
    head_sha = add_pr_commit(fixture_dir, pr_number)

    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")
    assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?
    assert Repositories::FetchPullRequestRef.result(project: project, pr_number: pr_number).success?

    project.pull_request_analyses.create!(pr_number: pr_number, head_sha: head_sha)
  end

  def worktree_exists?(pr_number)
    Rails.application.config.x.repository_root
      .then { |root| Pathname.new(root).join("AMASTek", "PrjJieZhou", "worktrees", "pr-#{pr_number}") }
      .exist?
  end

  test "graphs the PR head worktree and persists graphify artifacts, cleaning up afterward" do
    with_scratch_repository_root do
      pull_request_analysis = build_scenario(65)

      result = Graphify::AnalyzePullRequest.result(pull_request_analysis: pull_request_analysis)

      assert result.success?
      pull_request_analysis.reload
      assert_equal "graphifying", pull_request_analysis.status

      formats = pull_request_analysis.graphify_artifacts.map(&:format)
      assert_includes formats, "graph_json"
      assert_includes formats, "graph_report_md"

      json_artifact = pull_request_analysis.graphify_artifacts.find_by(format: "graph_json")
      # The PR-branch-only file, only visible when Graphify runs against the
      # PR head worktree (not the base branch, which is Phase 5's job) —
      # confirms this actor really analyzes head_sha, not whatever happened
      # to be checked out already.
      assert json_artifact.parsed_content["nodes"].any? { |n| n["label"] == "Comment" }

      assert_not worktree_exists?(65)
    end
  end

  test "fails cleanly and cleans up the worktree when graphify is unavailable" do
    with_scratch_repository_root do
      pull_request_analysis = build_scenario(65)

      result = with_env("PATH" => "/no/such/directory") do
        Graphify::AnalyzePullRequest.result(pull_request_analysis: pull_request_analysis)
      end

      assert_not result.success?
      pull_request_analysis.reload
      assert_equal "failed", pull_request_analysis.status
      assert_equal "graphifying", pull_request_analysis.error_stage
      assert_not worktree_exists?(65)
    end
  end
end
