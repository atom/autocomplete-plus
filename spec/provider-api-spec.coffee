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
      it "registers the given provider for the given editor", ->
        runs ->
          expect(autocompleteManager.providerManager.store).toBeDefined()
          testProvider = new TestProvider(editor)
          mainModule.registerProviderForEditor(testProvider, editor)

          expect(_.size(autocompleteManager.providerManager.store.propertySets)).toEqual(2)
          expect(autocompleteManager.providerManager.store.propertySets[0].properties.provider).toEqual(testProvider)
          expect(autocompleteManager.providerManager.store.propertySets[0].selector.selector[0].classList[0]).toEqual('js')
          expect(autocompleteManager.providerManager.store.propertySets[0].selector.selector[0].classList[1]).toEqual('source')
          expect(autocompleteManager.providerManager.store.propertySets[1].properties.provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)

      it "registers the given provider once when called multiple times for the given editor", ->
        runs ->
          expect(autocompleteManager.providerManager.store).toBeDefined()
          testProvider = new TestProvider(editor)
          expect(_.size(autocompleteManager.providerManager.store.propertiesForSource('autocomplete-provider-registration'))).toEqual(1)
          expect(autocompleteManager.providerManager.store.propertiesForSource('autocomplete-provider-registration')['*'].provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          mainModule.registerProviderForEditor(testProvider, editor)
          expect(_.size(autocompleteManager.providerManager.store.propertiesForSource('autocomplete-provider-registration'))).toEqual(2)
          expect(autocompleteManager.providerManager.store.propertiesForSource('autocomplete-provider-registration')['*'].provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.store.propertiesForSource('autocomplete-provider-registration')['.js.source'].provider).toEqual(testProvider)

          mainModule.registerProviderForEditor(testProvider, editor)
          expect(_.size(autocompleteManager.providerManager.store.propertiesForSource('autocomplete-provider-registration'))).toEqual(2)
          expect(autocompleteManager.providerManager.store.propertiesForSource('autocomplete-provider-registration')['*'].provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          console.log _.deepClone autocompleteManager.providerManager.store.propertiesForSource('autocomplete-provider-registration')['.js.source'].provider
          console.log _.deepClone testProvider
          expect(autocompleteManager.providerManager.store.propertiesForSource('autocomplete-provider-registration')['.js.source'].provider).toEqual(testProvider)

          mainModule.registerProviderForEditor(testProvider, editor)
          expect(_.size(autocompleteManager.providerManager.store.propertiesForSource('autocomplete-provider-registration'))).toEqual(2)
          expect(autocompleteManager.providerManager.store.propertiesForSource('autocomplete-provider-registration')['*'].provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.store.propertiesForSource('autocomplete-provider-registration')['.js.source'].provider).toEqual(testProvider)

      it "unregisters the provider from all editors", ->
        runs ->
          expect(autocompleteManager.providerManager.store).toBeDefined()
          testProvider = new TestProvider(editor)
          expect(_.size(autocompleteManager.providerManager.store.propertySets)).toEqual(1)
          expect(autocompleteManager.providerManager.store.propertySets[0].properties.provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          mainModule.registerProviderForEditor(testProvider, editor)
          expect(_.size(autocompleteManager.providerManager.store.propertySets)).toEqual(2)
          expect(autocompleteManager.providerManager.store.propertySets[0].properties.provider).toEqual(testProvider)
          expect(autocompleteManager.providerManager.store.propertySets[0].selector.selector[0].classList[0]).toEqual('js')
          expect(autocompleteManager.providerManager.store.propertySets[0].selector.selector[0].classList[1]).toEqual('source')
          expect(autocompleteManager.providerManager.store.propertySets[1].properties.provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          mainModule.unregisterProvider(testProvider)
          expect(_.size(autocompleteManager.providerManager.store.propertySets)).toEqual(1)
          expect(autocompleteManager.providerManager.store.propertySets[0].properties.provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)

      it "buildSuggestions is called for a registered provider", ->
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

      it "confirm is called for a registered provider", ->
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

    describe "Provider API v0.1.0", ->
      [testProvider, autocomplete, registration] = []

      it "should allow registration of a provider via a grammar", ->
        runs ->
          testProvider = new TestProvider(editor)
          # Register the test provider
          consumer = atom.services.consume "autocomplete.provider-api", "0.1.0", (a) ->
            autocomplete = a
            registration = a.registerProviderForGrammars(testProvider, [editor.getGrammar()])

          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.store.propertySets)).toEqual(2)

          expect(autocompleteManager.providerManager.store.propertySets[0].properties.provider).toEqual(testProvider)
          expect(autocompleteManager.providerManager.store.propertySets[0].selector.selector[0].classList[0]).toEqual('js')
          expect(autocompleteManager.providerManager.store.propertySets[0].selector.selector[0].classList[1]).toEqual('source')
          expect(autocompleteManager.providerManager.store.propertySets[1].properties.provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          editor.moveToBottom()
          editor.insertText('o')

          advanceClock(completionDelay)

          suggestionListView = atom.views.getView(autocompleteManager.suggestionList)

          expect(suggestionListView.querySelector('li .label')).toHaveHtml('<span style="color: red">ohai</span>')
          expect(suggestionListView.querySelector('li')).toHaveClass('ohai')

      it "should allow registration of a provider via a scope", ->
        runs ->
          # Register the test provider
          consumer = atom.services.consume "autocomplete.provider-api", "0.1.0", (a) ->
            autocomplete = a
            testProvider = new TestProvider(editor)
            registration = a.registerProviderForScope(testProvider, '.source.js,.source.coffee')

          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.store.propertySets)).toEqual(3)
          expect(autocompleteManager.providerManager.store.propertySets[0].properties.provider).toEqual(testProvider)
          expect(autocompleteManager.providerManager.store.propertySets[0].selector.selector[0].classList[0]).toEqual('coffee')
          expect(autocompleteManager.providerManager.store.propertySets[0].selector.selector[0].classList[1]).toEqual('source')
          expect(autocompleteManager.providerManager.store.propertySets[1].properties.provider).toEqual(testProvider)
          expect(autocompleteManager.providerManager.store.propertySets[1].selector.selector[0].classList[0]).toEqual('js')
          expect(autocompleteManager.providerManager.store.propertySets[1].selector.selector[0].classList[1]).toEqual('source')
          expect(autocompleteManager.providerManager.store.propertySets[2].properties.provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          editor.moveToBottom()
          editor.insertText('o')

          advanceClock(completionDelay)

          suggestionListView = atom.views.getView(autocompleteManager.suggestionList)

          expect(suggestionListView.querySelector('li .label')).toHaveHtml('<span style="color: red">ohai</span>')
          expect(suggestionListView.querySelector('li')).toHaveClass('ohai')

      it "should allow disposal of the registration multiple times without error", ->
        runs ->
          testProvider = new TestProvider(editor)
          expect(_.contains(autocompleteManager.providerManager.subscriptions.disposables, testProvider)).toBe(false)

          # Register the test provider
          consumer = atom.services.consume "autocomplete.provider-api", "0.1.0", (a) ->
            autocomplete = a
            registration = a.registerProviderForScope(testProvider, '.source.js,.source.coffee')

          expect(_.contains(autocompleteManager.providerManager.subscriptions.disposables, testProvider)).toBe(true)
          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.store.propertySets)).toEqual(3)
          expect(autocompleteManager.providerManager.store.propertySets[0].properties.provider).toEqual(testProvider)
          expect(autocompleteManager.providerManager.store.propertySets[0].selector.selector[0].classList[0]).toEqual('coffee')
          expect(autocompleteManager.providerManager.store.propertySets[0].selector.selector[0].classList[1]).toEqual('source')
          expect(autocompleteManager.providerManager.store.propertySets[1].properties.provider).toEqual(testProvider)
          expect(autocompleteManager.providerManager.store.propertySets[1].selector.selector[0].classList[0]).toEqual('js')
          expect(autocompleteManager.providerManager.store.propertySets[1].selector.selector[0].classList[1]).toEqual('source')
          expect(autocompleteManager.providerManager.store.propertySets[2].properties.provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          registration.dispose()
          expect(_.contains(autocompleteManager.providerManager.subscriptions.disposables, testProvider)).toBe(false)
          expect(_.size(autocompleteManager.providerManager.store.propertySets)).toEqual(1)
          expect(autocompleteManager.providerManager.store.propertySets[0].properties.provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          registration.dispose()
          expect(_.contains(autocompleteManager.providerManager.subscriptions.disposables, testProvider)).toBe(false)
          expect(_.size(autocompleteManager.providerManager.store.propertySets)).toEqual(1)
          expect(autocompleteManager.providerManager.store.propertySets[0].properties.provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)

      it "should dispose a provider registration correctly", ->
        runs ->
          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.store.propertySets)).toEqual(1)
          expect(autocompleteManager.providerManager.store.propertySets[0].properties.provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          testProvider = new TestProvider(editor)

          # Register the test provider
          consumer = atom.services.consume "autocomplete.provider-api", "0.1.0", (a) ->
            autocomplete = a
            registration = a.registerProviderForScope(testProvider, '.source.js')

          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.store.propertySets)).toEqual(2)
          expect(autocompleteManager.providerManager.store.propertySets[0].properties.provider).toEqual(testProvider)
          expect(autocompleteManager.providerManager.store.propertySets[0].selector.selector[0].classList[0]).toEqual('js')
          expect(autocompleteManager.providerManager.store.propertySets[0].selector.selector[0].classList[1]).toEqual('source')
          expect(autocompleteManager.providerManager.store.propertySets[1].properties.provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          registration.dispose()
          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.store.propertySets)).toEqual(1)
          expect(autocompleteManager.providerManager.store.propertySets[0].properties.provider).toEqual(autocompleteManager.providerManager.fuzzyProvider)
