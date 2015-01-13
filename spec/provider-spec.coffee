TestProvider = require('./lib/test-provider')
{ServiceHub}  = require 'atom'

describe "Provider API", ->
  [completionDelay, editor, autocompleteManager, consumer] = []

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

    # Activate the package
    waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
      autocompleteManager = a.mainModule.autocompleteManager

  afterEach ->
    consumer?.dispose()

  describe "When the Editor has a grammar", ->
    beforeEach ->
      waitsForPromise -> atom.packages.activatePackage('language-javascript')

    it "should allow registration of a provider using v1.0.0 of the API", ->
      runs ->
        # Register the test provider
        consumer = atom.services.consume "autocomplete.provider-api", "1.0.0", (a) ->
          testProvider = new TestProvider(editor)
          a.registerProviderForEditor(testProvider, editor)

        editor.moveToBottom()
        editor.insertText('o')

        advanceClock(completionDelay)

        suggestionListView = atom.views.getView(autocompleteManager.suggestionList)

        expect(suggestionListView.querySelector('li .label')).toHaveHtml('<span style="color: red">ohai</span>')
        expect(suggestionListView.querySelector('li')).toHaveClass('ohai')

    it "should allow registration of a provider via a grammar using v2.0.0 of the API", ->
      runs ->
        # Register the test provider
        consumer = atom.services.consume "autocomplete.provider-api", "2.0.0", (a) ->
          testProvider = new TestProvider(editor)
          a.registerProviderForGrammars(testProvider, [editor.getGrammar()])

        editor.moveToBottom()
        editor.insertText('o')

        advanceClock(completionDelay)

        suggestionListView = atom.views.getView(autocompleteManager.suggestionList)

        expect(suggestionListView.querySelector('li .label')).toHaveHtml('<span style="color: red">ohai</span>')
        expect(suggestionListView.querySelector('li')).toHaveClass('ohai')

    it "should allow registration of a provider via a scope using v2.0.0 of the API", ->
      runs ->
        # Register the test provider
        consumer = atom.services.consume "autocomplete.provider-api", "2.0.0", (a) ->
          testProvider = new TestProvider(editor)
          a.registerProviderForScopes(testProvider, ['source.js'])

        editor.moveToBottom()
        editor.insertText('o')

        advanceClock(completionDelay)

        suggestionListView = atom.views.getView(autocompleteManager.suggestionList)

        expect(suggestionListView.querySelector('li .label')).toHaveHtml('<span style="color: red">ohai</span>')
        expect(suggestionListView.querySelector('li')).toHaveClass('ohai')

    it "should not allow registration of a provider via a scope supplied as a grammar using v2.0.0 of the API", ->
      runs ->
        # Register the test provider
        consumer = atom.services.consume "autocomplete.provider-api", "2.0.0", (a) ->
          testProvider = new TestProvider(editor)
          a.registerProviderForGrammars(testProvider, ['source.js'])

        expect(autocompleteManager.scopes).toEqual({})

  describe "When the Editor has no grammar", ->
    it "should not allow registration of a provider using v1.0.0 of the API", ->
      runs ->
        # Register the test provider
        consumer = atom.services.consume "autocomplete.provider-api", "1.0.0", (a) ->
          testProvider = new TestProvider(editor)
          a.registerProviderForEditor(testProvider, editor)

        expect(autocompleteManager.scopes['text.plain.null-grammar']).toBeUndefined()
