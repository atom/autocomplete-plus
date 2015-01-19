ProviderManager = require('../lib/provider-manager')
_ = require 'underscore-plus'

describe "Provider Manager", ->
  [providerManager] = []

  beforeEach ->
    runs ->
      providerManager = new ProviderManager()

  afterEach ->
    runs ->
      # No-op

  describe "When no providers have been registered", ->

    it "Is constructed correctly", ->
      expect(providerManager.subscriptions).toBeDefined()
      expect(providerManager.store).toBeDefined()
      expect(providerManager.fuzzyProvider).toBeDefined()

    it "Disposes correctly", ->
      providerManager.dispose()
      expect(providerManager.subscriptions).toBeNull()
      expect(providerManager.store).toBeNull()
      expect(providerManager.fuzzyProvider).toBeNull()

    it "Registers FuzzyProvider", ->
      expect(_.size(providerManager.providersForScopeChain('*'))).toBe(1)
      expect(providerManager.providersForScopeChain('*')[0]).toBe(providerManager.fuzzyProvider)
