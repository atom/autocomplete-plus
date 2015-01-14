TestProvider = require('./lib/test-provider')
{ServiceHub}  = require 'atom'
_ = require 'underscore-plus'

describe "Provider API", ->
  [completionDelay, editor, mainModule, autocompleteManager, consumer] = []

  beforeEach ->
    runs ->
      consumer = null
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
      mainModule = a.mainModule
      autocompleteManager = mainModule.autocompleteManager

  afterEach ->
    consumer?.dispose()

  describe "When the Editor has a grammar", ->
    [testProvider, registration, autocomplete] = []

    beforeEach ->
      runs ->
          testProvider = null
          registration = null
          autocomplete = null

      waitsForPromise -> atom.packages.activatePackage('language-javascript')

    afterEach ->
      runs ->
        consumer?.dispose()
        registration?.dispose()

    describe "Legacy Provider API", ->
      describe "registerProviderForEditor", ->
        it "registers the given provider for the given editor", ->
          runs ->
            testProvider = new TestProvider(editor)
            mainModule.registerProviderForEditor(testProvider, editor)
            expect(autocompleteManager.providerManager.scopes['source.js'][0]).toBe(testProvider)

      describe "registerMultipleIdenticalProvidersForEditor", ->
        it "registers the given provider once when called multiple times for the given editor", ->
          runs ->
            testProvider = new TestProvider(editor)
            expect(autocompleteManager.providerManager.scopes['source.js']).toBeUndefined()

            mainModule.registerProviderForEditor(testProvider, editor)
            expect(autocompleteManager.providerManager.scopes['source.js'][0]).toBe(testProvider)
            expect(_.size(autocompleteManager.providerManager.scopes['source.js'])).toBe(1)

            mainModule.registerProviderForEditor(testProvider, editor)
            expect(autocompleteManager.providerManager.scopes['source.js'][0]).toBe(testProvider)
            expect(_.size(autocompleteManager.providerManager.scopes['source.js'])).toBe(1)

            mainModule.registerProviderForEditor(testProvider, editor)
            expect(autocompleteManager.providerManager.scopes['source.js'][0]).toBe(testProvider)
            expect(_.size(autocompleteManager.providerManager.scopes['source.js'])).toBe(1)

      describe "unregisterProviderFromEditor", ->
        it "unregisters the provider from all editors", ->
          runs ->
            testProvider = new TestProvider(editor)
            mainModule.registerProviderForEditor(testProvider, editor)

            expect(autocompleteManager.providerManager.scopes['source.js'][0]).toBe(testProvider)

            mainModule.unregisterProvider(testProvider)
            expect(autocompleteManager.providerManager.scopes).toEqual({})

      describe "a registered provider", ->
        it "calls buildSuggestions()", ->
          runs ->
            testProvider = new TestProvider(editor)
            mainModule.registerProviderForEditor(testProvider, editor)

            spyOn(testProvider, "buildSuggestions").andCallThrough()

            # Trigger an autocompletion
            editor.moveToBottom()
            editor.moveToBeginningOfLine()
            editor.insertText('f')
            advanceClock completionDelay

            expect(testProvider.buildSuggestions).toHaveBeenCalled()

        it "calls confirm()", ->
          runs ->
            testProvider = new TestProvider(editor)
            mainModule.registerProviderForEditor(testProvider, editor)

            spyOn(testProvider, 'confirm').andCallThrough()

            # Trigger an autocompletion
            editor.moveToBottom()
            editor.moveToBeginningOfLine()
            editor.insertText('f')
            advanceClock(completionDelay)

            suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
            atom.commands.dispatch(suggestionListView, 'autocomplete-plus:confirm')

            expect(testProvider.confirm).toHaveBeenCalled()

    describe "Provider API v1.0.0", ->

      it "exports Provider and Suggestion", ->
        runs ->
          # Register the test provider
          consumer = atom.services.consume "autocomplete.provider-api", "1.0.0", (a) ->
            autocomplete = a
            testProvider = new TestProvider(editor)
            registration = a.registerProviderForEditor(testProvider, editor)

          expect(autocomplete.Provider).toBeDefined()
          expect(autocomplete.Suggestion).toBeDefined()

      it "should allow registration of a provider", ->
        runs ->
          # Register the test provider
          consumer = atom.services.consume "autocomplete.provider-api", "1.0.0", (a) ->
            autocomplete = a
            testProvider = new TestProvider(editor)
            a.registerProviderForEditor(testProvider, editor)

          editor.moveToBottom()
          editor.insertText('o')

          advanceClock(completionDelay)

          suggestionListView = atom.views.getView(autocompleteManager.suggestionList)

          expect(suggestionListView.querySelector('li .label')).toHaveHtml('<span style="color: red">ohai</span>')
          expect(suggestionListView.querySelector('li')).toHaveClass('ohai')

      it "should unregister a provider correctly", ->
        runs ->
          # Register the test provider
          consumer = atom.services.consume "autocomplete.provider-api", "1.0.0", (a) ->
            autocomplete = a
            testProvider = new TestProvider(editor)
            registration = a.registerProviderForEditor(testProvider, editor)

          expect(autocompleteManager.providerManager.scopes).not.toEqual({})
          expect(_.size(autocompleteManager.providerManager.scopes['source.js'])).toEqual(1)
          expect(autocompleteManager.providerManager.scopes['source.js'][0]).toEqual(testProvider)

          editor.moveToBottom()
          editor.insertText('o')

          advanceClock(completionDelay)

          suggestionListView = atom.views.getView(autocompleteManager.suggestionList)

          expect(suggestionListView.querySelector('li .label')).toHaveHtml('<span style="color: red">ohai</span>')
          expect(suggestionListView.querySelector('li')).toHaveClass('ohai')

          autocomplete.unregisterProvider(testProvider)
          expect(autocompleteManager.providerManager.scopes).toEqual({})

    describe "Provider API v2.0.0", ->
      [testProvider, autocomplete, registration] = []

      it "does not export Provider and Suggestion", ->
        runs ->
          # Register the test provider
          consumer = atom.services.consume "autocomplete.provider-api", "2.0.0", (a) ->
            autocomplete = a
            testProvider = new TestProvider(editor)
            registration = a.registerProviderForGrammars(testProvider, [editor.getGrammar()])

          expect(autocomplete.Provider).toBeUndefined()
          expect(autocomplete.Suggestion).toBeUndefined()

      it "should allow registration of a provider via a grammar", ->
        runs ->
          # Register the test provider
          consumer = atom.services.consume "autocomplete.provider-api", "2.0.0", (a) ->
            autocomplete = a
            testProvider = new TestProvider(editor)
            registration = a.registerProviderForGrammars(testProvider, [editor.getGrammar()])

          expect(autocompleteManager.providerManager.scopes).not.toEqual({})
          expect(_.size(autocompleteManager.providerManager.scopes['source.js'])).toEqual(1)
          expect(autocompleteManager.providerManager.scopes['source.js'][0]).toEqual(testProvider)

          editor.moveToBottom()
          editor.insertText('o')

          advanceClock(completionDelay)

          suggestionListView = atom.views.getView(autocompleteManager.suggestionList)

          expect(suggestionListView.querySelector('li .label')).toHaveHtml('<span style="color: red">ohai</span>')
          expect(suggestionListView.querySelector('li')).toHaveClass('ohai')

      it "should allow registration of a provider via a scope", ->
        runs ->
          # Register the test provider
          consumer = atom.services.consume "autocomplete.provider-api", "2.0.0", (a) ->
            autocomplete = a
            testProvider = new TestProvider(editor)
            registration = a.registerProviderForScopes(testProvider, ['source.js'])

          expect(autocompleteManager.providerManager.scopes).not.toEqual({})
          expect(_.size(autocompleteManager.providerManager.scopes['source.js'])).toEqual(1)
          expect(autocompleteManager.providerManager.scopes['source.js'][0]).toEqual(testProvider)

          editor.moveToBottom()
          editor.insertText('o')

          advanceClock(completionDelay)

          suggestionListView = atom.views.getView(autocompleteManager.suggestionList)

          expect(suggestionListView.querySelector('li .label')).toHaveHtml('<span style="color: red">ohai</span>')
          expect(suggestionListView.querySelector('li')).toHaveClass('ohai')

      it "should not allow registration of a provider via a scope supplied as a grammar", ->
        runs ->
          # Register the test provider
          consumer = atom.services.consume "autocomplete.provider-api", "2.0.0", (a) ->
            autocomplete = a
            testProvider = new TestProvider(editor)
            registration = a.registerProviderForGrammars(testProvider, ['source.js'])

          expect(autocompleteManager.providerManager.scopes).toEqual({})

      it "should dispose a provider registration correctly", ->

        runs ->
          expect(autocompleteManager.providerManager.scopes).toEqual({})

          # Register the test provider
          consumer = atom.services.consume "autocomplete.provider-api", "2.0.0", (a) ->
            autocomplete = a
            testProvider = new TestProvider(editor)
            registration = a.registerProviderForScopes(testProvider, ['source.js'])

          expect(autocompleteManager.providerManager.scopes).not.toEqual({})
          expect(_.size(autocompleteManager.providerManager.scopes['source.js'])).toEqual(1)
          expect(autocompleteManager.providerManager.scopes['source.js'][0]).toEqual(testProvider)

          registration.dispose()
          expect(autocompleteManager.providerManager.scopes).toEqual({})

      it "should unregister a provider correctly", ->

        runs ->
          expect(autocompleteManager.providerManager.scopes).toEqual({})

          # Register the test provider
          consumer = atom.services.consume "autocomplete.provider-api", "2.0.0", (a) ->
            autocomplete = a
            testProvider = new TestProvider(editor)
            registration = autocomplete.registerProviderForScopes(testProvider, ['source.js'])

          expect(autocompleteManager.providerManager.scopes).not.toEqual({})
          expect(_.size(autocompleteManager.providerManager.scopes['source.js'])).toEqual(1)
          expect(autocompleteManager.providerManager.scopes['source.js'][0]).toEqual(testProvider)

          autocomplete.unregisterProviderForScopes(testProvider, ['source.js'])
          expect(autocompleteManager.providerManager.scopes).toEqual({})

  describe "When the Editor has no grammar", ->
    it "should not allow registration of a provider using v1.0.0 of the API", ->
      runs ->
        # Register the test provider
        consumer = atom.services.consume "autocomplete.provider-api", "1.0.0", (a) ->
          testProvider = new TestProvider(editor)
          a.registerProviderForEditor(testProvider, editor)

        expect(autocompleteManager.providerManager.scopes['text.plain.null-grammar']).toBeUndefined()
