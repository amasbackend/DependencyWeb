require "test_helper"

class Projects::IndexCodeTest < ActiveSupport::TestCase
  test "scans the base branch and persists classified code entities" do
    with_scratch_repository_root do
      fixture_dir = build_fixture_rails_repo
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")
      assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?

      result = Projects::IndexCode.result(project: project)

      assert result.success?
      project.reload
      assert_equal "mapping_business_modules", project.analysis_status
      assert result.code_entities_count.positive?
      assert_equal result.code_entities_count, project.code_entities.count

      assert project.code_entities.exists?(entity_type: "model", name: "User")
      assert project.code_entities.exists?(entity_type: "controller", name: "UsersController#show")
      assert project.code_entities.exists?(entity_type: "route")
      assert project.code_entities.exists?(entity_type: "view")

      # The scan worktree is ephemeral — cleaned up after use (§6).
      assert_not Rails.application.config.x.repository_root
        .then { |root| Pathname.new(root).join("AMASTek", "PrjJieZhou", "worktrees", "index") }
        .exist?
    end
  end

  test "re-running replaces stale entities rather than duplicating them" do
    with_scratch_repository_root do
      fixture_dir = build_fixture_rails_repo
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")
      assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?

      first = Projects::IndexCode.result(project: project)
      assert first.success?
      first_count = project.code_entities.count

      second = Projects::IndexCode.result(project: project)

      assert second.success?
      assert_equal first_count, project.code_entities.count
    end
  end

  test "fails cleanly and cleans up the worktree when graphify is unavailable" do
    with_scratch_repository_root do
      fixture_dir = build_fixture_rails_repo
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")
      assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?

      original_path = ENV["PATH"]
      result = begin
        ENV["PATH"] = "/no/such/directory"
        Projects::IndexCode.result(project: project)
      ensure
        ENV["PATH"] = original_path
      end

      assert_not result.success?
      project.reload
      assert_equal "failed", project.status
      assert_not Rails.application.config.x.repository_root
        .then { |root| Pathname.new(root).join("AMASTek", "PrjJieZhou", "worktrees", "index") }
        .exist?
    end
  end
end
