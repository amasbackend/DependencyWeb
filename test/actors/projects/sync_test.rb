require "test_helper"

class Projects::SyncTest < ActiveJob::TestCase
  test "marks the project syncing and enqueues the import job" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")

    assert_enqueued_with(job: ProjectImportJob, args: [ { project_id: project.id } ]) do
      result = Projects::Sync.result(project: project)
      assert result.success?
    end

    assert_equal "syncing", project.reload.status
  end

  test "refuses a second sync while one is already queued or running" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "syncing")

    assert_no_enqueued_jobs do
      result = Projects::Sync.result(project: project)
      assert_not result.success?
      assert_match "正在匯入或同步中", result.error
    end
  end

  test "allows syncing a project stuck in progress for a long time" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "syncing")
    project.update_column(:updated_at, 2.hours.ago)

    assert_enqueued_with(job: ProjectImportJob) { assert Projects::Sync.result(project: project).success? }
  end
end
