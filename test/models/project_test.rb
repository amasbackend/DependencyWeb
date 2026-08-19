require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "defaults status to pending and analysis_status to queued" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")

    assert_equal "pending", project.status
    assert_equal "queued", project.analysis_status
  end

  test "derives github_full_name from owner and repository_name" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")

    assert_equal "AMASTek/PrjJieZhou", project.github_full_name
  end

  test "rejects duplicate github_full_name" do
    Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    duplicate = Project.new(owner: "AMASTek", repository_name: "PrjJieZhou")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:github_full_name], "已經被使用"
  end

  test "rejects owner with invalid characters" do
    project = Project.new(owner: "AMAS Tek/", repository_name: "PrjJieZhou")

    assert_not project.valid?
    assert_includes project.errors[:owner], "格式不正確"
  end
end
