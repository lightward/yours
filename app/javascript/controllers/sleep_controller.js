import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    integrating: Boolean,
    startingUniverseTime: String
  }

  async connect() {
    // Wait for LightwardAura to be available
    if (typeof LightwardAura === 'undefined') {
      console.log('Waiting for LightwardAura to load...')
      await new Promise((resolve) => {
        const checkInterval = setInterval(() => {
          if (typeof LightwardAura !== 'undefined') {
            clearInterval(checkInterval)
            resolve()
          }
        }, 100)
        // Timeout after 5 seconds
        setTimeout(() => {
          clearInterval(checkInterval)
          console.error('LightwardAura failed to load')
          window.location.href = '/'
        }, 5000)
      })
    }

    // Get canvas element
    const canvas = document.getElementById('sleep-aura-canvas')
    const statusText = document.querySelector('.sleep-status-text')
    const continueLink = document.querySelector('.sleep-continue-link')

    if (!canvas) {
      console.error('Canvas not found')
      window.location.href = '/'
      return
    }

    // Set canvas to full viewport
    canvas.width = window.innerWidth
    canvas.height = window.innerHeight

    // Initialize WebGL context
    const gl = canvas.getContext('webgl2', { preserveDrawingBuffer: true })
    if (!gl) {
      console.error('WebGL2 not supported')
      window.location.href = '/'
      return
    }

    // Initialize aura with cyan/magenta colors
    const aura = new LightwardAura(gl, {
      ...LightwardAura.defaultParams,
      width: canvas.width,
      height: canvas.height,
      colors: [
        [0, 229, 255],    // --accent cyan
        [255, 102, 255],  // --accent-active magenta
      ],
    })

    // Start the aura animation
    aura.start()

    // If integrating, do the full flow. Otherwise just let it run.
    if (!this.integratingValue) {
      // GET /sleep - contemplative mode, just let the aura run
      return
    }

    // POST /sleep - integration mode
    // Track start time for minimum display duration
    const startTime = Date.now()
    const minimumDisplayMs = 5000

    // Animate ellipsis
    const ellipsisElement = document.querySelector('.ellipsis')
    const ellipsisStates = ['', '.', '..', '...']
    let ellipsisIndex = 0
    const ellipsisInterval = setInterval(() => {
      if (ellipsisElement) {
        ellipsisElement.textContent = ellipsisStates[ellipsisIndex]
        ellipsisIndex = (ellipsisIndex + 1) % ellipsisStates.length
      }
    }, 500)

    // Poll universe_time until it changes
    try {
      await this.pollUntilUniverseTimeChanges()

      // Ensure minimum display time - wait remaining time if integration was quick
      const elapsedMs = Date.now() - startTime
      const remainingMs = Math.max(0, minimumDisplayMs - elapsedMs)
      await new Promise(resolve => setTimeout(resolve, remainingMs))

      // Stop ellipsis animation
      clearInterval(ellipsisInterval)

      // Fade out the aura
      canvas.classList.add('fade-out')

      // Wait for fade to complete
      await new Promise(resolve => setTimeout(resolve, 1000))

      // Pause and clean up aura
      aura.pause()
      aura.shutdown()

      // Hide status text and show Continue link
      if (statusText) {
        statusText.classList.add('hidden')
      }

      if (continueLink) {
        continueLink.classList.add('visible')
      }

    } catch (error) {
      console.error('Integration error:', error)
      // Clean up ellipsis interval
      clearInterval(ellipsisInterval)
      // On error, just go back to root
      window.location.href = '/'
    }
  }

  async pollUntilUniverseTimeChanges() {
    const startingTime = this.startingUniverseTimeValue

    return new Promise((resolve, reject) => {
      const pollInterval = setInterval(async () => {
        try {
          const response = await fetch('/', {
            method: 'HEAD',
          })

          const currentTime = response.headers.get('Yours-Universe-Time')

          if (currentTime && currentTime !== startingTime) {
            clearInterval(pollInterval)
            resolve()
          }
        } catch (error) {
          console.error('Poll error:', error)
          // Don't reject, just keep polling
        }
      }, 1000) // Poll every second

      // Timeout after 5 minutes
      setTimeout(() => {
        clearInterval(pollInterval)
        reject(new Error('Integration timeout'))
      }, 300000)
    })
  }
}
