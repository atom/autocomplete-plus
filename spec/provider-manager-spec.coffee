ProviderManager = require '../lib/provider-manager'

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
      expect(providerManager.defaultProvider).toBeDefined()

    it 'disposes correctly', ->
      providerManager.dispose()
      expect(providerManager.providers).toBeNull()
      expect(providerManager.subscriptions).toBeNull()
      expect(providerManager.defaultProvider).toBeNull()

    it 'registers the default provider for all scopes', ->
      expect(providerManager.providersForScopeDescriptor('*').length).toBe(1)
      expect(providerManager.providersForScopeDescriptor('*')[0]).toBe(providerManager.defaultProvider)

    it 'adds providers', ->
      expect(providerManager.isProviderRegistered(testProvider)).toEqual(false)
      expect(hasDisposable(providerManager.subscriptions, testProvider)).toBe false

      providerManager.addProvider(testProvider, '2.0.0')
      expect(providerManager.isProviderRegistered(testProvider)).toEqual(true)
      apiVersion = providerManager.apiVersionForProvider(testProvider)
      expect(apiVersion).toEqual('2.0.0')
      expect(hasDisposable(providerManager.subscriptions, testProvider)).toBe true

    it 'removes providers', ->
      expect(providerManager.metadataForProvider(testProvider)).toBeFalsy()
      expect(hasDisposable(providerManager.subscriptions, testProvider)).toBe false

      providerManager.addProvider(testProvider)
      expect(providerManager.metadataForProvider(testProvider)).toBeTruthy()
      expect(hasDisposable(providerManager.subscriptions, testProvider)).toBe true

      providerManager.removeProvider(testProvider)
      expect(providerManager.metadataForProvider(testProvider)).toBeFalsy()
      expect(hasDisposable(providerManager.subscriptions, testProvider)).toBe false

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
      expect(providerManager.providersForScopeDescriptor('.source.js').length).toEqual(1)
      expect(providerManager.providersForScopeDescriptor('.source.js').indexOf(testProvider)).toBe(-1)
      expect(providerManager.metadataForProvider(testProvider)).toBeFalsy()

      registration = providerManager.registerProvider(testProvider)
      expect(providerManager.providersForScopeDescriptor('.source.js').length).toEqual(2)
      expect(providerManager.providersForScopeDescriptor('.source.js').indexOf(testProvider)).not.toBe(-1)
      expect(providerManager.metadataForProvider(testProvider)).toBeTruthy()

    it 'removes a registration', ->
      expect(providerManager.providersForScopeDescriptor('.source.js').length).toEqual(1)
      expect(providerManager.providersForScopeDescriptor('.source.js').indexOf(testProvider)).toBe(-1)
      expect(providerManager.metadataForProvider(testProvider)).toBeFalsy()

      registration = providerManager.registerProvider(testProvider)
      expect(providerManager.providersForScopeDescriptor('.source.js').length).toEqual(2)
      expect(providerManager.providersForScopeDescriptor('.source.js').indexOf(testProvider)).not.toBe(-1)
      expect(providerManager.metadataForProvider(testProvider)).toBeTruthy()
      registration.dispose()

      expect(providerManager.providersForScopeDescriptor('.source.js').length).toEqual(1)
      expect(providerManager.providersForScopeDescriptor('.source.js').indexOf(testProvider)).toBe(-1)
      expect(providerManager.metadataForProvider(testProvider)).toBeFalsy()

    it 'does not create duplicate registrations for the same scope', ->
      expect(providerManager.providersForScopeDescriptor('.source.js').length).toEqual(1)
      expect(providerManager.providersForScopeDescriptor('.source.js').indexOf(testProvider)).toBe(-1)
      expect(providerManager.metadataForProvider(testProvider)).toBeFalsy()

      registration = providerManager.registerProvider(testProvider)
      expect(providerManager.providersForScopeDescriptor('.source.js').length).toEqual(2)
      expect(providerManager.providersForScopeDescriptor('.source.js').indexOf(testProvider)).not.toBe(-1)
      expect(providerManager.metadataForProvider(testProvider)).toBeTruthy()

      registration = providerManager.registerProvider(testProvider)
      expect(providerManager.providersForScopeDescriptor('.source.js').length).toEqual(2)
      expect(providerManager.providersForScopeDescriptor('.source.js').indexOf(testProvider)).not.toBe(-1)
      expect(providerManager.metadataForProvider(testProvider)).toBeTruthy()

      registration = providerManager.registerProvider(testProvider)
      expect(providerManager.providersForScopeDescriptor('.source.js').length).toEqual(2)
      expect(providerManager.providersForScopeDescriptor('.source.js').indexOf(testProvider)).not.toBe(-1)
      expect(providerManager.metadataForProvider(testProvider)).toBeTruthy()

    it 'does not register an invalid provider', ->
      bogusProvider =
        getSuggestions: 'yo, this is a bad handler'
        selector: '.source.js'
        dispose: ->
          return

      expect(providerManager.providersForScopeDescriptor('.source.js').length).toEqual(1)
      expect(providerManager.providersForScopeDescriptor('.source.js').indexOf(bogusProvider)).toBe(-1)
      expect(providerManager.metadataForProvider(bogusProvider)).toBeFalsy()

      registration = providerManager.registerProvider(bogusProvider)
      expect(providerManager.providersForScopeDescriptor('.source.js').length).toEqual(1)
      expect(providerManager.providersForScopeDescriptor('.source.js').indexOf(bogusProvider)).toBe(-1)
      expect(providerManager.metadataForProvider(bogusProvider)).toBeFalsy()

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

      expect(providerManager.providersForScopeDescriptor('.source.js').length).toEqual(1)
      expect(providerManager.providersForScopeDescriptor('.source.js').indexOf(testProvider)).toBe(-1)
      expect(providerManager.metadataForProvider(testProvider)).toBeFalsy()

      registration = providerManager.registerProvider(testProvider)
      expect(providerManager.providersForScopeDescriptor('.source.js').length).toEqual(2)
      expect(providerManager.providersForScopeDescriptor('.source.js').indexOf(testProvider)).not.toBe(-1)
      expect(providerManager.metadataForProvider(testProvider)).toBeTruthy()

  describe 'when no providers have been registered, and enableBuiltinProvider is false', ->

    beforeEach ->
      atom.config.set('autocomplete-plus.enableBuiltinProvider', false)

    it 'does not register the default provider for all scopes', ->
      expect(providerManager.providersForScopeDescriptor('*').length).toBe(0)
      expect(providerManager.defaultProvider).toEqual(null)
      expect(providerManager.defaultProviderRegistration).toEqual(null)

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
      defaultProvider = providerManager.defaultProvider

      providers = providerManager.providersForScopeDescriptor('.source.other')
      expect(providers).toHaveLength 2
      expect(providers[0]).toEqual testProvider3
      expect(providers[1]).toEqual defaultProvider

      providers = providerManager.providersForScopeDescriptor('.source.js')
      expect(providers).toHaveLength 3
      expect(providers[0]).toEqual testProvider1
      expect(providers[1]).toEqual testProvider3
      expect(providers[2]).toEqual defaultProvider

      providers = providerManager.providersForScopeDescriptor('.source.js .comment')
      expect(providers).toHaveLength 4
      expect(providers[0]).toEqual testProvider4
      expect(providers[1]).toEqual testProvider1
      expect(providers[2]).toEqual testProvider3
      expect(providers[3]).toEqual defaultProvider

      providers = providerManager.providersForScopeDescriptor('.source.js .variable.js')
      expect(providers).toHaveLength 4
      expect(providers[0]).toEqual testProvider2
      expect(providers[1]).toEqual testProvider1
      expect(providers[2]).toEqual testProvider3
      expect(providers[3]).toEqual defaultProvider

      providers = providerManager.providersForScopeDescriptor('.source.js .other.js')
      expect(providers).toHaveLength 3
      expect(providers[0]).toEqual testProvider1
      expect(providers[1]).toEqual testProvider3
      expect(providers[2]).toEqual defaultProvider

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
      defaultProvider = providerManager.defaultProvider

      providers = providerManager.providersForScopeDescriptor('.source.js .variable.js .other.js')
      expect(providers).toHaveLength 4
      expect(providers[0]).toEqual testProvider2
      expect(providers[1]).toEqual testProvider1
      expect(providers[2]).toEqual testProvider3
      expect(providers[3]).toEqual defaultProvider

      providers = providerManager.providersForScopeDescriptor('.source.js .variable.js .comment2.js')
      expect(providers).toHaveLength 3
      expect(providers[0]).toEqual testProvider1
      expect(providers[1]).toEqual testProvider3
      expect(providers[2]).toEqual defaultProvider

    it 'filters a provider if the scopeChain matches a provider providerblacklist item', ->
      providers = providerManager.providersForScopeDescriptor('.source.js .variable.js .other.js')
      expect(providers).toHaveLength 4
      expect(providers[0]).toEqual(testProvider2)
      expect(providers[1]).toEqual(testProvider1)
      expect(providers[2]).toEqual(testProvider3)
      expect(providers[3]).toEqual(providerManager.defaultProvider)

      providers = providerManager.providersForScopeDescriptor('.source.js .variable.js .comment3.js')
      expect(providers).toHaveLength 3
      expect(providers[0]).toEqual(testProvider2)
      expect(providers[1]).toEqual(testProvider1)
      expect(providers[2]).toEqual(testProvider3)

  describe "when inclusion priorities are used", ->
    [accessoryProvider1, accessoryProvider2, verySpecificProvider, mainProvider, defaultProvider] = []

    beforeEach ->
      atom.config.set('autocomplete-plus.enableBuiltinProvider', true)
      providerManager = new ProviderManager()
      defaultProvider = providerManager.defaultProvider

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
      expect(providers[1]).toEqual defaultProvider

    it 'exclude the lower priority provider, the default, when one with a higher proirity excludes the lower', ->
      providers = providerManager.providersForScopeDescriptor('.source.js')
      expect(providers).toHaveLength 3
      expect(providers[0]).toEqual accessoryProvider2
      expect(providers[1]).toEqual mainProvider
      expect(providers[2]).toEqual accessoryProvider1

    it 'excludes the all lower priority providers when multiple providers of lower priority', ->
      providers = providerManager.providersForScopeDescriptor('.source.js .comment')
      expect(providers).toHaveLength 3
      expect(providers[0]).toEqual verySpecificProvider
      expect(providers[1]).toEqual accessoryProvider2
      expect(providers[2]).toEqual accessoryProvider1

  describe "when suggestionPriorities are the same", ->
    [provider1, provider2, provider3, defaultProvider] = []
    beforeEach ->
      atom.config.set('autocomplete-plus.enableBuiltinProvider', true)
      providerManager = new ProviderManager()
      defaultProvider = providerManager.defaultProvider

      provider1 =
        selector: '*'
        suggestionPriority: 2
        getSuggestions: (options) ->
        dispose: ->

      provider2 =
        selector: '.source.js'
        suggestionPriority: 3
        getSuggestions: (options) ->
        dispose: ->

      provider3 =
        selector: '.source.js .comment'
        suggestionPriority: 2
        getSuggestions: (options) ->
        dispose: ->

      providerManager.registerProvider(provider1)
      providerManager.registerProvider(provider2)
      providerManager.registerProvider(provider3)

    it 'sorts by specificity', ->
      providers = providerManager.providersForScopeDescriptor('.source.js .comment')
      expect(providers).toHaveLength 4
      expect(providers[0]).toEqual provider2
      expect(providers[1]).toEqual provider3
      expect(providers[2]).toEqual provider1

hasDisposable = (compositeDisposable, disposable) ->
  if compositeDisposable?.disposables?.has?
    compositeDisposable.disposables.has(disposable)
  else if compositeDisposable?.disposables?.indexOf?
    compositeDisposable.disposables.indexOf(disposable) > -1
  else
    false
