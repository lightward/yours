import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import ThemeController from '../../app/javascript/controllers/theme_controller.js'

describe('ThemeController', () => {
  let fixture
  let controller

  beforeEach(async () => {
    const html = `
      <div data-controller="theme">
        <button data-theme-target="option" data-action="click->theme#select" data-theme-value-param="dark">Dark</button>
        <button data-theme-target="option" data-action="click->theme#select" data-theme-value-param="light">Light</button>
        <button data-theme-target="option" data-action="click->theme#select" data-theme-value-param="auto">Auto</button>
      </div>
    `

    const result = await createControllerFixture(html, ThemeController, 'theme')
    fixture = result
    controller = result.controller

    localStorage.clear()
  })

  afterEach(() => {
    fixture.application.stop()
    document.body.innerHTML = ''
    localStorage.clear()
    document.documentElement.removeAttribute('data-theme')
  })

  describe('initialization', () => {
    it('defaults to dark theme', () => {
      expect(controller.currentValue).toBe('dark')
      expect(document.documentElement.getAttribute('data-theme')).toBe('dark')
    })

    it('loads saved theme from localStorage', async () => {
      localStorage.setItem('yours-theme', 'light')

      const html = `
        <div data-controller="theme">
          <button data-theme-target="option" data-theme-value-param="dark">Dark</button>
          <button data-theme-target="option" data-theme-value-param="light">Light</button>
          <button data-theme-target="option" data-theme-value-param="auto">Auto</button>
        </div>
      `
      const newFixture = await createControllerFixture(html, ThemeController, 'theme')

      expect(newFixture.controller.currentValue).toBe('light')
      expect(document.documentElement.getAttribute('data-theme')).toBe('light')

      newFixture.application.stop()
    })

    it('highlights the selected button on connect', () => {
      const darkBtn = controller.optionTargets[0]
      const lightBtn = controller.optionTargets[1]
      const autoBtn = controller.optionTargets[2]

      expect(darkBtn.classList.contains('secondary')).toBe(false)
      expect(lightBtn.classList.contains('secondary')).toBe(true)
      expect(autoBtn.classList.contains('secondary')).toBe(true)
    })
  })

  describe('selection', () => {
    it('selects light theme', () => {
      const event = { params: { value: 'light' } }
      controller.select(event)

      expect(controller.currentValue).toBe('light')
      expect(document.documentElement.getAttribute('data-theme')).toBe('light')
    })

    it('selects auto theme', () => {
      const event = { params: { value: 'auto' } }
      controller.select(event)

      expect(controller.currentValue).toBe('auto')
      expect(document.documentElement.getAttribute('data-theme')).toBe('auto')
    })

    it('saves preference to localStorage', () => {
      const event = { params: { value: 'light' } }
      controller.select(event)

      expect(localStorage.getItem('yours-theme')).toBe('light')
    })

    it('updates button styling on selection', () => {
      const darkBtn = controller.optionTargets[0]
      const lightBtn = controller.optionTargets[1]

      const event = { params: { value: 'light' } }
      controller.select(event)

      expect(darkBtn.classList.contains('secondary')).toBe(true)
      expect(lightBtn.classList.contains('secondary')).toBe(false)
    })
  })

  describe('theme application', () => {
    it('sets data-theme attribute on document element', () => {
      controller.currentValue = 'light'
      controller.applyTheme()

      expect(document.documentElement.getAttribute('data-theme')).toBe('light')
    })
  })
})
