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
