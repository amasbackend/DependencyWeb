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
end
