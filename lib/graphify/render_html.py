"""Renders a graph.json (or a node subset of it) with Graphify's own graph.html
exporter, so the Graphify tab looks and behaves exactly like Graphify's native
visualization instead of a hand-rolled re-implementation.

Run under Graphify's own interpreter (GraphifyCli.python), via
GraphifyHtmlRenderer:

    python -I render_html.py <graph.json> <options.json> <output.html>

options.json: {"node_ids": [...] | null, "seed_ids": [...], "direct_ids": [...]}
  node_ids null renders the whole graph; seed/direct ids get the PR-relevance
  accent (see HIGHLIGHT_SCRIPT), the only thing layered on top of Graphify.
"""
import json
import sys
from collections import defaultdict

import networkx as nx
from graphify.exporters.html import _viz_node_limit, to_html

NO_COMMUNITY_ID = -1

# Appended after Graphify's own <script>, reusing the globals it defines
# (nodesDS, showInfo). Marks changed (seed) nodes red and their direct callers
# amber, keeps seed labels always visible, and tells the embedding page which
# node was inspected so it can show app-side detail (business features).
HIGHLIGHT_SCRIPT = """<script>
(function () {
  const SEED_IDS = %(seed_ids)s;
  const DIRECT_IDS = %(direct_ids)s;
  const accent = (id, border, width, font) => {
    const n = nodesDS.get(id);
    if (!n) return null;
    return {
      id, borderWidth: width, font: font || n.font,
      color: { background: n.color.background, border, highlight: { background: "#ffffff", border } },
    };
  };
  nodesDS.update([
    ...DIRECT_IDS.map((id) => accent(id, "#f59e0b", 3)),
    ...SEED_IDS.map((id) => accent(id, "#ef4444", 4, { size: 14, color: "#ffffff" })),
  ].filter(Boolean));

  const graphifyShowInfo = showInfo;
  showInfo = function (nodeId) {
    graphifyShowInfo(nodeId);
    if (window.parent !== window) {
      window.parent.postMessage({ type: "graphify:inspect", nodeId }, window.location.origin);
    }
  };

  const stats = document.getElementById("stats");
  if (stats && SEED_IDS.length) {
    stats.insertAdjacentHTML("beforeend",
      '<br><span style="color:#ef4444">&#9679;</span> 紅框：PR 異動節點　' +
      '<span style="color:#f59e0b">&#9679;</span> 橘框：直接依賴');
  }
})();
</script>
"""


def js_safe(obj):
    return json.dumps(obj).replace("</", "<\\/")


def main(graph_path, options_path, output_path):
    graph = json.load(open(graph_path, encoding="utf-8"))
    options = json.load(open(options_path, encoding="utf-8"))
    nodes = {n["id"]: n for n in graph.get("nodes", [])}

    keep = set(nodes) if options.get("node_ids") is None else set(options["node_ids"]) & set(nodes)

    G = nx.DiGraph()
    for node_id in keep:
        G.add_node(node_id, **nodes[node_id])
    for link in graph.get("links", []):
        if link["source"] in keep and link["target"] in keep:
            G.add_edge(link["source"], link["target"], **link)

    communities = defaultdict(list)
    labels = {}
    for node_id in keep:
        node = nodes[node_id]
        cid = node.get("community")
        cid = NO_COMMUNITY_ID if cid is None else int(cid)
        communities[cid].append(node_id)
        labels[cid] = node.get("community_name") or ("其他" if cid == NO_COMMUNITY_ID else f"Community {cid}")

    # node_limit makes an oversized graph degrade to Graphify's aggregated
    # community view instead of raising.
    to_html(G, dict(communities), output_path, community_labels=labels, node_limit=_viz_node_limit())

    script = HIGHLIGHT_SCRIPT % {
        "seed_ids": js_safe(options.get("seed_ids", [])),
        "direct_ids": js_safe(options.get("direct_ids", [])),
    }
    with open(output_path, encoding="utf-8") as f:
        html = f.read()
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html.replace("</body>", script + "</body>", 1))


if __name__ == "__main__":
    main(*sys.argv[1:4])
