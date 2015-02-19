{waitForAutocomplete} = require('./spec-helper')
describe 'Async providers', ->
  [completionDelay, editorView, editor, mainModule, autocompleteManager, registration] = []

  beforeEach ->
    runs ->
      jasmine.unspy(window, 'setTimeout')
      jasmine.unspy(window, 'clearTimeout')

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

    waitsFor ->
      mainModule.autocompleteManager.providerManager?

    runs ->
      autocompleteManager = mainModule.autocompleteManager
      spyOn(autocompleteManager, 'displaySuggestions').andCallThrough()
      spyOn(autocompleteManager, 'hideSuggestionList').andCallThrough()
      spyOn(autocompleteManager, 'getSuggestionsFromProviders').andCallThrough()

  afterEach ->
    registration?.dispose()
    jasmine.unspy(autocompleteManager, 'displaySuggestions')
    jasmine.unspy(autocompleteManager, 'hideSuggestionList')
    jasmine.unspy(autocompleteManager, 'getSuggestionsFromProviders')

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
      runs ->
        editor.moveToBottom()
        editor.insertText('o')

      waitsFor ->
        autocompleteManager.displaySuggestions.calls.length is 1

      runs ->
        suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
        expect(suggestionListView.querySelector('li .completion-label')).toHaveText('asyncProvided')

  describe 'when a provider takes a long time to provide suggestions', ->
    [done] = []

    beforeEach ->
      done = false
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
            done = true
            )
      registration = atom.packages.serviceHub.provide('autocomplete.provider', '1.0.0', {provider: testAsyncProvider})

    it 'does not show the suggestion list when it is triggered then no longer needed', ->
      runs ->
        editorView = atom.views.getView(editor)
        editor.moveToBottom()

      waitsFor ->
        autocompleteManager.hideSuggestionList.calls.length is 1

      runs ->
        editor.insertText('o')

        # Waiting will kick off the suggestion request
        advanceClock(autocompleteManager.suggestionDelay * 2)

      waitsFor ->
        autocompleteManager.getSuggestionsFromProviders.calls.length is 1

      runs ->
        editor.insertText(' ')

      waitsFor ->
        autocompleteManager.hideSuggestionList.calls.length is 2

      runs ->
        # Expect nothing because the provider has not come back yet
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        # Wait til the longass provider comes back
        advanceClock(1000)

      waitsFor ->
        done is true

      runs ->
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
