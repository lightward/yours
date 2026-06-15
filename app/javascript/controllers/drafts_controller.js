import { Controller } from "@hotwired/stimulus"

// Clears every locally-held draft. Wired to the "Start over" form via
// turbo:submit-start - which fires only once the confirm is accepted and
// the submission actually begins - so a cancelled confirm clears nothing.
// "No trace of what was" includes the drafts this device was holding.
export default class extends Controller {
  clearAll() {
    for (let i = localStorage.length - 1; i >= 0; i--) {
      const key = localStorage.key(i)
      if (key && key.startsWith("yours-input-")) {
        localStorage.removeItem(key)
      }
    }
  }
}
