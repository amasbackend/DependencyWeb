require "test_helper"

class GitCommandTest < ActiveSupport::TestCase
  test "returns stdout on success" do
    output = GitCommand.run("--version")
    assert_match(/git version/, output)
  end

  test "raises Error with stderr on failure" do
    error = assert_raises(GitCommand::Error) do
      GitCommand.run("not-a-real-git-subcommand")
    end
    assert_match(/not-a-real-git-subcommand/, error.message)
  end

  test "prepends --git-dir when given" do
    dir = build_fixture_git_repo
    output = GitCommand.run("log", "--oneline", git_dir: File.join(dir, ".git"))
    assert_match(/initial commit/, output)
  end

  test "auth_env reads the token lazily from ENV and points GIT_ASKPASS at the real script" do
    original = ENV["GITHUB_ACCESS_TOKEN"]
    ENV["GITHUB_ACCESS_TOKEN"] = "test-token-123"
    env = GitCommand.auth_env
    assert_equal "0", env["GIT_TERMINAL_PROMPT"]
    assert_equal "test-token-123", env["GIT_ASKPASS_TOKEN"]
    assert File.executable?(env["GIT_ASKPASS"])
  ensure
    ENV["GITHUB_ACCESS_TOKEN"] = original
  end

  test "the askpass script echoes the token from its environment, not argv" do
    stdout, = Open3.capture3(
      { "GIT_ASKPASS_TOKEN" => "secret-token" }, GitCommand::ASKPASS_SCRIPT, "Username for 'https://github.com': "
    )
    assert_equal "secret-token", stdout.strip
  end
end
