import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["log", "input", "actions"]
  static values = {
    narrative: Array,
    universeTime: String,
    savedTextarea: String
  }

  connect() {
    this.loadExistingMessages()
    this.loadSavedInput()
    this.saveDebounceTimeout = null

    // Scroll to bottom after loading messages
    if (this.narrativeValue && this.narrativeValue.length > 0) {
      // Use requestAnimationFrame to ensure DOM is fully rendered
      requestAnimationFrame(() => {
        // Calculate the gap between textarea and Send button to use as breathing room
        const textareaRect = this.inputTarget.getBoundingClientRect()
        const actionsRect = this.actionsTarget.getBoundingClientRect()
        const gap = actionsRect.top - textareaRect.bottom

        // Scroll to the bottom of the chat container with breathing room
        this.element.scrollIntoView({ behavior: "instant", block: "end" })
        // Add breathing room matching the gap between textarea and button
        window.scrollBy(0, gap)
      })
    }
  }

  loadExistingMessages() {
    if (this.narrativeValue && this.narrativeValue.length > 0) {
      this.narrativeValue.forEach(message => {
        const text = message.content[0].text
        this.addMessage(message.role, text, { skipScroll: true })
      })
    }
  }

  handleKeydown(event) {
    if (event.key === "Enter") {
      if (event.metaKey || event.ctrlKey) {
        event.preventDefault()
        this.send()
      }
      // Plain Enter allows multiline - textarea will expand naturally
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.inputTarget.blur()
    }
  }

  handleInput(event) {
    // Auto-expand textarea to fit content
    const textarea = event.target

    // Save current scroll position before resizing
    const scrollY = window.scrollY

    textarea.style.height = "auto"
    textarea.style.height = textarea.scrollHeight + "px"

    // Restore scroll position to prevent auto-scroll
    window.scrollTo(0, scrollY)

    // Save input to localStorage immediately
    this.saveInputToStorage(textarea.value)

    // Debounced save to server (unless this is a programmatic event from loadSavedInput)
    if (!event.skipServerSave) {
      this.debouncedSaveToServer(textarea.value)
    }
  }

  saveInputToStorage(value) {
    const storageKey = `yours-input-${this.universeTimeValue || 'current'}`
    localStorage.setItem(storageKey, value)
  }

  debouncedSaveToServer(value) {
    // Clear existing timeout
    if (this.saveDebounceTimeout) {
      clearTimeout(this.saveDebounceTimeout)
    }

    // Set new timeout to save after 1.5 seconds of inactivity
    this.saveDebounceTimeout = setTimeout(() => {
      this.saveToServer(value)
    }, 1500)
  }

  async saveToServer(value) {
    try {
      const response = await fetch("/textarea", {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Assert-Yours-Universe-Time": this.universeTimeValue
        },
        body: JSON.stringify({
          textarea: value
        })
      })

      if (response.status === 409) {
        // Continuity divergence - this space moved forward elsewhere
        const data = await response.json()
        console.warn("Textarea save blocked: continuity divergence", data)
        // Could show a subtle notice here if desired
      } else if (!response.ok) {
        console.error("Failed to save textarea:", response.status)
      } else {
        // Success! Clear localStorage now that server has it
        const storageKey = `yours-input-${this.universeTimeValue || 'current'}`
        localStorage.removeItem(storageKey)
      }
    } catch (error) {
      console.error("Error saving textarea:", error)
      // Fail silently - localStorage still has it
    }
  }

  loadSavedInput() {
    // Prefer server-saved value over localStorage
    const serverSaved = this.savedTextareaValue
    const storageKey = `yours-input-${this.universeTimeValue || 'current'}`
    const localSaved = localStorage.getItem(storageKey)

    // Use whichever is longer (assumes the longer one is more recent)
    // In practice, server value is canonical for cross-device sync
    const savedInput = (serverSaved && serverSaved.length >= (localSaved || "").length)
      ? serverSaved
      : localSaved

    if (savedInput) {
      this.inputTarget.value = savedInput
      // Trigger input event to auto-expand (but don't re-trigger server save)
      const event = new Event('input')
      event.skipServerSave = true
      this.inputTarget.dispatchEvent(event)
    }
  }

  clearSavedInput() {
    const storageKey = `yours-input-${this.universeTimeValue || 'current'}`
    localStorage.removeItem(storageKey)

    // Also clear on server
    this.saveToServer("")
  }

  send() {
    const text = this.inputTarget.value.trim()
    if (!text) return

    // Clear any visible flash messages
    const flashMessages = document.querySelectorAll('[data-turbo-temporary]')
    flashMessages.forEach(flash => flash.remove())

    // Add user message to UI
    this.addMessage("user", text)

    // Clear input, reset height, and disable
    this.inputTarget.value = ""
    this.inputTarget.style.height = "auto"
    this.inputTarget.disabled = true

    // Add waiting state to actions
    this.actionsTarget.classList.add("waiting")

    // Cancel any pending debounced saves
    if (this.saveDebounceTimeout) {
      clearTimeout(this.saveDebounceTimeout)
      this.saveDebounceTimeout = null
    }

    // Immediately clear saved draft (both localStorage and server)
    this.clearSavedInput()

    // Create message object in Lightward AI format
    const message = {
      role: "user",
      content: [{ type: "text", text }]
    }

    // Stream response from backend
    this.streamResponse(message)
  }

  async streamResponse(message) {
    // Add pulsing assistant message placeholder with pink border
    const assistantElement = this.addPulsingMessage("assistant")
    let accumulatedText = ""

    try {
      const response = await fetch("/stream", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Assert-Yours-Universe-Time": this.universeTimeValue
        },
        body: JSON.stringify({
          message
        })
      })

      // Handle continuity divergence (409 Conflict)
      if (response.status === 409) {
        const data = await response.json()
        this.handleContinuityDivergence(data)
        this.inputTarget.disabled = false
        this.actionsTarget.classList.remove("waiting")
        this.inputTarget.focus()
        this.stopLoadingAnimation(assistantElement)
        assistantElement.remove()
        return
      }

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      // Read SSE stream
      const reader = response.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ""

      while (true) {
        const { done, value } = await reader.read()
        if (done) break

        buffer += decoder.decode(value, { stream: true })

        // Process complete SSE events (separated by blank lines)
        const events = buffer.split("\n\n")
        buffer = events.pop() || "" // Keep incomplete event in buffer

        for (const eventBlock of events) {
          if (!eventBlock.trim()) continue

          // Parse each event block for event: and data: fields
          let eventType = null
          let eventData = null

          const eventLines = eventBlock.split("\n")
          for (const line of eventLines) {
            if (line.startsWith("event: ")) {
              eventType = line.substring(7)
            } else if (line.startsWith("data: ")) {
              eventData = line.substring(6)
            }
          }

          if (eventType) {
            const data = eventData ? JSON.parse(eventData) : null
            this.handleSSEEvent(eventType, data, assistantElement)
          }
        }
      }
    } catch (error) {
      console.error("Stream error:", error)
      this.stopLoadingAnimation(assistantElement)
      assistantElement.textContent = `⚠️ Error: ${error.message}`
      assistantElement.classList.remove("pulsing", "loading")
    } finally {
      // Re-enable input and remove waiting state when done
      this.inputTarget.disabled = false
      this.actionsTarget.classList.remove("waiting")
      this.inputTarget.focus()
    }
  }

  handleSSEEvent(event, data, element) {
    switch (event) {
      case "message_start":
        this.stopLoadingAnimation(element)
        element.classList.remove("pulsing")
        element.style.animation = ""
        element.textContent = ""
        break

      case "content_block_delta":
        if (data.delta?.type === "text_delta") {
          this.stopLoadingAnimation(element)
          element.classList.remove("pulsing", "loading")
          element.style.animation = ""
          element.textContent += data.delta.text
        }
        break

      case "message_stop":
        this.stopLoadingAnimation(element)
        element.classList.remove("pulsing", "loading")
        element.style.animation = ""
        break

      case "universe_time":
        // Server sends updated universe_time after saving narrative
        // Update to the new universe_time
        this.universeTimeValue = data.universe_time
        break

      case "end":
        this.stopLoadingAnimation(element)
        element.classList.remove("pulsing", "loading")
        element.style.animation = ""
        break

      case "error":
        this.stopLoadingAnimation(element)
        element.textContent = `⚠️ ${data.error.message}`
        element.classList.remove("pulsing", "loading")
        element.style.animation = ""
        break
    }
  }

  addMessage(role, text, options = {}) {
    const messageElement = document.createElement("div")
    messageElement.classList.add("chat-message", role)
    messageElement.textContent = text

    this.logTarget.appendChild(messageElement)

    // Only scroll if not explicitly skipped (for initial load)
    if (!options.skipScroll) {
      messageElement.scrollIntoView({ behavior: "smooth", block: "end" })
    }

    return messageElement
  }

  addPulsingMessage(role) {
    const messageElement = this.addMessage(role, ".")
    messageElement.classList.add("pulsing")

    // Animate dots while waiting for first content
    let dotCount = 1
    messageElement.loadingInterval = setInterval(() => {
      dotCount = (dotCount % 3) + 1
      messageElement.textContent = ".".repeat(dotCount)
    }, 500)

    return messageElement
  }

  stopLoadingAnimation(element) {
    if (element.loadingInterval) {
      clearInterval(element.loadingInterval)
      element.loadingInterval = null
    }
  }

  handleContinuityDivergence(data) {
    // Create a gentle notice that this space moved forward elsewhere
    const noticeElement = document.createElement("div")
    noticeElement.classList.add("continuity-notice")

    noticeElement.innerHTML = `
      <div style="margin-bottom: 1rem;">${data.message}</div>
      <button onclick="window.location.reload()" style="cursor: pointer;">
        Refresh to continue
      </button>
    `

    this.logTarget.appendChild(noticeElement)
    noticeElement.scrollIntoView({ behavior: "smooth", block: "end" })
  }
}
