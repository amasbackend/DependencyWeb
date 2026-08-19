require "test_helper"

class Graphify::ParseResultTest < ActiveSupport::TestCase
  test "persists graph.json and GRAPH_REPORT.md as GraphifyArtifact rows" do
    dir = build_fixture_code_dir
    analyze = Graphify::Analyze.result(path: dir)
    assert analyze.success?

    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    pr_analysis = project.pull_request_analyses.create!(pr_number: 65)

    result = Graphify::ParseResult.result(pull_request_analysis: pr_analysis, output_dir: analyze.output_dir)

    assert result.success?
    formats = result.graphify_artifacts.map(&:format)
    assert_includes formats, "graph_json"
    assert_includes formats, "graph_report_md"

    json_artifact = result.graphify_artifacts.find { |a| a.format == "graph_json" }
    assert json_artifact.parsed_content.present?
    assert json_artifact.parsed_content["nodes"].any? { |n| n["label"] == "User" }
    assert json_artifact.graphify_version.present?

    report_artifact = result.graphify_artifacts.find { |a| a.format == "graph_report_md" }
    assert_nil report_artifact.parsed_content
    assert report_artifact.raw_content.present?
  end

  test "fails when the output directory has nothing to parse" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    pr_analysis = project.pull_request_analyses.create!(pr_number: 65)
    empty_dir = Dir.mktmpdir("empty-graphify-out")

    result = Graphify::ParseResult.result(pull_request_analysis: pr_analysis, output_dir: empty_dir)

    assert_not result.success?
  ensure
    FileUtils.remove_entry(empty_dir) if empty_dir && File.exist?(empty_dir)
  end
end
