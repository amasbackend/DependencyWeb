import { Controller } from "@hotwired/stimulus"

// Toggles a details region's visibility, keeping aria-expanded in sync.
export default class extends Controller {
  static targets = ["content", "icon"]

  toggle(event) {
    const isHidden = this.contentTarget.classList.toggle("hidden")
    const expanded = !isHidden

    event.currentTarget.setAttribute("aria-expanded", expanded)
    this.iconTarget?.classList.toggle("rotate-180", expanded)
  }
}
