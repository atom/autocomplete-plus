{waitForAutocomplete} = require('./spec-helper')
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

  it 'should provide completions when a provider returns a promise that results in an array of suggestions', ->
    runs ->
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
      registration = atom.services.provide('autocomplete.provider', '1.0.0', {provider: testAsyncProvider})

      editor.moveToBottom()
      editor.insertText('o')

      waitForAutocomplete()

      runs ->
        suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
        expect(suggestionListView.querySelector('li .completion-label')).toHaveText('asyncProvided')
