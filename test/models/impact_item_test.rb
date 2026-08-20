require "test_helper"

class ImpactItemTest < ActiveSupport::TestCase
  def build_item(impact_level)
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou-#{SecureRandom.hex(4)}")
    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65)
    pull_request_analysis.impact_items.create!(impact_level: impact_level)
  end

  test "direct_change and direct_dependency are high risk" do
    assert_equal "high", build_item("direct_change").risk_level
    assert_equal "high", build_item("direct_dependency").risk_level
  end

  test "indirect_dependency is medium risk" do
    assert_equal "medium", build_item("indirect_dependency").risk_level
  end

  test "regression_candidate is low risk" do
    assert_equal "low", build_item("regression_candidate").risk_level
  end

  test "risk_label returns the matching Traditional Chinese label" do
    assert_equal "高風險", build_item("direct_change").risk_label
  end
end
