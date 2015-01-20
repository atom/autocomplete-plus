ProviderManager = require('../lib/provider-manager')
TestProvider = require('./lib/test-provider')
_ = require 'underscore-plus'

describe "Provider Manager", ->
  [providerManager, testProvider, legacyTestProvider] = []

  beforeEach ->
    runs ->
      providerManager = new ProviderManager()
      testProvider =
        requestHandler: (options) ->
          [new Suggestion(this,
            word: "ohai",
            prefix: "ohai",
            label: "<span style=\"color: red\">ohai</span>",
            renderLabelAsHtml: true,
            className: 'ohai'
          )]
        selector: '.source.js'
        dispose: ->
          # No-op

      legacyTestProvider = new TestProvider()

  afterEach ->
    runs ->
      # No-op

  fdescribe "when no providers have been registered", ->

    it "is constructed correctly", ->
      expect(providerManager.subscriptions).toBeDefined()
      expect(providerManager.store).toBeDefined()
      expect(providerManager.fuzzyProvider).toBeDefined()

    it "disposes correctly", ->
      providerManager.dispose()
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
