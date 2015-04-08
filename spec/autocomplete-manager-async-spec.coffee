{waitForAutocomplete} = require './spec-helper'
describe 'Async providers', ->
  [completionDelay, editorView, editor, mainModule, autocompleteManager, registration] = []

  beforeEach ->
    runs ->
      # Set to live completion
      atom.config.set('autocomplete-plus.enableAutoActivation', true)
      atom.config.set('editor.fontSize', '16')

      # Set the completion delay
      completionDelay = 100
      atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
      completionDelay += 100 # Rendering

      workspaceElement = atom.views.getView(atom.workspace)
      jasmine.attachToDOM(workspaceElement)

    waitsForPromise -> atom.workspace.open('sample.js').then (e) ->
      editor = e

    waitsForPromise ->
      atom.packages.activatePackage('language-javascript')

    # Activate the package
    waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
      mainModule = a.mainModule

    waitsFor ->
      mainModule.autocompleteManager?.ready

    runs ->
      autocompleteManager = mainModule.autocompleteManager

  afterEach ->
    registration?.dispose()

  describe 'when an async provider is registered', ->
    beforeEach ->
      testAsyncProvider =
        getSuggestions: (options) ->
          return new Promise((resolve) ->
            setTimeout ->
              resolve(
                [{
                  text: 'asyncProvided',
                  replacementPrefix: 'asyncProvided',
                  rightLabel: 'asyncProvided'
                }]
              )
            , 10
            )
        selector: '.source.js'
      registration = atom.packages.serviceHub.provide('autocomplete.provider', '2.0.0', testAsyncProvider)

    it 'should provide completions when a provider returns a promise that results in an array of suggestions', ->
      editor.moveToBottom()
      editor.insertText('o')

      waitForAutocomplete()

      runs ->
        suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
        expect(suggestionListView.querySelector('li .right-label')).toHaveText('asyncProvided')

  describe 'when a provider takes a long time to provide suggestions', ->
    [testAsyncProvider] = []

    beforeEach ->
      testAsyncProvider =
        selector: '.source.js'
        signal: null
        getSuggestions: (options) ->
          return new Promise((resolve) =>
            @signal = =>
              @signal = null
              resolve(
                [{
                  text: 'sort',
                  rightLabel: 'asyncProvided'
                }]
              )
            )
      registration = atom.packages.serviceHub.provide('autocomplete.provider', '2.0.0', testAsyncProvider)

    it 'has the most up-to-date prefix when it completes', ->
      runs ->
        editor.moveToBottom()
        editor.insertText('s')
        # Waiting will kick off the suggestion request
        advanceClock(autocompleteManager.suggestionDelay * 2)

      waits(0)

      runs ->
        editor.moveToBottom()
        # The provider has not returned at this point, cause the race condition.
        editor.insertText('o')

      waits(0)

      runs ->
        expect(testAsyncProvider.signal).not.toBeNull()
        testAsyncProvider.signal()

      waits(0)

      runs ->
        suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
        console.log suggestionListView
        expect(suggestionListView.querySelectorAll('li .character-match').length).toBe(2)

    it 'does not show the suggestion list when it is triggered then no longer needed', ->
      runs ->
        editorView = atom.views.getView(editor)

        editor.moveToBottom()
        editor.insertText('o')

        # Waiting will kick off the suggestion request
        advanceClock(autocompleteManager.suggestionDelay * 2)

      waits(0)

      runs ->
        # Waiting will kick off the suggestion request
        editor.insertText('\r')
        waitForAutocomplete()

        # Expect nothing because the provider has not come back yet
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        # Wait til the longass provider comes back
        expect(testAsyncProvider.signal).not.toBeNull()
        testAsyncProvider.signal()

      waits(0)

      runs ->
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
