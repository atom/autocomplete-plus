'use babel'
/* eslint-env jasmine */

import { waitForAutocomplete } from './spec-helper'

describe('Autocomplete Manager', function () {
  let [completionDelay, editorView, editor, mainModule, autocompleteManager] = []

  beforeEach(() =>
    runs(function () {
      // Set to live completion
      atom.config.set('autocomplete-plus.enableAutoActivation', true)
      atom.config.set('editor.fontSize', '16')

      // Set the completion delay
      completionDelay = 100
      atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
      completionDelay += 100 // Rendering

      let workspaceElement = atom.views.getView(atom.workspace)
      return jasmine.attachToDOM(workspaceElement)
    })
  )

  return describe('Undo a completion', function () {
    beforeEach(function () {
      runs(() => atom.config.set('autocomplete-plus.enableAutoActivation', true))

      waitsForPromise(() => atom.workspace.open('sample.js').then((e) => {
        editor = e
      }))

      waitsForPromise(() => atom.packages.activatePackage('language-javascript'))

      // Activate the package
      waitsForPromise(() => atom.packages.activatePackage('autocomplete-plus').then((a) => {
        mainModule = a.mainModule
      }))

      waitsFor(() => {
        if (!mainModule.autocompleteManager) {
          return false
        }
        return mainModule.autocompleteManager.ready
      })

      return runs(function () {
        ({ autocompleteManager } = mainModule)
        return advanceClock(autocompleteManager.providerManager.defaultProvider.deferBuildWordListInterval)
      })
    })

    return it('restores the previous state', function () {
      // Trigger an autocompletion
      editor.moveToBottom()
      editor.moveToBeginningOfLine()
      editor.insertText('f')

      waitForAutocomplete()

      return runs(function () {
        // Accept suggestion
        editorView = atom.views.getView(editor)
        atom.commands.dispatch(editorView, 'autocomplete-plus:confirm')

        expect(editor.getBuffer().getLastLine()).toEqual('function')

        editor.undo()

        return expect(editor.getBuffer().getLastLine()).toEqual('f')
      })
    })
  })
})
