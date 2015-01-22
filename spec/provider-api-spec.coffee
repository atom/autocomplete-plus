{waitForAutocomplete} = require('./spec-helper')
TestProvider = require('./lib/test-provider')
_ = require 'underscore-plus'

describe "Provider API", ->
  [completionDelay, editor, mainModule, autocompleteManager, registration, testProvider] = []

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
      mainModule = a.mainModule
      autocompleteManager = mainModule.autocompleteManager

  afterEach ->
    registration?.dispose() if registration?.dispose?
    registration = null
    testProvider?.dispose() if testProvider?.dispose?
    testProvider = null

  describe "When the Editor has a grammar", ->

    beforeEach ->
      waitsForPromise -> atom.packages.activatePackage('language-javascript')

    describe "Legacy Provider API", ->
      it "registers the given provider for the given editor", ->
        runs ->
          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(1)

          testProvider = new TestProvider()
          expect(autocompleteManager.providerManager.isLegacyProvider(testProvider)).toEqual(true)
          registration = mainModule.registerProviderForEditor(testProvider, editor)

          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(2)
          expect(autocompleteManager.providerManager.providers.has(testProvider)).toEqual(true)
          shimProvider = autocompleteManager.providerManager.providers.get(testProvider)
          expect(autocompleteManager.providerManager.providers.has(shimProvider)).toEqual(true)
          expect(_.contains(autocompleteManager.providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(false)
          expect(_.contains(autocompleteManager.providerManager.providersForScopeChain('.source.js'), shimProvider)).toEqual(true)

      it "registers the given provider once when called multiple times for the given editor", ->
        runs ->
          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(1)

          testProvider = new TestProvider()
          expect(autocompleteManager.providerManager.isLegacyProvider(testProvider)).toEqual(true)
          registration = mainModule.registerProviderForEditor(testProvider, editor)

          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(2)
          expect(autocompleteManager.providerManager.providers.has(testProvider)).toEqual(true)
          shimProvider = autocompleteManager.providerManager.providers.get(testProvider)
          expect(autocompleteManager.providerManager.providers.has(shimProvider)).toEqual(true)
          expect(_.contains(autocompleteManager.providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(false)
          expect(_.contains(autocompleteManager.providerManager.providersForScopeChain('.source.js'), shimProvider)).toEqual(true)

          registration = mainModule.registerProviderForEditor(testProvider, editor)

          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(2)
          expect(autocompleteManager.providerManager.providers.has(testProvider)).toEqual(true)
          shimProvider = autocompleteManager.providerManager.providers.get(testProvider)
          expect(autocompleteManager.providerManager.providers.has(shimProvider)).toEqual(true)
          expect(_.contains(autocompleteManager.providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(false)
          expect(_.contains(autocompleteManager.providerManager.providersForScopeChain('.source.js'), shimProvider)).toEqual(true)

          registration = mainModule.registerProviderForEditor(testProvider, editor)

          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(2)
          expect(autocompleteManager.providerManager.providers.has(testProvider)).toEqual(true)
          shimProvider = autocompleteManager.providerManager.providers.get(testProvider)
          expect(autocompleteManager.providerManager.providers.has(shimProvider)).toEqual(true)
          expect(_.contains(autocompleteManager.providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(false)
          expect(_.contains(autocompleteManager.providerManager.providersForScopeChain('.source.js'), shimProvider)).toEqual(true)

      it "unregisters the provider from all editors", ->
        runs ->
          expect(autocompleteManager.providerManager.store).toBeDefined()
          testProvider = new TestProvider()
          expect(autocompleteManager.providerManager.isLegacyProvider(testProvider)).toEqual(true)
          registration = mainModule.registerProviderForEditor(testProvider, editor)

          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(2)
          expect(autocompleteManager.providerManager.providers.has(testProvider)).toEqual(true)
          shimProvider = autocompleteManager.providerManager.providers.get(testProvider)
          expect(autocompleteManager.providerManager.providers.has(shimProvider)).toEqual(true)
          expect(_.contains(autocompleteManager.providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(false)
          expect(_.contains(autocompleteManager.providerManager.providersForScopeChain('.source.js'), shimProvider)).toEqual(true)

          mainModule.unregisterProvider(testProvider)
          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(1)
          expect(autocompleteManager.providerManager.providers.has(testProvider)).toEqual(false)
          expect(autocompleteManager.providerManager.providers.has(shimProvider)).toEqual(false)

      it "buildSuggestions is called for a registered provider", ->
        runs ->
          testProvider = new TestProvider()
          mainModule.registerProviderForEditor(testProvider, editor)

          spyOn(testProvider, "buildSuggestions").andCallThrough()

          # Trigger an autocompletion
          editor.moveToBottom()
          editor.moveToBeginningOfLine()
          editor.insertText('f')
          advanceClock completionDelay

          expect(testProvider.buildSuggestions).toHaveBeenCalled()

    describe "Provider API v0.1.0", ->
      [registration1, registration2, registration3] = []

      afterEach ->
        registration1?.dispose()
        registration2?.dispose()
        registration3?.dispose()

      it "should allow registration of a provider", ->
        runs ->
          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(1)
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.coffee'))).toEqual(1)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          testProvider =
            requestHandler: (options) ->
              [{
                provider: testProvider,
                word: "ohai",
                prefix: "ohai",
                label: "<span style=\"color: red\">ohai</span>",
                renderLabelAsHtml: true,
                className: 'ohai'
              }]
            selector: '.source.js,.source.coffee'
            dispose: ->
          # Register the test provider
          registration = atom.services.provide('autocomplete.provider', '0.1.0', {provider:testProvider})

          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(2)
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.coffee'))).toEqual(2)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[0]).toEqual(testProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[1]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[0]).toEqual(testProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[1]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.go')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          editor.moveToBottom()
          editor.insertText('o')

          waitForAutocomplete()

          runs ->
            suggestionListView = atom.views.getView(autocompleteManager.suggestionList)

            expect(suggestionListView.querySelector('li .label')).toHaveHtml('<span style="color: red">ohai</span>')
            expect(suggestionListView.querySelector('li')).toHaveClass('ohai')

      xit "registers the given provider once when provided times", ->
        runs ->
          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(1)
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.coffee'))).toEqual(1)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          testProvider =
            requestHandler: (options) ->
              [{
                provider: testProvider,
                word: "ohai",
                prefix: "ohai",
                label: "<span style=\"color: red\">ohai</span>",
                renderLabelAsHtml: true,
                className: 'ohai'
              }]
            selector: '.source.js,.source.coffee'
            dispose: ->
          # Register the test provider
          registration1 = atom.services.provide('autocomplete.provider', '0.1.0', {provider:testProvider})

          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(2)
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.coffee'))).toEqual(2)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[0]).toEqual(testProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[1]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[0]).toEqual(testProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[1]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.go')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          editor.moveToBottom()
          editor.insertText('o')

          advanceClock(completionDelay)

          suggestionListView = atom.views.getView(autocompleteManager.suggestionList)

          expect(suggestionListView.querySelector('li .label')).toHaveHtml('<span style="color: red">ohai</span>')
          expect(suggestionListView.querySelector('li')).toHaveClass('ohai')

          registration2 = atom.services.provide('autocomplete.provider', '0.1.0', {provider:testProvider})

          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(2)
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.coffee'))).toEqual(2)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[0]).toEqual(testProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[1]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[0]).toEqual(testProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[1]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.go')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          registration3 = atom.services.provide('autocomplete.provider', '0.1.0', {provider:testProvider})

          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(2)
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.coffee'))).toEqual(2)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[0]).toEqual(testProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[1]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[0]).toEqual(testProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[1]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.go')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)

      xit "should dispose a provider registration correctly", ->
        runs ->
          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(1)
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.coffee'))).toEqual(1)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          testProvider =
            requestHandler: (options) ->
              [{
                provider: testProvider,
                word: "ohai",
                prefix: "ohai",
                label: "<span style=\"color: red\">ohai</span>",
                renderLabelAsHtml: true,
                className: 'ohai'
              }]
            selector: '.source.js,.source.coffee'
            dispose: ->
          # Register the test provider
          registration = atom.services.provide('autocomplete.provider', '0.1.0', {provider:testProvider})

          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(2)
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.coffee'))).toEqual(2)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[0]).toEqual(testProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[1]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[0]).toEqual(testProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[1]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.go')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          registration.dispose()

          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(1)
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.coffee'))).toEqual(1)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          registration.dispose()

          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(1)
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.coffee'))).toEqual(1)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)

      xit "should remove a provider's registration if the provider is disposed", ->
        runs ->
          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(1)
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.coffee'))).toEqual(1)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          testProvider =
            requestHandler: (options) ->
              [{
                provider: testProvider,
                word: "ohai",
                prefix: "ohai",
                label: "<span style=\"color: red\">ohai</span>",
                renderLabelAsHtml: true,
                className: 'ohai'
              }]
            selector: '.source.js,.source.coffee'
            dispose: ->
          # Register the test provider
          registration = atom.services.provide('autocomplete.provider', '0.1.0', {provider:testProvider})

          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(2)
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.coffee'))).toEqual(2)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[0]).toEqual(testProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[1]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[0]).toEqual(testProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[1]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.go')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)

          testProvider.dispose()

          expect(autocompleteManager.providerManager.store).toBeDefined()
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.js'))).toEqual(1)
          expect(_.size(autocompleteManager.providerManager.providersForScopeChain('.source.coffee'))).toEqual(1)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.js')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
          expect(autocompleteManager.providerManager.providersForScopeChain('.source.coffee')[0]).toEqual(autocompleteManager.providerManager.fuzzyProvider)
