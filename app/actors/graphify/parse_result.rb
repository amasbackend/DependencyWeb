module Graphify
  # Persists Graphify's raw output (graph.json, GRAPH_REPORT.md) as
  # GraphifyArtifact rows tied to a PullRequestAnalysis — this is the layer
  # that knows about the DB; Graphify::Analyze itself stays generic. Only
  # graph.json is stored as parsed_content (structured, consumed
  # programmatically by later impact-mapping phases); GRAPH_REPORT.md is kept
  # as raw text only. graph.html is intentionally not persisted — it's a
  # multi-MB self-contained visualization better regenerated on demand than
  # stored in the DB (see docs/architecture_plan.md §4's JSON-vs-TEXT rule).
  class ParseResult < Actor
    input :pull_request_analysis
    input :output_dir
    output :graphify_artifacts

    FILES = {
      "graph_json" => "graph.json",
      "graph_report_md" => "GRAPH_REPORT.md",
    }.freeze

    def call
      self.graphify_artifacts = FILES.filter_map { |format, filename| store_artifact(format, filename) }

      return if graphify_artifacts.any?

      fail!(error: I18n.t("actor.graphify.parse_result.no_output"))
    end

    private

    def store_artifact(format, filename)
      path = File.join(output_dir.to_s, filename)
      return unless File.exist?(path)

      raw = File.read(path)

      pull_request_analysis.graphify_artifacts.create!(
        format: format,
        raw_content: raw,
        parsed_content: format == "graph_json" ? JSON.parse(raw) : nil,
        graphify_version: GraphifyCli.version,
        generated_at: Time.current,
      )
    end
  end
end
