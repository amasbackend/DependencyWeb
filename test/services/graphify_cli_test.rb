require "test_helper"

class GraphifyCliTest < ActiveSupport::TestCase
  test "runs headlessly against a real directory and returns stdout" do
    dir = build_fixture_code_dir
    output = GraphifyCli.run("update", ".", chdir: dir)
    assert_match(/Rebuilt|updated/i, output)
  end

  test "version returns a version string" do
    assert_match(/\A\d+\.\d+\.\d+\z/, GraphifyCli.version)
  end

  test "raises NotInstalled when the binary genuinely cannot be found" do
    original_path = ENV["PATH"]
    ENV["PATH"] = "/no/such/directory"
    assert_raises(GraphifyCli::NotInstalled) { GraphifyCli.run("--version", chdir: Dir.pwd) }
  ensure
    ENV["PATH"] = original_path
  end
end
