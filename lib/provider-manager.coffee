{CompositeDisposable, Disposable} = require 'atom'
{isFunction, isString} = require('./type-helpers')
semver = require 'semver'
{Selector} = require 'selector-kit'
stableSort = require 'stable'

{selectorsMatchScopeChain} = require('./scope-helpers')
{API_VERSION} = require './private-symbols'

# Deferred requires
SymbolProvider = null
FuzzyProvider =  null
grim = null
ProviderMetadata = null

module.exports =
class ProviderManager
  defaultProvider: null
  defaultProviderRegistration: null
  providers: null
  store: null
  subscriptions: null
  globalBlacklist: null

  constructor: ->
    @subscriptions = new CompositeDisposable
    @globalBlacklist = new CompositeDisposable
    @subscriptions.add(@globalBlacklist)
    @providers = []
    @subscriptions.add(atom.config.observe('autocomplete-plus.enableBuiltinProvider', (value) => @toggleDefaultProvider(value)))
    @subscriptions.add(atom.config.observe('autocomplete-plus.scopeBlacklist', (value) => @setGlobalBlacklist(value)))

  dispose: ->
    @toggleDefaultProvider(false)
    @subscriptions?.dispose()
    @subscriptions = null
    @globalBlacklist = null
    @providers = null

  applicableProviders: (editor, scopeDescriptor) =>
    providers = @filterProvidersByEditor(@providers, editor)
    providers = @filterProvidersByScopeDescriptor(providers, scopeDescriptor)
    providers = @sortProviders(providers, scopeDescriptor)
    providers = @filterProvidersByExcludeLowerPriority(providers)
    @removeMetadata(providers)

  filterProvidersByScopeDescriptor: (providers, scopeDescriptor) ->
    scopeChain = scopeChainForScopeDescriptor(scopeDescriptor)
    return [] unless scopeChain
    return [] if @globalBlacklistSelectors? and selectorsMatchScopeChain(@globalBlacklistSelectors, scopeChain)

    matchingProviders = []
    disableDefaultProvider = false
    defaultProviderMetadata = null
    for providerMetadata in providers
      {provider} = providerMetadata
      if provider is @defaultProvider
        defaultProviderMetadata = providerMetadata
      if providerMetadata.matchesScopeChain(scopeChain)
        matchingProviders.push(providerMetadata)
        if providerMetadata.shouldDisableDefaultProvider(scopeChain)
          disableDefaultProvider = true

    if disableDefaultProvider
      index = matchingProviders.indexOf(defaultProviderMetadata)
      matchingProviders.splice(index, 1) if index > -1
    matchingProviders

  sortProviders: (providers, scopeDescriptor) ->
    scopeChain = scopeChainForScopeDescriptor(scopeDescriptor)
    stableSort providers, (providerA, providerB) ->
      difference = (providerB.provider.suggestionPriority ? 1) - (providerA.provider.suggestionPriority ? 1)
      if difference is 0
        specificityA = providerA.getSpecificity(scopeChain)
        specificityB = providerB.getSpecificity(scopeChain)
        difference = specificityB - specificityA
      difference

  filterProvidersByEditor: (providers, editor) ->
    providers.filter((providerMetadata) ->
      providerMetadata.matchesEditor(editor))

  filterProvidersByExcludeLowerPriority: (providers) ->
    lowestAllowedPriority = 0
    for providerMetadata in providers
      {provider} = providerMetadata
      if provider.excludeLowerPriority
        lowestAllowedPriority = Math.max(lowestAllowedPriority, provider.inclusionPriority ? 0)
    providerMetadata for providerMetadata in providers when (providerMetadata.provider.inclusionPriority ? 0) >= lowestAllowedPriority

  removeMetadata: (providers) ->
    providers.map((providerMetadata) -> providerMetadata.provider)

  toggleDefaultProvider: (enabled) =>
    return unless enabled?

    if enabled
      return if @defaultProvider? or @defaultProviderRegistration?
      if atom.config.get('autocomplete-plus.defaultProvider') is 'Symbol'
        SymbolProvider ?= require('./symbol-provider')
        @defaultProvider = new SymbolProvider()
      else
        FuzzyProvider ?= require('./fuzzy-provider')
        @defaultProvider = new FuzzyProvider()
      @defaultProviderRegistration = @registerProvider(@defaultProvider)
    else
      @defaultProviderRegistration?.dispose()
      @defaultProvider?.dispose()
      @defaultProviderRegistration = null
      @defaultProvider = null

  setGlobalBlacklist: (globalBlacklist) =>
    @globalBlacklistSelectors = null
    if globalBlacklist?.length
      @globalBlacklistSelectors = Selector.create(globalBlacklist)

  isValidProvider: (provider, apiVersion) ->
    # TODO API: Check based on the apiVersion
    if semver.satisfies(apiVersion, '>=2.0.0')
      provider? and
      isFunction(provider.getSuggestions) and
      ((isString(provider.selector) and !!provider.selector.length) or
       (isString(provider.scopeSelector) and !!provider.scopeSelector.length))
    else
      provider? and isFunction(provider.requestHandler) and isString(provider.selector) and !!provider.selector.length

  metadataForProvider: (provider) =>
    for providerMetadata in @providers
      return providerMetadata if providerMetadata.provider is provider
    null

  apiVersionForProvider: (provider) =>
    @metadataForProvider(provider)?.apiVersion

  isProviderRegistered: (provider) ->
    @metadataForProvider(provider)?

  addProvider: (provider, apiVersion='2.0.0') =>
    return if @isProviderRegistered(provider)
    ProviderMetadata ?= require './provider-metadata'
    @providers.push new ProviderMetadata(provider, apiVersion)
    @subscriptions.add(provider) if provider.dispose?

  removeProvider: (provider) =>
    return unless @providers
    for providerMetadata, i in @providers
      if providerMetadata.provider is provider
        @providers.splice(i, 1)
        break
    @subscriptions?.remove(provider) if provider.dispose?

  registerProvider: (provider, apiVersion='2.0.0') =>
    return unless provider?

    provider[API_VERSION] = apiVersion

    apiIs2_0 = semver.satisfies(apiVersion, '>=2.0.0')
    apiIs2_1 = semver.satisfies(apiVersion, '>=2.1.0')

    if apiIs2_0
      if provider.id? and provider isnt @defaultProvider
        grim ?= require 'grim'
        grim.deprecate """
          Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
          contains an `id` property.
          An `id` attribute on your provider is no longer necessary.
          See https://github.com/atom/autocomplete-plus/wiki/Provider-API
        """
      if provider.requestHandler?
        grim ?= require 'grim'
        grim.deprecate """
          Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
          contains a `requestHandler` property.
          `requestHandler` has been renamed to `getSuggestions`.
          See https://github.com/atom/autocomplete-plus/wiki/Provider-API
        """
      if provider.blacklist?
        grim ?= require 'grim'
        grim.deprecate """
          Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
          contains a `blacklist` property.
          `blacklist` has been renamed to `disableForScopeSelector`.
          See https://github.com/atom/autocomplete-plus/wiki/Provider-API
        """

    if apiIs2_1
      if provider.selector?
        grim ?= require 'grim'
        grim.deprecate """
          Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
          specifies `selector` instead of the `scopeSelector` attribute.
          See https://github.com/atom/autocomplete-plus/wiki/Provider-API.
        """

      if provider.disableForSelector?
        grim ?= require 'grim'
        grim.deprecate """
          Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
          specifies `disableForSelector` instead of the `disableForScopeSelector`
          attribute.
          See https://github.com/atom/autocomplete-plus/wiki/Provider-API.
        """

    unless @isValidProvider(provider, apiVersion)
      console.warn "Provider #{provider.constructor.name} is not valid", provider
      return new Disposable()

    return if @isProviderRegistered(provider)

    @addProvider(provider, apiVersion)

    disposable = new Disposable =>
      @removeProvider(provider)

    # When the provider is disposed, remove its registration
    if originalDispose = provider.dispose
      provider.dispose = ->
        originalDispose.call(provider)
        disposable.dispose()

    disposable

scopeChainForScopeDescriptor = (scopeDescriptor) ->
  # TODO: most of this is temp code to understand #308
  type = typeof scopeDescriptor
  if type is 'string'
    scopeDescriptor
  else if type is 'object' and scopeDescriptor?.getScopeChain?
    scopeChain = scopeDescriptor.getScopeChain()
    if scopeChain? and not scopeChain.replace?
      json = JSON.stringify(scopeDescriptor)
      console.log scopeDescriptor, json
      throw new Error("01: ScopeChain is not correct type: #{type}; #{json}")
    scopeChain
  else
    json = JSON.stringify(scopeDescriptor)
    console.log scopeDescriptor, json
    throw new Error("02: ScopeChain is not correct type: #{type}; #{json}")
