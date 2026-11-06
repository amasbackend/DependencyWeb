import { Controller } from "@hotwired/stimulus"

// Bridges the embedded Graphify graph.html (an iframe rendered by
// GraphifyHtmlRenderer) to the app-side Inspector: the iframe posts
// { type: "graphify:inspect", nodeId } whenever Graphify's own node panel
// opens a node, and this loads that node's business-feature detail into the
// Inspector Turbo Frame.
export default class extends Controller {
  static targets = ["frame", "inspector"]
  static values = { inspectorUrlTemplate: String }

  connect() {
    this.onMessage = this.#handleMessage.bind(this)
    window.addEventListener("message", this.onMessage)
  }

  disconnect() {
    window.removeEventListener("message", this.onMessage)
  }

  #handleMessage(event) {
    if (event.origin !== window.location.origin) return
    if (event.source !== this.frameTarget.contentWindow) return
    if (event.data?.type !== "graphify:inspect" || typeof event.data.nodeId !== "string") return

    this.inspectorTarget.src = this.inspectorUrlTemplateValue.replace("__NODE_ID__", encodeURIComponent(event.data.nodeId))
  }
}
