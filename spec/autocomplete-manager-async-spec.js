'use babel'
/* eslint-env jasmine */

import { waitForAutocomplete } from './spec-helper'
describe('Async providers', () => {
  let [completionDelay, editorView, editor, mainModule, autocompleteManager, registration] = []

  beforeEach(() => {
    runs(() => {
      // Set to live completion
      atom.config.set('autocomplete-plus.enableAutoActivation', true)
      atom.config.set('editor.fontSize', '16')

      // Set the completion delay
      completionDelay = 100
      atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
      completionDelay += 100 // Rendering

      let workspaceElement = atom.views.getView(atom.workspace)
      jasmine.attachToDOM(workspaceElement)
    })

    waitsForPromise(() => atom.workspace.open('sample.js').then((e) => {
      editor = e
    }))

    waitsForPromise(() => atom.packages.activatePackage('language-javascript'))

    // Activate the package
    waitsForPromise(() => atom.packages.activatePackage('autocomplete-plus').then((a) => {
      mainModule = a.mainModule
    }))

    waitsFor(() => {
      autocompleteManager = mainModule.autocompleteManager
      return autocompleteManager
    })
  })

  afterEach(() => {
    if (registration) {
      registration.dispose()
    }
  })

  describe('when an async provider is registered', () => {
    beforeEach(() => {
      let testAsyncProvider = {
        getSuggestions (options) {
          return new Promise((resolve) => {
            setTimeout(() => {
              resolve(
                [{
                  text: 'asyncProvided',
                  replacementPrefix: 'asyncProvided',
                  rightLabel: 'asyncProvided'
                }]
              )
            }, 10)
          })
        },
        scopeSelector: '.source.js'
      }
      registration = atom.packages.serviceHub.provide('autocomplete.provider', '2.0.0', testAsyncProvider)
    })

    it('should provide completions when a provider returns a promise that results in an array of suggestions', () => {
      editor.moveToBottom()
      editor.insertText('o')

      waitForAutocomplete()

      runs(() => {
        let suggestionListView = autocompleteManager.suggestionList.suggestionListElement
        expect(suggestionListView.element.querySelector('li .right-label')).toHaveText('asyncProvided')
      })
    })
  })

  describe('when a provider takes a long time to provide suggestions', () => {
    beforeEach(() => {
      let testAsyncProvider = {
        scopeSelector: '.source.js',
        getSuggestions (options) {
          return new Promise(resolve => {
            setTimeout(() =>
              resolve(
                [{
                  text: 'asyncProvided',
                  replacementPrefix: 'asyncProvided',
                  rightLabel: 'asyncProvided'
                }]
              )
            , 1000)
          })
        }
      }
      registration = atom.packages.serviceHub.provide('autocomplete.provider', '2.0.0', testAsyncProvider)
    })

    it('does not show the suggestion list when it is triggered then no longer needed', () => {
      runs(() => {
        editorView = atom.views.getView(editor)

        editor.moveToBottom()
        editor.insertText('o')

        // Waiting will kick off the suggestion request
        advanceClock(autocompleteManager.suggestionDelay * 2)
      })

      waits(0)

      runs(() => {
        // Waiting will kick off the suggestion request
        editor.insertText('\r')
        waitForAutocomplete()

        // Expect nothing because the provider has not come back yet
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        // Wait til the longass provider comes back
        advanceClock(1000)
      })

      waits(0)

      runs(() => expect(editorView.querySelector('.autocomplete-plus')).not.toExist())
    })
  })
})
