module Graphify
  # Runs Graphify against a directory (a PR analysis worktree, per §29 — never
  # the bare repo or a shared working directory) and returns where its output
  # landed. Deliberately generic (path in, output_dir out) rather than coupled
  # to PullRequestAnalysis, so it stays reusable wherever a code graph is
  # needed — status bookkeeping is the caller's responsibility, matching how
  # Repositories::Fetch stays generic rather than assuming "sync" semantics.
  class Analyze < Actor
    input :path
    output :output_dir

    def call
      # `update` both builds a fresh graph and refreshes an existing one — it
      # is purely local tree-sitter extraction, no LLM call, verified in the
      # Phase 4 spike (docs/architecture_plan.md §9).
      GraphifyCli.run("update", ".", chdir: path)
      self.output_dir = File.join(path.to_s, "graphify-out")
    rescue GraphifyCli::NotInstalled
      fail!(error: I18n.t("actor.graphify.analyze.not_installed"))
    rescue StandardError => e
      fail!(error: I18n.t("actor.graphify.analyze.failed", message: e.message))
    end
  end
end
