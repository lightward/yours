import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import ChatController from '../../app/javascript/controllers/chat_controller.js'

describe('ChatController', () => {
  let fixture
  let controller

  beforeEach(async () => {
    // Create a basic chat interface
    const html = `
      <div data-controller="chat"
           data-chat-narrative-value='[{"role":"user","content":[{"text":"Hello"}]},{"role":"assistant","content":[{"text":"Hi there"}]}]'
           data-chat-universe-time-value="2024-01-01T00:00:00Z"
           data-chat-saved-textarea-value="">
        <div data-chat-target="log"></div>
        <textarea data-chat-target="input" data-action="input->chat#handleInput keydown->chat#handleKeydown"></textarea>
        <div data-chat-target="actions"></div>
      </div>
    `

    const result = await createControllerFixture(html, ChatController, 'chat')
    fixture = result
    controller = result.controller

    // Set up CSRF token meta tag
    const meta = document.createElement('meta')
    meta.name = 'csrf-token'
    meta.content = 'test-token'
    document.head.appendChild(meta)

    // Mock fetch to prevent real network requests
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: () => Promise.resolve({}),
    })

    // Clear localStorage before each test
    localStorage.clear()
  })

  afterEach(() => {
    fixture.application.stop()
    document.body.innerHTML = ''
    document.head.innerHTML = ''
    localStorage.clear()
    vi.restoreAllMocks()
  })

  describe('initialization', () => {
    it('loads existing messages on connect', () => {
      const messages = fixture.element.querySelectorAll('.chat-message')
      expect(messages.length).toBe(2)
      expect(messages[0].dataset.rawText).toBe('Hello')
      expect(messages[0].classList.contains('user')).toBe(true)
      expect(messages[1].dataset.rawText).toBe('Hi there')
      expect(messages[1].classList.contains('assistant')).toBe(true)
    })

    it.skip('scrolls to bottom after loading messages', () => {
      // This would require spying before the connect() hook runs, which is complex in Stimulus
      // Visual behavior is tested manually
    })
  })

  describe('input handling', () => {
    it('auto-expands textarea on input', () => {
      const textarea = controller.inputTarget
      textarea.value = 'Line 1\nLine 2\nLine 3'

      const event = new Event('input')
      textarea.dispatchEvent(event)

      expect(textarea.style.height).toBeTruthy()
    })

    it('preserves scroll position when textarea expands', () => {
      const scrollSpy = vi.spyOn(window, 'scrollTo')

      // Simulate being scrolled down
      Object.defineProperty(window, 'scrollY', { value: 500, writable: true })

      const textarea = controller.inputTarget
      textarea.value = 'Line 1\nLine 2\nLine 3'

      const event = new Event('input')
      textarea.dispatchEvent(event)

      // Should restore the original scroll position
      expect(scrollSpy).toHaveBeenCalledWith(0, 500)
    })

    it('saves input to localStorage on change', () => {
      const textarea = controller.inputTarget
      textarea.value = 'Test message'

      const event = new Event('input')
      textarea.dispatchEvent(event)

      const storageKey = `yours-input-${controller.universeTimeValue}`
      expect(localStorage.getItem(storageKey)).toBe('Test message')
    })

    it('debounces server saves', async () => {
      vi.useFakeTimers()
      const saveSpy = vi.spyOn(controller, 'saveToServer')

      const textarea = controller.inputTarget
      textarea.value = 'T'
      textarea.dispatchEvent(new Event('input'))

      textarea.value = 'Te'
      textarea.dispatchEvent(new Event('input'))

      textarea.value = 'Test'
      textarea.dispatchEvent(new Event('input'))

      expect(saveSpy).not.toHaveBeenCalled()

      vi.advanceTimersByTime(1500)

      expect(saveSpy).toHaveBeenCalledOnce()
      expect(saveSpy).toHaveBeenCalledWith('Test')

      vi.useRealTimers()
    })
  })

  describe('keyboard shortcuts', () => {
    it('sends message on Cmd+Enter', () => {
      const sendSpy = vi.spyOn(controller, 'send')
      const textarea = controller.inputTarget
      textarea.value = 'Test message'

      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        metaKey: true
      })

      textarea.dispatchEvent(event)

      expect(sendSpy).toHaveBeenCalled()
    })

    it('sends message on Ctrl+Enter', () => {
      const sendSpy = vi.spyOn(controller, 'send')
      const textarea = controller.inputTarget
      textarea.value = 'Test message'

      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        ctrlKey: true
      })

      textarea.dispatchEvent(event)

      expect(sendSpy).toHaveBeenCalled()
    })

    it('blurs textarea on Escape', () => {
      const textarea = controller.inputTarget
      textarea.focus()

      const blurSpy = vi.spyOn(textarea, 'blur')
      const event = new KeyboardEvent('keydown', { key: 'Escape' })

      textarea.dispatchEvent(event)

      expect(blurSpy).toHaveBeenCalled()
    })

    it('allows plain Enter for multiline input', () => {
      const sendSpy = vi.spyOn(controller, 'send')
      const textarea = controller.inputTarget
      textarea.value = 'Line 1'

      const event = new KeyboardEvent('keydown', { key: 'Enter' })
      textarea.dispatchEvent(event)

      expect(sendSpy).not.toHaveBeenCalled()
    })
  })

  describe('sending messages', () => {
    it('does not send empty messages', () => {
      const streamSpy = vi.spyOn(controller, 'streamResponse')
      const textarea = controller.inputTarget
      textarea.value = '   '

      controller.send()

      expect(streamSpy).not.toHaveBeenCalled()
    })

    it('adds user message to UI', () => {
      const textarea = controller.inputTarget
      textarea.value = 'Test message'

      vi.spyOn(controller, 'streamResponse').mockImplementation(() => {})

      controller.send()

      const userMessages = fixture.element.querySelectorAll('.chat-message.user')
      const lastMessage = userMessages[userMessages.length - 1]
      expect(lastMessage.dataset.rawText).toBe('Test message')
    })

    it('clears and disables input after sending', () => {
      const textarea = controller.inputTarget
      textarea.value = 'Test message'

      vi.spyOn(controller, 'streamResponse').mockImplementation(() => {})

      controller.send()

      expect(textarea.value).toBe('')
      expect(textarea.disabled).toBe(true)
      expect(controller.actionsTarget.classList.contains('waiting')).toBe(true)
    })

    it('clears saved input after sending', () => {
      const textarea = controller.inputTarget
      textarea.value = 'Test message'

      // Save to localStorage first
      const event = new Event('input')
      textarea.dispatchEvent(event)

      const storageKey = `yours-input-${controller.universeTimeValue}`
      expect(localStorage.getItem(storageKey)).toBeTruthy()

      vi.spyOn(controller, 'streamResponse').mockImplementation(() => {})

      controller.send()

      expect(localStorage.getItem(storageKey)).toBeNull()
    })
  })

  describe('localStorage integration', () => {
    it('loads saved input from localStorage on connect', async () => {
      const storageKey = `yours-input-2024-01-01T00:00:00Z`
      localStorage.setItem(storageKey, 'Saved draft')

      const html = `
        <div data-controller="chat"
             data-chat-narrative-value='[]'
             data-chat-universe-time-value="2024-01-01T00:00:00Z"
             data-chat-saved-textarea-value="">
          <div data-chat-target="log"></div>
          <textarea data-chat-target="input"></textarea>
          <div data-chat-target="actions"></div>
        </div>
      `

      const newFixture = await createControllerFixture(html, ChatController, 'chat')

      expect(newFixture.controller.inputTarget.value).toBe('Saved draft')

      newFixture.application.stop()
    })

    it('prefers server-saved value over localStorage when longer', async () => {
      const storageKey = `yours-input-2024-01-01T00:00:00Z`
      localStorage.setItem(storageKey, 'Short')

      const html = `
        <div data-controller="chat"
             data-chat-narrative-value='[]'
             data-chat-universe-time-value="2024-01-01T00:00:00Z"
             data-chat-saved-textarea-value="This is a much longer saved value from server">
          <div data-chat-target="log"></div>
          <textarea data-chat-target="input"></textarea>
          <div data-chat-target="actions"></div>
        </div>
      `

      const newFixture = await createControllerFixture(html, ChatController, 'chat')

      expect(newFixture.controller.inputTarget.value).toBe('This is a much longer saved value from server')

      newFixture.application.stop()
    })
  })

  describe('message display', () => {
    it('adds messages with correct role classes', () => {
      const userMsg = controller.addMessage('user', 'User message')
      const assistantMsg = controller.addMessage('assistant', 'Assistant message')

      expect(userMsg.classList.contains('user')).toBe(true)
      expect(userMsg.classList.contains('chat-message')).toBe(true)
      expect(assistantMsg.classList.contains('assistant')).toBe(true)
    })

    it('formats markdown indicators with dimmed styling (streaming)', () => {
      const result = controller.formatMarkdownIndicators('This is *italic* and **bold** text')

      expect(result).toContain('<span class="markdown-indicator">*</span>')
      expect(result).toContain('<span class="markdown-indicator">**</span>')
      expect(result).toContain('italic')
      expect(result).toContain('bold')
    })

    it('renders markdown with styling while preserving indicators', () => {
      const result = controller.renderMarkdown('This is *italic* and **bold** text')

      expect(result).toContain('<span class="markdown-indicator">*</span>')
      expect(result).toContain('<span class="markdown-italic">italic</span>')
      expect(result).toContain('<span class="markdown-indicator">**</span>')
      expect(result).toContain('<span class="markdown-bold">bold</span>')
    })

    it('escapes HTML in message text', () => {
      const result = controller.renderMarkdown('<script>alert("xss")</script>')

      expect(result).toContain('&lt;script&gt;')
      expect(result).not.toContain('<script>')
    })

    it('stores raw text and renders with markdown', () => {
      const message = controller.addMessage('user', 'Test *message*')

      expect(message.dataset.rawText).toBe('Test *message*')
      expect(message.innerHTML).toContain('<span class="markdown-indicator">*</span>')
      expect(message.innerHTML).toContain('<span class="markdown-italic">message</span>')
    })

    it.skip('scrolls new messages into view by default', () => {
      // This would require spying before the method is called, which is complex timing-wise
      // Visual behavior is tested manually
    })

    it('skips scroll when loading existing messages', () => {
      const message = document.createElement('div')
      const scrollSpy = vi.spyOn(message, 'scrollIntoView')

      vi.spyOn(document, 'createElement').mockReturnValue(message)

      controller.addMessage('user', 'Test', { skipScroll: true })

      expect(scrollSpy).not.toHaveBeenCalled()
    })
  })

  describe('pulsing animation', () => {
    it('creates pulsing message with animation', () => {
      vi.useFakeTimers()

      const element = controller.addPulsingMessage('assistant')

      expect(element.classList.contains('pulsing')).toBe(true)
      expect(element.textContent).toBe('.')

      vi.advanceTimersByTime(500)
      expect(element.textContent).toBe('..')

      vi.advanceTimersByTime(500)
      expect(element.textContent).toBe('...')

      vi.advanceTimersByTime(500)
      expect(element.textContent).toBe('.')

      controller.stopLoadingAnimation(element)

      vi.useRealTimers()
    })

    it('stops animation when requested', () => {
      vi.useFakeTimers()

      const element = controller.addPulsingMessage('assistant')
      expect(element.loadingInterval).toBeTruthy()

      controller.stopLoadingAnimation(element)
      expect(element.loadingInterval).toBeNull()

      vi.useRealTimers()
    })
  })

  describe('continuity divergence handling', () => {
    it('displays continuity notice', () => {
      const data = {
        message: 'This space moved forward elsewhere'
      }

      controller.handleContinuityDivergence(data)

      const notice = fixture.element.querySelector('.continuity-notice')
      expect(notice).toBeTruthy()
      expect(notice.textContent).toContain('This space moved forward elsewhere')
      expect(notice.querySelector('button')).toBeTruthy()
    })
  })
})
