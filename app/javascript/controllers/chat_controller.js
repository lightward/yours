import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["log", "input"]
  static values = { narrative: Array }

  connect() {
    console.log("Chat controller connected")
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

    // Add user message to UI
    this.addMessage("user", text)

    // Clear input
    this.inputTarget.value = ""

    // Create message object in Lightward AI format
    const message = {
      role: "user",
      content: [{ type: "text", text }]
    }

    // Stream response from backend
    this.streamResponse(message)
  }

  async streamResponse(message) {
    // Add pulsing assistant message placeholder
    const assistantElement = this.addPulsingMessage("assistant")
    let accumulatedText = ""

    try {
      const response = await fetch("/chat/stream", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ message })
      })

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
        const lines = buffer.split("\n\n")
        buffer = lines.pop() || ""

        for (const line of lines) {
          if (!line.trim()) continue

          const eventMatch = line.match(/^event: (.+)$/m)
          const dataMatch = line.match(/^data: (.+)$/m)

          if (eventMatch && dataMatch) {
            const event = eventMatch[1]
            const data = JSON.parse(dataMatch[1])

            this.handleSSEEvent(event, data, assistantElement)
          }
        }
      }
    } catch (error) {
      console.error("Stream error:", error)
      assistantElement.textContent = `⚠️ Error: ${error.message}`
      assistantElement.classList.remove("pulsing", "loading")
    }
  }

  handleSSEEvent(event, data, element) {
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
        break

      case "end":
        element.classList.remove("pulsing", "loading")
        element.style.animation = ""
        break

      case "error":
        element.textContent = `⚠️ ${data.error.message}`
        element.classList.remove("pulsing", "loading")
        element.style.animation = ""
        break
    }
  }

  addMessage(role, text) {
    const messageElement = document.createElement("div")
    messageElement.classList.add("chat-message", role)
    messageElement.textContent = text
    messageElement.style.cssText = `
      padding: 1rem;
      margin: 0.5rem 0;
      border-radius: 4px;
      background: ${role === "user" ? "#e3f2fd" : "#f5f5f5"};
      white-space: pre-wrap;
    `
    this.logTarget.appendChild(messageElement)
    messageElement.scrollIntoView({ behavior: "smooth", block: "end" })
    return messageElement
  }

  addPulsingMessage(role) {
    const messageElement = this.addMessage(role, "")
    messageElement.classList.add("pulsing")
    messageElement.style.cssText += `
      min-height: 2rem;
      animation: pulse 1.5s ease-in-out infinite;
    `
    return messageElement
  }
}
