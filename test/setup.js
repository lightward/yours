import { Application } from '@hotwired/stimulus'

// Set up a global Stimulus application for tests
globalThis.createStimulusApplication = () => {
  return Application.start()
}

// Mock localStorage if not available
if (typeof globalThis.localStorage === 'undefined') {
  let store = {}
  globalThis.localStorage = {
    getItem: (key) => store[key] || null,
    setItem: (key, value) => { store[key] = value.toString() },
    removeItem: (key) => { delete store[key] },
    clear: () => { store = {} }
  }
}

// Mock window.scrollBy if not available (happy-dom doesn't implement it)
if (typeof globalThis.window !== 'undefined' && typeof globalThis.window.scrollBy === 'undefined') {
  globalThis.window.scrollBy = () => {}
}

// Mock markdown-it for tests (in browser it's loaded via script tag)
if (typeof globalThis.window !== 'undefined') {
  globalThis.window.markdownit = (options) => {
    return {
      renderer: {
        rules: {}
      },
      render: (text) => {
        // Simple mock that preserves text and applies basic transformations
        // to match what our custom renderers do
        let result = text
          // Escape HTML
          .replace(/&/g, "&amp;")
          .replace(/</g, "&lt;")
          .replace(/>/g, "&gt;")

        // Use placeholders to avoid regex conflicts
        result = result
          .replace(/\*\*(\S(?:.*?\S)?)\*\*/g, '〔B2〕$1〔/B2〕')
          .replace(/__(\S(?:.*?\S)?)__/g, '〔BU〕$1〔/BU〕')
          .replace(/\*(\S(?:.*?\S)?)\*/g, '〔I1〕$1〔/I1〕')
          .replace(/_(\S(?:.*?\S)?)_/g, '〔IU〕$1〔/IU〕')

        // Replace placeholders with HTML
        result = result
          .replace(/〔B2〕/g, '<span class="markdown-indicator">**</span><span class="markdown-bold">')
          .replace(/〔\/B2〕/g, '</span><span class="markdown-indicator">**</span>')
          .replace(/〔BU〕/g, '<span class="markdown-indicator">__</span><span class="markdown-bold">')
          .replace(/〔\/BU〕/g, '</span><span class="markdown-indicator">__</span>')
          .replace(/〔I1〕/g, '<span class="markdown-indicator">*</span><span class="markdown-italic">')
          .replace(/〔\/I1〕/g, '</span><span class="markdown-indicator">*</span>')
          .replace(/〔IU〕/g, '<span class="markdown-indicator">_</span><span class="markdown-italic">')
          .replace(/〔\/IU〕/g, '</span><span class="markdown-indicator">_</span>')

        return result.trimEnd()
      }
    }
  }
}

// Mock fetch for tests that need it
globalThis.fetchMock = {
  reset: () => {
    globalThis.fetch = fetchMock.originalFetch
  },
  mockResponse: (response) => {
    globalThis.fetch = vi.fn().mockResolvedValue(response)
  },
  mockResponseOnce: (response) => {
    globalThis.fetch = vi.fn().mockResolvedValueOnce(response)
  }
}
globalThis.fetchMock.originalFetch = globalThis.fetch

// Helper to create a test fixture with a controller
globalThis.createControllerFixture = (html, controllerClass, identifier) => {
  document.body.innerHTML = html
  const application = createStimulusApplication()
  application.register(identifier, controllerClass)

  const element = document.querySelector(`[data-controller="${identifier}"]`)

  // Wait for Stimulus to connect the controller
  return new Promise((resolve) => {
    setTimeout(() => {
      const controller = application.controllers.find(
        c => c.context.identifier === identifier && c.element === element
      )
      resolve({ application, element, controller })
    }, 0)
  })
}
