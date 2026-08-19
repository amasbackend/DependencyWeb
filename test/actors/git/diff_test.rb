require "test_helper"

class Git::DiffTest < ActiveSupport::TestCase
  def build_pr_scenario(fixture_dir)
    base_sha = nil
    merge_base_sha = nil
    head_sha = nil

    Dir.chdir(fixture_dir) do
      FileUtils.mkdir_p("app/models")
      File.write("app/models/user.rb", <<~RUBY)
        class User < ApplicationRecord
          def full_name
            "\#{first_name} \#{last_name}"
          end
        end
      RUBY
      system("git", "add", "-A", exception: true)
      system("git", "commit", "-qm", "add user model", exception: true)
      base_sha = `git rev-parse HEAD`.strip
      merge_base_sha = base_sha

      system("git", "checkout", "-q", "-b", "pr-branch", exception: true)
      File.write("app/models/user.rb", <<~RUBY)
        class User < ApplicationRecord
          def full_name
            "\#{first_name} \#{last_name}".strip
          end

          def archived?
            archived_at.present?
          end
        end
      RUBY
      system("git", "add", "-A", exception: true)
      system("git", "commit", "-qm", "trim full_name and add archived?", exception: true)
      head_sha = `git rev-parse HEAD`.strip
      system("git", "update-ref", "refs/pull/65/head", head_sha, exception: true)
    end

    [ base_sha, merge_base_sha, head_sha ]
  end

  test "persists structured ChangedFile rows from a real diff" do
    with_scratch_repository_root do
      fixture_dir = build_fixture_git_repo
      base_sha, merge_base_sha, head_sha = build_pr_scenario(fixture_dir)

      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main", base_sha: base_sha)
      assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?
      pull_request_analysis = project.pull_request_analyses.create!(
        pr_number: 65, base_sha: base_sha, head_sha: head_sha, merge_base_sha: merge_base_sha
      )

      result = Git::Diff.result(pull_request_analysis: pull_request_analysis)

      assert result.success?
      pull_request_analysis.reload
      assert_equal "diffing", pull_request_analysis.status
      changed_file = pull_request_analysis.changed_files.find_by(file_path: "app/models/user.rb")
      assert changed_file
      assert_equal "modified", changed_file.change_type
      assert_match "archived?", changed_file.patch
      assert changed_file.additions.positive?
    end
  end

  test "fails cleanly with a readable message when the PR ref cannot be found" do
    with_scratch_repository_root do
      fixture_dir = build_fixture_git_repo
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")
      assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?
      pull_request_analysis = project.pull_request_analyses.create!(
        pr_number: 999, base_sha: "deadbeef", head_sha: "deadbeef", merge_base_sha: "deadbeef"
      )

      result = Git::Diff.result(pull_request_analysis: pull_request_analysis)

      assert_not result.success?
      pull_request_analysis.reload
      assert_equal "failed", pull_request_analysis.status
      assert_equal "diffing", pull_request_analysis.error_stage
    end
  end
end
