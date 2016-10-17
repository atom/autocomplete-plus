'use babel'
/* eslint-env jasmine */

import { waitForAutocomplete } from './spec-helper'

describe('Autocomplete', () => {
  let [completionDelay, editorView, editor, autocompleteManager, mainModule] = []

  beforeEach(() => {
    runs(() => {
      // Set to live completion
      atom.config.set('autocomplete-plus.enableAutoActivation', true)
      atom.config.set('autocomplete-plus.fileBlacklist', ['.*', '*.md'])

      // Set the completion delay
      completionDelay = 100
      atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
      completionDelay += 100 // Rendering delay

      let workspaceElement = atom.views.getView(atom.workspace)
      jasmine.attachToDOM(workspaceElement)
    })

    waitsForPromise(() => {
      return atom.workspace.open('sample.js').then((e) => {
        editor = e
      })
    })

    waitsForPromise(() => { return atom.packages.activatePackage('language-javascript') })

    // Activate the package
    waitsForPromise(() => {
      return atom.packages.activatePackage('autocomplete-plus').then((a) => {
        mainModule = a.mainModule
      })
    })

    waitsFor(() => {
      if (!mainModule.autocompleteManager) {
        return false
      }
      return mainModule.autocompleteManager.ready
    })

    runs(() => {
      autocompleteManager = mainModule.autocompleteManager
    })

    return runs(() => {
      editorView = atom.views.getView(editor)
      return advanceClock(mainModule.autocompleteManager.providerManager.defaultProvider.deferBuildWordListInterval)
    })
  })

  describe('@activate()', () =>
    it('activates autocomplete and initializes AutocompleteManager', () =>
      runs(() => {
        expect(autocompleteManager).toBeDefined()
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
      })
    )
  )

  describe('@deactivate()', () =>
    it('removes all autocomplete views', () =>
      runs(() => {
        // Trigger an autocompletion
        editor.moveToBottom()
        editor.insertText('A')

        waitForAutocomplete()

        runs(() => {
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

          // Deactivate the package
          atom.packages.deactivatePackage('autocomplete-plus')
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
        })
      })
    )
  )
})
