require "open3"

# Read-only view of a bare repository's files at one commit, read straight
# from the object database (`git ls-tree` / `git cat-file --batch`) — no
# worktree checkout needed, unlike Graphify. Used to build the screen catalog
# (ScreenCatalog) and trace code references (ScreenImpactLocator) against the
# exact code the PR head contains.
class RepositorySnapshot
  def initialize(git_dir:, sha:)
    @git_dir = git_dir.to_s
    @sha = sha
    @contents = {}
  end

  def paths
    @paths ||= GitCommand.run("ls-tree", "-r", "--name-only", @sha, git_dir: @git_dir).split("\n")
  end

  # nil when the path doesn't exist at this commit.
  def read(path)
    preload([ path ]) unless @contents.key?(path)
    @contents[path]
  end

  # Batch-reads many files in one `git cat-file --batch` round trip, rather
  # than one process per file — the screen catalog reads hundreds.
  def preload(wanted)
    missing = wanted.reject { |p| @contents.key?(p) }
    return if missing.empty?

    stdin = missing.map { |p| "#{@sha}:#{p}\n" }.join
    stdout, stderr, status = Open3.capture3("git", "--git-dir=#{@git_dir}", "cat-file", "--batch", stdin_data: stdin, binmode: true)
    raise GitCommand::Error, stderr.presence || "git cat-file --batch failed" unless status.success?

    parse_batch(stdout, missing)
  end

  private

  def parse_batch(output, requested)
    offset = 0
    requested.each do |path|
      header_end = output.index("\n", offset)
      header = output.byteslice(offset, header_end - offset)
      offset = header_end + 1

      if header.end_with?(" missing")
        @contents[path] = nil
        next
      end

      size = header.split.last.to_i
      @contents[path] = output.byteslice(offset, size).force_encoding(Encoding::UTF_8).scrub
      offset += size + 1
    end
  end
end
