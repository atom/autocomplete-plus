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
        requestHandler: (options) ->
          return new Promise((resolve) ->
            setTimeout ->
              resolve(
                [{
                  word: 'asyncProvided',
                  prefix: 'asyncProvided',
                  label: 'asyncProvided'
                }]
              )
            , 10
            )
        selector: '.source.js'
      registration = atom.packages.serviceHub.provide('autocomplete.provider', '1.0.0', {provider: testAsyncProvider})

    it 'should provide completions when a provider returns a promise that results in an array of suggestions', ->
      editor.moveToBottom()
      editor.insertText('o')

      waitForAutocomplete()

      runs ->
        suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
        expect(suggestionListView.querySelector('li .completion-label')).toHaveText('asyncProvided')

  describe 'when a provider takes a long time to provide suggestions', ->
    beforeEach ->
      testAsyncProvider =
        selector: '.source.js'
        requestHandler: (options) ->
          return new Promise((resolve) ->
            setTimeout ->
              resolve(
                [{
                  word: 'asyncProvided',
                  prefix: 'asyncProvided',
                  label: 'asyncProvided'
                }]
              )
            , 1000
            )
      registration = atom.packages.serviceHub.provide('autocomplete.provider', '1.0.0', {provider: testAsyncProvider})

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
        editor.insertText(' ')
        waitForAutocomplete()

        # Expect nothing because the provider has not come back yet
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        # Wait til the longass provider comes back
        advanceClock(1000)

      waits(0)

      runs ->
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
