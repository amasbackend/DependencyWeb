require "test_helper"

class Graphify::AnalyzeTest < ActiveSupport::TestCase
  test "runs graphify against a real directory and produces graphify-out" do
    dir = build_fixture_code_dir

    result = Graphify::Analyze.result(path: dir)

    assert result.success?
    assert_equal File.join(dir, "graphify-out"), result.output_dir
    assert File.exist?(File.join(result.output_dir, "graph.json"))
  end

  test "fails with a readable message when graphify is not on PATH" do
    dir = build_fixture_code_dir
    original_path = ENV["PATH"]
    ENV["PATH"] = "/no/such/directory"

    result = Graphify::Analyze.result(path: dir)

    assert_not result.success?
    assert_match(/Graphify 安裝失敗/, result.error)
  ensure
    ENV["PATH"] = original_path
  end
end
