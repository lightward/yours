import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import DraftsController from '../../app/javascript/controllers/drafts_controller.js'

describe('DraftsController', () => {
  let fixture

  beforeEach(async () => {
    localStorage.clear()

    const html = `
      <form data-controller="drafts" data-action="turbo:submit-start->drafts#clearAll">
        <button type="submit">Start over</button>
      </form>
    `

    fixture = await createControllerFixture(html, DraftsController, 'drafts')
  })

  afterEach(() => {
    fixture.application.stop()
    document.body.innerHTML = ''
    localStorage.clear()
  })

  describe('clearAll', () => {
    it('removes every locally-held draft: no trace of what was', () => {
      localStorage.setItem('yours-input-1:0', 'a draft from a previous life')
      localStorage.setItem('yours-input-42:13', 'another stranded draft')
      localStorage.setItem('yours-input-current', 'an unkeyed draft')

      fixture.controller.clearAll()

      expect(localStorage.getItem('yours-input-1:0')).toBeNull()
      expect(localStorage.getItem('yours-input-42:13')).toBeNull()
      expect(localStorage.getItem('yours-input-current')).toBeNull()
    })

    it('leaves non-draft keys alone', () => {
      localStorage.setItem('yours-theme', 'light')
      localStorage.setItem('yours-input-1:0', 'a draft')

      fixture.controller.clearAll()

      expect(localStorage.getItem('yours-theme')).toBe('light')
      expect(localStorage.getItem('yours-input-1:0')).toBeNull()
    })

    // The turbo:submit-start wiring (fires after the confirm, not before) is
    // pinned server-side in spec/requests/application_controller_spec.rb -
    // this test environment doesn't deliver dispatched DOM events to
    // Stimulus bindings, so controller methods are exercised directly here,
    // as throughout this suite
  })
})
