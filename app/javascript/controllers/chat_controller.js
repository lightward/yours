import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["log", "input"]
  static values = {
    narrative: Array,
    universeTime: String
  }

  connect() {
    this.loadExistingMessages()
  }

  loadExistingMessages() {
    if (this.narrativeValue && this.narrativeValue.length > 0) {
      this.narrativeValue.forEach(message => {
        const text = message.content[0].text
        this.addMessage(message.role, text)
      })
    }
  }

  handleKeydown(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault()
      this.send()
    }
  }

  send() {
    const text = this.inputTarget.value.trim()
    if (!text) return

    // Clear any visible flash messages
    const flashMessages = document.querySelectorAll('[data-turbo-temporary]')
    flashMessages.forEach(flash => flash.remove())

    // Add user message to UI
    this.addMessage("user", text)

    // Clear and disable input
    this.inputTarget.value = ""
    this.inputTarget.disabled = true

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
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          message,
          universe_time: this.universeTimeValue
        })
      })

      // Handle continuity divergence (409 Conflict)
      if (response.status === 409) {
        const data = await response.json()
        this.handleContinuityDivergence(data)
        this.inputTarget.disabled = false
        this.inputTarget.focus()
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
      assistantElement.textContent = `⚠️ Error: ${error.message}`
      assistantElement.classList.remove("pulsing", "loading")
      assistantElement.style.borderLeftColor = getComputedStyle(document.documentElement).getPropertyValue('--message-border').trim()
    } finally {
      // Re-enable input when done
      this.inputTarget.disabled = false
      this.inputTarget.focus()
    }
  }

  handleSSEEvent(event, data, element) {
    const messageBorder = getComputedStyle(document.documentElement).getPropertyValue('--message-border').trim()

    switch (event) {
      case "message_start":
        element.classList.remove("pulsing")
        element.style.animation = ""
        break

      case "content_block_delta":
        if (data.delta?.type === "text_delta") {
          element.classList.remove("pulsing", "loading")
          element.style.animation = ""
          element.textContent += data.delta.text
        }
        break

      case "message_stop":
        element.classList.remove("pulsing", "loading")
        element.style.animation = ""
        element.style.borderLeftColor = messageBorder
        break

      case "universe_time":
        // Server sends updated universe_time after saving narrative
        this.universeTimeValue = data.universe_time
        break

      case "end":
        element.classList.remove("pulsing", "loading")
        element.style.animation = ""
        element.style.borderLeftColor = messageBorder
        break

      case "error":
        element.textContent = `⚠️ ${data.error.message}`
        element.classList.remove("pulsing", "loading")
        element.style.animation = ""
        element.style.borderLeftColor = messageBorder
        break
    }
  }

  addMessage(role, text) {
    const messageElement = document.createElement("div")
    messageElement.classList.add("chat-message", role)
    messageElement.textContent = text

    const userBg = getComputedStyle(document.documentElement).getPropertyValue('--user-message-bg').trim()
    const assistantBg = getComputedStyle(document.documentElement).getPropertyValue('--assistant-message-bg').trim()
    const messageBorder = getComputedStyle(document.documentElement).getPropertyValue('--message-border').trim()
    const accent = getComputedStyle(document.documentElement).getPropertyValue('--accent').trim()

    messageElement.style.cssText = `
      padding: 1rem;
      border-radius: 8px;
      background: ${role === "user" ? userBg : assistantBg};
      border-left: 3px solid ${role === "user" ? accent : messageBorder};
      white-space: pre-wrap;
      font-family: 'Lightward Favorit Mono', 'Courier New', monospace;
    `
    this.logTarget.appendChild(messageElement)
    messageElement.scrollIntoView({ behavior: "smooth", block: "end" })
    return messageElement
  }

  addPulsingMessage(role) {
    const messageElement = this.addMessage(role, "")
    messageElement.classList.add("pulsing")
    const accentActive = getComputedStyle(document.documentElement).getPropertyValue('--accent-active').trim()
    messageElement.style.cssText += `
      min-height: 3rem;
      animation: pulse 1.5s ease-in-out infinite;
      border-left-color: ${accentActive};
    `
    return messageElement
  }

  handleContinuityDivergence(data) {
    // Create a gentle notice that this space moved forward elsewhere
    const noticeElement = document.createElement("div")
    const accent = getComputedStyle(document.documentElement).getPropertyValue('--accent').trim()
    const accentBg = getComputedStyle(document.documentElement).getPropertyValue('--user-message-bg').trim()

    noticeElement.style.cssText = `
      padding: 1.5rem;
      border-radius: 8px;
      background: ${accentBg};
      border-left: 3px solid ${accent};
      margin: 1rem 0;
      font-family: 'Lightward Favorit Mono', 'Courier New', monospace;
    `

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
