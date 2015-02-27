ProviderManager = require '../lib/provider-manager'
_ = require 'underscore-plus'

describe 'Provider Manager', ->
  [providerManager, testProvider, registration] = []

  beforeEach ->
    atom.config.set('autocomplete-plus.enableBuiltinProvider', true)
    providerManager = new ProviderManager()
    testProvider =
      getSuggestions: (options) ->
        [{
          text: 'ohai',
          replacementPrefix: 'ohai'
        }]
      selector: '.source.js'
      dispose: ->

  afterEach ->
    registration?.dispose?()
    registration = null
    testProvider?.dispose?()
    testProvider = null
    providerManager?.dispose()
    providerManager = null

  describe 'when no providers have been registered, and enableBuiltinProvider is true', ->
    beforeEach ->
      atom.config.set('autocomplete-plus.enableBuiltinProvider', true)

    it 'is constructed correctly', ->
      expect(providerManager.providers).toBeDefined()
      expect(providerManager.subscriptions).toBeDefined()
      expect(providerManager.store).toBeDefined()
      expect(providerManager.fuzzyProvider).toBeDefined()

    it 'disposes correctly', ->
      providerManager.dispose()
      expect(providerManager.providers).toBeNull()
      expect(providerManager.subscriptions).toBeNull()
      expect(providerManager.store).toBeNull()
      expect(providerManager.fuzzyProvider).toBeNull()

    it 'registers FuzzyProvider for all scopes', ->
      expect(_.size(providerManager.providersForScopeDescriptor('*'))).toBe(1)
      expect(providerManager.providersForScopeDescriptor('*')[0]).toBe(providerManager.fuzzyProvider)

    it 'adds providers', ->
      expect(providerManager.isProviderRegistered(testProvider)).toEqual(false)
      expect(_.contains(providerManager.subscriptions?.disposables, testProvider)).toEqual(false)

      providerManager.addProvider(testProvider, '2.0.0')
      expect(providerManager.isProviderRegistered(testProvider)).toEqual(true)
      apiVersion = providerManager.apiVersionForProvider(testProvider)
      expect(apiVersion).toEqual('2.0.0')
      expect(_.contains(providerManager.subscriptions?.disposables, testProvider)).toEqual(true)

    it 'removes providers', ->
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

    it 'can identify a provider with a missing getSuggestions', ->
      bogusProvider =
        badgetSuggestions: (options) ->
        selector: '.source.js'
        dispose: ->
      expect(providerManager.isValidProvider({}, '2.0.0')).toEqual(false)
      expect(providerManager.isValidProvider(bogusProvider, '2.0.0')).toEqual(false)
      expect(providerManager.isValidProvider(testProvider, '2.0.0')).toEqual(true)

    it 'can identify a provider with an invalid getSuggestions', ->
      bogusProvider =
        getSuggestions: 'yo, this is a bad handler'
        selector: '.source.js'
        dispose: ->
      expect(providerManager.isValidProvider({}, '2.0.0')).toEqual(false)
      expect(providerManager.isValidProvider(bogusProvider, '2.0.0')).toEqual(false)
      expect(providerManager.isValidProvider(testProvider, '2.0.0')).toEqual(true)

    it 'can identify a provider with a missing selector', ->
      bogusProvider =
        getSuggestions: (options) ->
        aSelector: '.source.js'
        dispose: ->
      expect(providerManager.isValidProvider(bogusProvider, '2.0.0')).toEqual(false)
      expect(providerManager.isValidProvider(testProvider, '2.0.0')).toEqual(true)

    it 'can identify a provider with an invalid selector', ->
      bogusProvider =
        getSuggestions: (options) ->
        selector: ''
        dispose: ->
      expect(providerManager.isValidProvider(bogusProvider, '2.0.0')).toEqual(false)
      expect(providerManager.isValidProvider(testProvider, '2.0.0')).toEqual(true)

      bogusProvider =
        getSuggestions: (options) ->
        selector: false
        dispose: ->

      expect(providerManager.isValidProvider(bogusProvider, '2.0.0')).toEqual(false)

    it 'correctly identifies a 1.0 provider', ->
      bogusProvider =
        selector: '.source.js'
        requestHandler: 'yo, this is a bad handler'
        dispose: ->
      expect(providerManager.isValidProvider({}, '1.0.0')).toEqual(false)
      expect(providerManager.isValidProvider(bogusProvider, '1.0.0')).toEqual(false)

      legitProvider =
        selector: '.source.js'
        requestHandler: ->
        dispose: ->
      expect(providerManager.isValidProvider(legitProvider, '1.0.0')).toEqual(true)

    it 'registers a valid provider', ->
      expect(_.size(providerManager.providersForScopeDescriptor('.source.js'))).toEqual(1)
      expect(_.contains(providerManager.providersForScopeDescriptor('.source.js'), testProvider)).toEqual(false)
      expect(providerManager.providers.has(testProvider)).toEqual(false)

      registration = providerManager.registerProvider(testProvider)
      expect(_.size(providerManager.providersForScopeDescriptor('.source.js'))).toEqual(2)
      expect(_.contains(providerManager.providersForScopeDescriptor('.source.js'), testProvider)).toEqual(true)
      expect(providerManager.providers.has(testProvider)).toEqual(true)

    it 'removes a registration', ->
      expect(_.size(providerManager.providersForScopeDescriptor('.source.js'))).toEqual(1)
      expect(_.contains(providerManager.providersForScopeDescriptor('.source.js'), testProvider)).toEqual(false)
      expect(providerManager.providers.has(testProvider)).toEqual(false)

      registration = providerManager.registerProvider(testProvider)
      expect(_.size(providerManager.providersForScopeDescriptor('.source.js'))).toEqual(2)
      expect(_.contains(providerManager.providersForScopeDescriptor('.source.js'), testProvider)).toEqual(true)
      expect(providerManager.providers.has(testProvider)).toEqual(true)
      registration.dispose()

      expect(_.size(providerManager.providersForScopeDescriptor('.source.js'))).toEqual(1)
      expect(_.contains(providerManager.providersForScopeDescriptor('.source.js'), testProvider)).toEqual(false)
      expect(providerManager.providers.has(testProvider)).toEqual(false)

    it 'does not create duplicate registrations for the same scope', ->
      expect(_.size(providerManager.providersForScopeDescriptor('.source.js'))).toEqual(1)
      expect(_.contains(providerManager.providersForScopeDescriptor('.source.js'), testProvider)).toEqual(false)
      expect(providerManager.providers.has(testProvider)).toEqual(false)

      registration = providerManager.registerProvider(testProvider)
      expect(_.size(providerManager.providersForScopeDescriptor('.source.js'))).toEqual(2)
      expect(_.contains(providerManager.providersForScopeDescriptor('.source.js'), testProvider)).toEqual(true)
      expect(providerManager.providers.has(testProvider)).toEqual(true)

      registration = providerManager.registerProvider(testProvider)
      expect(_.size(providerManager.providersForScopeDescriptor('.source.js'))).toEqual(2)
      expect(_.contains(providerManager.providersForScopeDescriptor('.source.js'), testProvider)).toEqual(true)
      expect(providerManager.providers.has(testProvider)).toEqual(true)

      registration = providerManager.registerProvider(testProvider)
      expect(_.size(providerManager.providersForScopeDescriptor('.source.js'))).toEqual(2)
      expect(_.contains(providerManager.providersForScopeDescriptor('.source.js'), testProvider)).toEqual(true)
      expect(providerManager.providers.has(testProvider)).toEqual(true)

    it 'does not register an invalid provider', ->
      bogusProvider =
        getSuggestions: 'yo, this is a bad handler'
        selector: '.source.js'
        dispose: ->
          return

      expect(_.size(providerManager.providersForScopeDescriptor('.source.js'))).toEqual(1)
      expect(_.contains(providerManager.providersForScopeDescriptor('.source.js'), bogusProvider)).toEqual(false)
      expect(providerManager.providers.has(bogusProvider)).toEqual(false)

      registration = providerManager.registerProvider(bogusProvider)
      expect(_.size(providerManager.providersForScopeDescriptor('.source.js'))).toEqual(1)
      expect(_.contains(providerManager.providersForScopeDescriptor('.source.js'), bogusProvider)).toEqual(false)
      expect(providerManager.providers.has(bogusProvider)).toEqual(false)

    it 'registers a provider with a blacklist', ->
      testProvider =
        getSuggestions: (options) ->
          [{
            text: 'ohai',
            replacementPrefix: 'ohai'
          }]
        selector: '.source.js'
        disableForSelector: '.source.js .comment'
        dispose: ->
          return

      expect(providerManager.isValidProvider(testProvider, '2.0.0')).toEqual(true)

      expect(_.size(providerManager.providersForScopeDescriptor('.source.js'))).toEqual(1)
      expect(_.contains(providerManager.providersForScopeDescriptor('.source.js'), testProvider)).toEqual(false)
      expect(providerManager.providers.has(testProvider)).toEqual(false)

      registration = providerManager.registerProvider(testProvider)
      expect(_.size(providerManager.providersForScopeDescriptor('.source.js'))).toEqual(2)
      expect(_.contains(providerManager.providersForScopeDescriptor('.source.js'), testProvider)).toEqual(true)
      expect(providerManager.providers.has(testProvider)).toEqual(true)

  describe 'when no providers have been registered, and enableBuiltinProvider is false', ->

    beforeEach ->
      atom.config.set('autocomplete-plus.enableBuiltinProvider', false)

    it 'does not register FuzzyProvider for all scopes', ->
      expect(_.size(providerManager.providersForScopeDescriptor('*'))).toBe(0)
      expect(providerManager.fuzzyProvider).toEqual(null)
      expect(providerManager.fuzzyRegistration).toEqual(null)

  describe 'when providers have been registered', ->
    [testProvider1, testProvider2, testProvider3, testProvider4] = []

    beforeEach ->
      atom.config.set('autocomplete-plus.enableBuiltinProvider', true)
      providerManager = new ProviderManager()

      testProvider1 =
        selector: '.source.js'
        getSuggestions: (options) ->
          [{
            text: 'ohai2',
            replacementPrefix: 'ohai2'
          }]
        dispose: ->

      testProvider2 =
        selector: '.source.js .variable.js'
        disableForSelector: '.source.js .variable.js .comment2'
        providerblacklist:
          'autocomplete-plus-fuzzyprovider': '.source.js .variable.js .comment3'
        getSuggestions: (options) ->
          [{
            text: 'ohai2',
            replacementPrefix: 'ohai2'
          }]
        dispose: ->

      testProvider3 =
        selector: '*'
        getSuggestions: (options) ->
          [{
            text: 'ohai3',
            replacementPrefix: 'ohai3'
          }]
        dispose: ->

      testProvider4 =
        selector: '.source.js .comment'
        getSuggestions: (options) ->
          [{
            text: 'ohai4',
            replacementPrefix: 'ohai4'
          }]
        dispose: ->

      providerManager.registerProvider(testProvider1)
      providerManager.registerProvider(testProvider2)
      providerManager.registerProvider(testProvider3)
      providerManager.registerProvider(testProvider4)

    it 'returns providers in the correct order for the given scope chain', ->
      fuzzyProvider = providerManager.fuzzyProvider

      providers = providerManager.providersForScopeDescriptor('.source.other')
      expect(providers).toHaveLength 2
      expect(providers[0]).toEqual testProvider3
      expect(providers[1]).toEqual fuzzyProvider

      providers = providerManager.providersForScopeDescriptor('.source.js')
      expect(providers).toHaveLength 3
      expect(providers[0]).toEqual testProvider1
      expect(providers[1]).toEqual testProvider3
      expect(providers[2]).toEqual fuzzyProvider

      providers = providerManager.providersForScopeDescriptor('.source.js .comment')
      expect(providers).toHaveLength 4
      expect(providers[0]).toEqual testProvider4
      expect(providers[1]).toEqual testProvider1
      expect(providers[2]).toEqual testProvider3
      expect(providers[3]).toEqual fuzzyProvider

      providers = providerManager.providersForScopeDescriptor('.source.js .variable.js')
      expect(providers).toHaveLength 4
      expect(providers[0]).toEqual testProvider2
      expect(providers[1]).toEqual testProvider1
      expect(providers[2]).toEqual testProvider3
      expect(providers[3]).toEqual fuzzyProvider

      providers = providerManager.providersForScopeDescriptor('.source.js .other.js')
      expect(providers).toHaveLength 3
      expect(providers[0]).toEqual testProvider1
      expect(providers[1]).toEqual testProvider3
      expect(providers[2]).toEqual fuzzyProvider

    it 'does not return providers if the scopeChain exactly matches a global blacklist item', ->
      expect(providerManager.providersForScopeDescriptor('.source.js .comment')).toHaveLength 4
      atom.config.set('autocomplete-plus.scopeBlacklist', ['.source.js .comment'])
      expect(providerManager.providersForScopeDescriptor('.source.js .comment')).toHaveLength 0

    it 'does not return providers if the scopeChain matches a global blacklist item with a wildcard', ->
      expect(providerManager.providersForScopeDescriptor('.source.js .comment')).toHaveLength 4
      atom.config.set('autocomplete-plus.scopeBlacklist', ['.source.js *'])
      expect(providerManager.providersForScopeDescriptor('.source.js .comment')).toHaveLength 0

    it 'does not return providers if the scopeChain matches a global blacklist item with a wildcard one level of depth below the current scope', ->
      expect(providerManager.providersForScopeDescriptor('.source.js .comment')).toHaveLength 4
      atom.config.set('autocomplete-plus.scopeBlacklist', ['.source.js *'])
      expect(providerManager.providersForScopeDescriptor('.source.js .comment .other')).toHaveLength 0

    it 'does return providers if the scopeChain does not match a global blacklist item with a wildcard', ->
      expect(providerManager.providersForScopeDescriptor('.source.js .comment')).toHaveLength 4
      atom.config.set('autocomplete-plus.scopeBlacklist', ['.source.coffee *'])
      expect(providerManager.providersForScopeDescriptor('.source.js .comment')).toHaveLength 4

    it 'filters a provider if the scopeChain matches a provider blacklist item', ->
      fuzzyProvider = providerManager.fuzzyProvider

      providers = providerManager.providersForScopeDescriptor('.source.js .variable.js .other.js')
      expect(providers).toHaveLength 4
      expect(providers[0]).toEqual testProvider2
      expect(providers[1]).toEqual testProvider1
      expect(providers[2]).toEqual testProvider3
      expect(providers[3]).toEqual fuzzyProvider

      providers = providerManager.providersForScopeDescriptor('.source.js .variable.js .comment2.js')
      expect(providers).toHaveLength 3
      expect(providers[0]).toEqual testProvider1
      expect(providers[1]).toEqual testProvider3
      expect(providers[2]).toEqual fuzzyProvider

    it 'filters a provider if the scopeChain matches a provider providerblacklist item', ->
      providers = providerManager.providersForScopeDescriptor('.source.js .variable.js .other.js')
      expect(providers).toHaveLength 4
      expect(providers[0]).toEqual(testProvider2)
      expect(providers[1]).toEqual(testProvider1)
      expect(providers[2]).toEqual(testProvider3)
      expect(providers[3]).toEqual(providerManager.fuzzyProvider)

      providers = providerManager.providersForScopeDescriptor('.source.js .variable.js .comment3.js')
      expect(providers).toHaveLength 3
      expect(providers[0]).toEqual(testProvider2)
      expect(providers[1]).toEqual(testProvider1)
      expect(providers[2]).toEqual(testProvider3)

  describe "when inclusion priorities are used", ->
    [accessoryProvider1, accessoryProvider2, verySpecificProvider, mainProvider, fuzzyProvider] = []

    beforeEach ->
      atom.config.set('autocomplete-plus.enableBuiltinProvider', true)
      providerManager = new ProviderManager()
      fuzzyProvider = providerManager.fuzzyProvider

      accessoryProvider1 =
        selector: '*'
        inclusionPriority: 2
        getSuggestions: (options) ->
        dispose: ->

      accessoryProvider2 =
        selector: '.source.js'
        inclusionPriority: 2
        getSuggestions: (options) ->
        dispose: ->

      verySpecificProvider =
        selector: '.source.js .comment'
        inclusionPriority: 2
        excludeLowerPriority: true
        getSuggestions: (options) ->
        dispose: ->

      mainProvider =
        selector: '.source.js'
        inclusionPriority: 1
        excludeLowerPriority: true
        getSuggestions: (options) ->
        dispose: ->

      providerManager.registerProvider(accessoryProvider1)
      providerManager.registerProvider(accessoryProvider2)
      providerManager.registerProvider(verySpecificProvider)
      providerManager.registerProvider(mainProvider)

    it 'returns the default provider and higher when nothing with a higher proirity is excluding the lower', ->
      providers = providerManager.providersForScopeDescriptor('.source.coffee')
      expect(providers).toHaveLength 2
      expect(providers[0]).toEqual accessoryProvider1
      expect(providers[1]).toEqual fuzzyProvider

    it 'exclude the lower priority provider, the default, when one with a higher proirity excludes the lower', ->
      providers = providerManager.providersForScopeDescriptor('.source.js')
      expect(providers).toHaveLength 3
      expect(providers[0]).toEqual mainProvider
      expect(providers[1]).toEqual accessoryProvider2
      expect(providers[2]).toEqual accessoryProvider1

    it 'excludes the all lower priority providers when multiple providers of lower priority', ->
      providers = providerManager.providersForScopeDescriptor('.source.js .comment')
      expect(providers).toHaveLength 3
      expect(providers[0]).toEqual verySpecificProvider
      expect(providers[1]).toEqual accessoryProvider2
      expect(providers[2]).toEqual accessoryProvider1
