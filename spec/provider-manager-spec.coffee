ProviderManager = require('../lib/provider-manager')
TestProvider = require('./lib/test-provider')
_ = require 'underscore-plus'

describe "Provider Manager", ->
  [providerManager, testProvider, legacyTestProvider, registration] = []

  beforeEach ->
    runs ->
      atom.config.set('autocomplete-plus.enableBuiltinProvider', true)
      providerManager = new ProviderManager()
      testProvider =
        requestHandler: (options) ->
          [{
            word: "ohai",
            prefix: "ohai",
            label: "<span style=\"color: red\">ohai</span>",
            renderLabelAsHtml: true,
            className: 'ohai'
          }]
        selector: '.source.js'
        dispose: ->
          # No-op

      legacyTestProvider = new TestProvider()

  afterEach ->
    runs ->
      registration?.dispose() if registration?.dispose?
      registration = null
      legacyTestProvider?.dispose() if legacyTestProvider?.dispose?
      legacyTestProvider = null
      testProvider?.dispose() if testProvider?.dispose?
      testProvider = null
      providerManager?.dispose()
      providerManager = null

  describe "when no providers have been registered, and enableBuiltinProvider is true", ->
    beforeEach ->
      atom.config.set('autocomplete-plus.enableBuiltinProvider', true)

    it "is constructed correctly", ->
      expect(providerManager.providers).toBeDefined()
      expect(providerManager.subscriptions).toBeDefined()
      expect(providerManager.store).toBeDefined()
      expect(providerManager.fuzzyProvider).toBeDefined()

    it "disposes correctly", ->
      providerManager.dispose()
      expect(providerManager.providers).toBeNull()
      expect(providerManager.subscriptions).toBeNull()
      expect(providerManager.store).toBeNull()
      expect(providerManager.fuzzyProvider).toBeNull()

    it "registers FuzzyProvider for all scopes", ->
      expect(_.size(providerManager.providersForScopeChain('*'))).toBe(1)
      expect(providerManager.providersForScopeChain('*')[0]).toBe(providerManager.fuzzyProvider)

    it "adds providers", ->
      expect(providerManager.providers.has(testProvider)).toEqual(false)
      expect(_.contains(providerManager.subscriptions?.disposables, testProvider)).toEqual(false)

      providerManager.addProvider(testProvider)
      expect(providerManager.providers.has(testProvider)).toEqual(true)
      uuid = providerManager.providers.get(testProvider)
      expect(uuid).toBeDefined()
      expect(uuid).not.toEqual('')
      expect(_.contains(providerManager.subscriptions?.disposables, testProvider)).toEqual(true)

      providerManager.addProvider(testProvider)
      expect(providerManager.providers.has(testProvider)).toEqual(true)
      uuid2 = providerManager.providers.get(testProvider)
      expect(uuid2).toBeDefined()
      expect(uuid2).not.toEqual('')
      expect(uuid).toEqual(uuid2)
      expect(_.contains(providerManager.subscriptions?.disposables, testProvider)).toEqual(true)
      providerManager.removeProvider(testProvider)

    it "removes providers", ->
      expect(providerManager.providers.has(testProvider)).toEqual(false)
      expect(_.contains(providerManager.subscriptions?.disposables, testProvider)).toEqual(false)

      providerManager.addProvider(testProvider)
      expect(providerManager.providers.has(testProvider)).toEqual(true)
      expect(providerManager.providers.get(testProvider)).toBeDefined()
      expect(providerManager.providers.get(testProvider)).not.toEqual('')
      expect(_.contains(providerManager.subscriptions?.disposables, testProvider)).toEqual(true)

      providerManager.removeProvider(testProvider)
      expect(providerManager.providers.has(testProvider)).toEqual(false)
      expect(_.contains(providerManager.subscriptions?.disposables, testProvider)).toEqual(false)

    it "can identify a legacy provider", ->
      expect(providerManager.isLegacyProvider(testProvider)).toEqual(false)
      expect(providerManager.isLegacyProvider(legacyTestProvider)).toEqual(true)

    it "can identify a provider with a missing requestHandler", ->
      bogusProvider =
        badRequestHandler: (options) ->
          return []
        selector: '.source.js'
        dispose: ->
          # No-op
      expect(providerManager.isValidProvider({})).toEqual(false)
      expect(providerManager.isValidProvider(bogusProvider)).toEqual(false)
      expect(providerManager.isValidProvider(testProvider)).toEqual(true)

    it "can identify a provider with an invalid requestHandler", ->
      bogusProvider =
        requestHandler: 'yo, this is a bad handler'
        selector: '.source.js'
        dispose: ->
          # No-op
      expect(providerManager.isValidProvider({})).toEqual(false)
      expect(providerManager.isValidProvider(bogusProvider)).toEqual(false)
      expect(providerManager.isValidProvider(testProvider)).toEqual(true)

    it "can identify a provider with a missing selector", ->
      bogusProvider =
        requestHandler: (options) ->
          return []
        aSelector: '.source.js'
        dispose: ->
          # No-op
      expect(providerManager.isValidProvider(bogusProvider)).toEqual(false)
      expect(providerManager.isValidProvider(testProvider)).toEqual(true)

    it "can identify a provider with an invalid selector", ->
      bogusProvider =
        requestHandler: (options) ->
          return []
        selector: ''
        dispose: ->
          # No-op
      expect(providerManager.isValidProvider(bogusProvider)).toEqual(false)
      expect(providerManager.isValidProvider(testProvider)).toEqual(true)

      bogusProvider =
        requestHandler: (options) ->
          return []
        selector: false
        dispose: ->
      expect(providerManager.isValidProvider(bogusProvider)).toEqual(false)

    it "registers a valid provider", ->
      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(1)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(false)
      expect(providerManager.providers.has(testProvider)).toEqual(false)

      registration = providerManager.registerProvider(testProvider)
      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(2)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(true)
      expect(providerManager.providers.has(testProvider)).toEqual(true)

    it "removes a registration", ->
      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(1)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(false)
      expect(providerManager.providers.has(testProvider)).toEqual(false)

      registration = providerManager.registerProvider(testProvider)
      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(2)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(true)
      expect(providerManager.providers.has(testProvider)).toEqual(true)
      registration.dispose()

      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(1)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(false)
      expect(providerManager.providers.has(testProvider)).toEqual(false)

    it "does not create duplicate registrations for the same scope", ->
      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(1)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(false)
      expect(providerManager.providers.has(testProvider)).toEqual(false)

      registration = providerManager.registerProvider(testProvider)
      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(2)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(true)
      expect(providerManager.providers.has(testProvider)).toEqual(true)

      registration = providerManager.registerProvider(testProvider)
      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(2)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(true)
      expect(providerManager.providers.has(testProvider)).toEqual(true)

      registration = providerManager.registerProvider(testProvider)
      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(2)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(true)
      expect(providerManager.providers.has(testProvider)).toEqual(true)

    it "does not register an invalid provider", ->
      bogusProvider =
        requestHandler: 'yo, this is a bad handler'
        selector: '.source.js'
        dispose: ->
      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(1)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), bogusProvider)).toEqual(false)
      expect(providerManager.providers.has(bogusProvider)).toEqual(false)

      registration = providerManager.registerProvider(bogusProvider)
      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(1)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), bogusProvider)).toEqual(false)
      expect(providerManager.providers.has(bogusProvider)).toEqual(false)

    it "shims a legacy provider during registration", ->
      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(1)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), providerManager.fuzzyProvider)).toEqual(true)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), legacyTestProvider)).toEqual(false)
      expect(providerManager.providers.has(legacyTestProvider)).toEqual(false)

      expect(providerManager.isLegacyProvider(legacyTestProvider)).toEqual(true)
      registration = providerManager.registerLegacyProvider(legacyTestProvider, '.source.js')
      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(2)
      expect(providerManager.legacyProviderRegistrations.has(legacyTestProvider.constructor)).toEqual(true)
      legacyProviderRegistration = providerManager.legacyProviderRegistrations.get(legacyTestProvider.constructor)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), legacyTestProvider)).toEqual(false)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), legacyProviderRegistration.shim)).toEqual(true)

    it "registers a provider with a blacklist", ->
      testProvider =
        requestHandler: (options) ->
          [{
            word: "ohai",
            prefix: "ohai",
            label: "<span style=\"color: red\">ohai</span>",
            renderLabelAsHtml: true,
            className: 'ohai'
          }]
        selector: '.source.js'
        blacklist: '.source.js .comment'
        dispose: ->
          # No-op

      expect(providerManager.isValidProvider(testProvider)).toEqual(true)

      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(1)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(false)
      expect(providerManager.providers.has(testProvider)).toEqual(false)

      registration = providerManager.registerProvider(testProvider)
      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(2)
      expect(_.contains(providerManager.providersForScopeChain('.source.js'), testProvider)).toEqual(true)
      expect(providerManager.providers.has(testProvider)).toEqual(true)

  describe "when no providers have been registered, and enableBuiltinProvider is false", ->

    beforeEach ->
      atom.config.set('autocomplete-plus.enableBuiltinProvider', false)

    it "doesn't register FuzzyProvider for all scopes", ->
      expect(_.size(providerManager.providersForScopeChain('*'))).toBe(0)
      expect(providerManager.fuzzyProvider).toEqual(null)
      expect(providerManager.fuzzyRegistration).toEqual(null)

  describe "when providers have been registered", ->
    [testProvider1, testProvider2, testProvider3, testProvider4, registration1, registration2, registration3, registration4] = []

    beforeEach ->
      runs ->
        atom.config.set('autocomplete-plus.enableBuiltinProvider', true)
        providerManager = new ProviderManager()
        testProvider1 =
          requestHandler: (options) ->
            [{
              word: "ohai2",
              prefix: "ohai2",
              label: "<span style=\"color: red\">ohai2</span>",
              renderLabelAsHtml: true,
              className: 'ohai2'
            }]
          selector: '.source.js'
          dispose: ->
            # No-op

        testProvider2 =
          requestHandler: (options) ->
            [{
              word: "ohai2",
              prefix: "ohai2",
              label: "<span style=\"color: red\">ohai2</span>",
              renderLabelAsHtml: true,
              className: 'ohai2'
            }]
          selector: '.source.js .variable.js'
          blacklist: '.source.js .variable.js .comment2'
          providerblacklist:
            'autocomplete-plus-fuzzyprovider': '.source.js .variable.js .comment3'
          dispose: ->
            # No-op

        testProvider3 =
          requestHandler: (options) ->
            [{
              word: "ohai3",
              prefix: "ohai3",
              label: "<span style=\"color: red\">ohai3</span>",
              renderLabelAsHtml: true,
              className: 'ohai3'
            }]
          selector: '*'
          dispose: ->
            # No-op

        testProvider4 =
          requestHandler: (options) ->
            [{
              word: "ohai4",
              prefix: "ohai4",
              label: "<span style=\"color: red\">ohai4</span>",
              renderLabelAsHtml: true,
              className: 'ohai4'
            }]
          selector: '.source.js .comment'
          dispose: ->
            # No-op

        registration1 = providerManager.registerProvider(testProvider1)
        registration2 = providerManager.registerProvider(testProvider2)
        registration3 = providerManager.registerProvider(testProvider3)
        registration4 = providerManager.registerProvider(testProvider4)

    afterEach ->
      registration1?.dispose()
      registration2?.dispose()
      registration3?.dispose()
      registration4?.dispose()
      registration1 = null
      registration2 = null
      registration3 = null
      registration4 = null
      testProvider1 = null
      testProvider2 = null
      testProvider3 = null
      testProvider4 = null

    it "returns providers in the correct order for the given scope chain", ->
      expect(_.size(providerManager.providersForScopeChain('.source.other'))).toEqual(2)
      expect(providerManager.providersForScopeChain('.source.other')[0]).toEqual(testProvider3)
      expect(providerManager.providersForScopeChain('.source.other')[1]).toEqual(providerManager.fuzzyProvider)

      expect(_.size(providerManager.providersForScopeChain('.source.js'))).toEqual(3)
      expect(providerManager.providersForScopeChain('.source.js')[0]).toEqual(testProvider1)
      expect(providerManager.providersForScopeChain('.source.js')[1]).toEqual(testProvider3)
      expect(providerManager.providersForScopeChain('.source.js')[2]).toEqual(providerManager.fuzzyProvider)

      expect(_.size(providerManager.providersForScopeChain('.source.js .comment'))).toEqual(4)
      expect(providerManager.providersForScopeChain('.source.js .comment')[0]).toEqual(testProvider4)
      expect(providerManager.providersForScopeChain('.source.js .comment')[1]).toEqual(testProvider1)
      expect(providerManager.providersForScopeChain('.source.js .comment')[2]).toEqual(testProvider3)
      expect(providerManager.providersForScopeChain('.source.js .comment')[3]).toEqual(providerManager.fuzzyProvider)

      expect(_.size(providerManager.providersForScopeChain('.source.js .variable.js'))).toEqual(4)

      expect(providerManager.providersForScopeChain('.source.js .variable.js')[0]).toEqual(testProvider2)
      expect(providerManager.providersForScopeChain('.source.js .variable.js')[1]).toEqual(testProvider1)
      expect(providerManager.providersForScopeChain('.source.js .variable.js')[2]).toEqual(testProvider3)
      expect(providerManager.providersForScopeChain('.source.js .variable.js')[3]).toEqual(providerManager.fuzzyProvider)

      expect(_.size(providerManager.providersForScopeChain('.source.js .other.js'))).toEqual(3)
      expect(providerManager.providersForScopeChain('.source.js .comment')[1]).toEqual(testProvider1)
      expect(providerManager.providersForScopeChain('.source.js .comment')[2]).toEqual(testProvider3)
      expect(providerManager.providersForScopeChain('.source.js .comment')[3]).toEqual(providerManager.fuzzyProvider)

    it "doesn't return providers if the scopeChain exactly matches a global blacklist item", =>
      expect(_.size(providerManager.providersForScopeChain('.source.js .comment'))).toEqual(4)
      atom.config.set('autocomplete-plus.scopeBlacklist', ['.source.js .comment'])
      expect(_.size(providerManager.providersForScopeChain('.source.js .comment'))).toEqual(0)

    it "doesn't return providers if the scopeChain matches a global blacklist item with a wildcard", =>
      expect(_.size(providerManager.providersForScopeChain('.source.js .comment'))).toEqual(4)
      atom.config.set('autocomplete-plus.scopeBlacklist', ['.source.js *'])
      expect(_.size(providerManager.providersForScopeChain('.source.js .comment'))).toEqual(0)

    it "doesn't return providers if the scopeChain matches a global blacklist item with a wildcard one level of depth below the current scope", =>
      expect(_.size(providerManager.providersForScopeChain('.source.js .comment'))).toEqual(4)
      atom.config.set('autocomplete-plus.scopeBlacklist', ['.source.js *'])
      expect(_.size(providerManager.providersForScopeChain('.source.js .comment .other'))).toEqual(0)

    it "does return providers if the scopeChain doesn't match a global blacklist item with a wildcard", =>
      expect(_.size(providerManager.providersForScopeChain('.source.js .comment'))).toEqual(4)
      atom.config.set('autocomplete-plus.scopeBlacklist', ['.source.coffee *'])
      expect(_.size(providerManager.providersForScopeChain('.source.js .comment'))).toEqual(4)

    it "filters a provider if the scopeChain matches a provider blacklist item", =>
      expect(_.size(providerManager.providersForScopeChain('.source.js .variable.js .other.js'))).toEqual(4)
      expect(providerManager.providersForScopeChain('.source.js .variable.js .other.js')[0]).toEqual(testProvider2)
      expect(providerManager.providersForScopeChain('.source.js .variable.js .other.js')[1]).toEqual(testProvider1)
      expect(providerManager.providersForScopeChain('.source.js .variable.js .other.js')[2]).toEqual(testProvider3)
      expect(providerManager.providersForScopeChain('.source.js .variable.js .other.js')[3]).toEqual(providerManager.fuzzyProvider)

      expect(_.size(providerManager.providersForScopeChain('.source.js .variable.js .comment2.js'))).toEqual(3)
      expect(providerManager.providersForScopeChain('.source.js .variable.js .comment2.js')[0]).toEqual(testProvider1)
      expect(providerManager.providersForScopeChain('.source.js .variable.js .comment2.js')[1]).toEqual(testProvider3)
      expect(providerManager.providersForScopeChain('.source.js .variable.js .comment2.js')[2]).toEqual(providerManager.fuzzyProvider)

    it "filters a provider if the scopeChain matches a provider providerblacklist item", =>
      expect(_.size(providerManager.providersForScopeChain('.source.js .variable.js .other.js'))).toEqual(4)
      expect(providerManager.providersForScopeChain('.source.js .variable.js .other.js')[0]).toEqual(testProvider2)
      expect(providerManager.providersForScopeChain('.source.js .variable.js .other.js')[1]).toEqual(testProvider1)
      expect(providerManager.providersForScopeChain('.source.js .variable.js .other.js')[2]).toEqual(testProvider3)
      expect(providerManager.providersForScopeChain('.source.js .variable.js .other.js')[3]).toEqual(providerManager.fuzzyProvider)

      expect(_.size(providerManager.providersForScopeChain('.source.js .variable.js .comment3.js'))).toEqual(3)
      expect(providerManager.providersForScopeChain('.source.js .variable.js .comment3.js')[0]).toEqual(testProvider2)
      expect(providerManager.providersForScopeChain('.source.js .variable.js .comment3.js')[1]).toEqual(testProvider1)
      expect(providerManager.providersForScopeChain('.source.js .variable.js .comment3.js')[2]).toEqual(testProvider3)
