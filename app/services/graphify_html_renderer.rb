require "open3"

# Renders a stored graph.json (whole graph, or a GraphifySubgraphBuilder node
# subset) into Graphify's own interactive graph.html — vis.js force layout,
# community legend, search and node panel — by calling Graphify's exporter
# through lib/graphify/render_html.py under Graphify's own interpreter, rather
# than re-implementing that visualization in this app. Returns the HTML string.
class GraphifyHtmlRenderer
  SCRIPT = Rails.root.join("lib/graphify/render_html.py").to_s

  def self.call(graph_json:, title:, node_ids: nil, seed_ids: [], direct_ids: [])
    Dir.mktmpdir("graphify-html") do |dir|
      graph_path = File.join(dir, "graph.json")
      options_path = File.join(dir, "options.json")
      # The exporter derives the page <title> from the output file name.
      output_path = File.join(dir, "#{title.parameterize}.html")

      File.write(graph_path, graph_json.is_a?(String) ? graph_json : JSON.generate(graph_json))
      File.write(options_path, JSON.generate(node_ids: node_ids, seed_ids: seed_ids, direct_ids: direct_ids))

      _stdout, stderr, status = Open3.capture3(GraphifyCli.python, "-I", SCRIPT, graph_path, options_path, output_path)
      raise GraphifyCli::Error, stderr.presence || "graphify html render failed" unless status.success? && File.exist?(output_path)

      File.read(output_path)
    end
  end
end
