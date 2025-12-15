import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["option"]
  static values = {
    current: { type: String, default: "dark" }
  }

  connect() {
    // Load saved preference or default to dark
    const saved = localStorage.getItem("yours-theme")
    this.currentValue = saved || "dark"
    this.applyTheme()
  }

  select(event) {
    const theme = event.params.value
    this.currentValue = theme
    localStorage.setItem("yours-theme", theme)
    this.applyTheme()
  }

  applyTheme() {
    document.documentElement.setAttribute("data-theme", this.currentValue)
    this.updateButtons()
  }

  updateButtons() {
    this.optionTargets.forEach(button => {
      const buttonTheme = button.dataset.themeValueParam
      if (buttonTheme === this.currentValue) {
        button.classList.remove("secondary")
      } else {
        button.classList.add("secondary")
      }
    })
  }

  currentValueChanged() {
    this.updateButtons()
  }
}
