require "test_helper"

class RepositorySnapshotTest < ActiveSupport::TestCase
  test "lists and batch-reads files at a commit straight from the object database" do
    repo = build_fixture_git_repo
    sha = GitCommand.run("rev-parse", "HEAD", git_dir: File.join(repo, ".git")).strip
    snapshot = RepositorySnapshot.new(git_dir: File.join(repo, ".git"), sha: sha)

    assert_equal [ "README.md" ], snapshot.paths
    snapshot.preload([ "README.md", "missing.rb" ])
    assert_equal "hello", snapshot.read("README.md")
    assert_nil snapshot.read("missing.rb")
  end
end
