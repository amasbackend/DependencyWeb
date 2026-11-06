require "open3"

# Thin wrapper around the `graphify` CLI (https://github.com/Graphify-Labs/graphify,
# package `graphifyy`, installed via `uv tool install graphifyy` — see docs/setup.md).
#
# Verified in Phase 4 (docs/architecture_plan.md §9) to run fully headlessly
# from a plain shell — `graphify update <path>` builds a code graph via
# tree-sitter with NO LLM call and NO interactive prompt, exit code 0 on
# success. This resolved what was flagged as this project's biggest open
# integration risk: Graphify is documented primarily as a Claude Code/Cursor
# AI-IDE skill, but its underlying CLI is a genuine standalone tool.
class GraphifyCli
  class Error < StandardError; end
  class NotInstalled < Error; end

  BINARY = "graphify"

  def self.run(*args, chdir:)
    stdout, stderr, status = Open3.capture3(BINARY, *args, chdir: chdir.to_s)
    raise Error, stderr.presence || "graphify #{args.join(' ')} failed" unless status.success?

    stdout
  rescue Errno::ENOENT
    raise NotInstalled, "graphify command not found on PATH"
  end

  # The Python interpreter Graphify itself runs under (read from the
  # `graphify` launcher's shebang — `uv tool install` gives it a private
  # venv), so scripts can import Graphify's own modules, e.g. its graph.html
  # exporter, without a second install.
  def self.python
    launcher = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
                  .map { |dir| File.join(dir, BINARY) }
                  .find { |path| File.file?(path) && File.executable?(path) }
    raise NotInstalled, "graphify command not found on PATH" unless launcher

    shebang = File.open(launcher, &:readline).delete_prefix("#!").split
    shebang.first.end_with?("/env") ? shebang.second : shebang.first
  end

  def self.version
    run("--version", chdir: Dir.pwd).strip.delete_prefix("#{BINARY} ")
  rescue Error
    nil
  end
end
