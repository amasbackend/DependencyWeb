require "test_helper"

class Projects::CreateTest < ActiveSupport::TestCase
  # Projects::Create's only downstream responsibility is enqueuing the import
  # job — what that job then does internally (Import/Clone/IndexCode/...) is
  # exercised by their own actor tests, so stub the job itself here rather
  # than every actor it happens to chain, keeping this test unaffected as the
  # pipeline grows.
  test "creates a project and enqueues background import" do
    enqueued = false

    result = ProjectImportJob.stub :perform_later, ->(**) { enqueued = true } do
      Projects::Create.result(owner: "AMASTek", repository_name: "PrjJieZhou")
    end

    assert result.success?
    assert result.project.persisted?
    assert enqueued
  end

  test "returns the existing project without re-importing when already imported" do
    existing = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")

    result = Projects::Create.result(owner: "AMASTek", repository_name: "PrjJieZhou")

    assert result.success?
    assert_equal existing.id, result.project.id
  end

  test "fails with a validation error for an invalid owner" do
    result = Projects::Create.result(owner: "bad owner!", repository_name: "PrjJieZhou")

    assert_not result.success?
  end
end
