'use babel'
/* eslint-env jasmine */

import { waitForAutocomplete } from './spec-helper'

describe('Autocomplete', function () {
  let [completionDelay, editorView, editor, autocompleteManager, mainModule] = []

  beforeEach(function () {
    runs(function () {
      // Set to live completion
      atom.config.set('autocomplete-plus.enableAutoActivation', true)
      atom.config.set('autocomplete-plus.fileBlacklist', ['.*', '*.md'])

      // Set the completion delay
      completionDelay = 100
      atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
      completionDelay += 100 // Rendering delay

      let workspaceElement = atom.views.getView(atom.workspace)
      return jasmine.attachToDOM(workspaceElement)
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
      runs(function () {
        expect(autocompleteManager).toBeDefined()
        return expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
      })

    )

  )

  return describe('@deactivate()', () =>
    it('removes all autocomplete views', () =>
      runs(function () {
        // Trigger an autocompletion
        editor.moveToBottom()
        editor.insertText('A')

        waitForAutocomplete()

        return runs(() => {
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

          // Deactivate the package
          atom.packages.deactivatePackage('autocomplete-plus')
          return expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
        })
      })
    )
  )
})
