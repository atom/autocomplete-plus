{CompositeDisposable, Disposable} = require 'atom'
_ = require 'underscore-plus'
semver = require 'semver'
{Selector} = require 'selector-kit'
stableSort = require 'stable'

{selectorsMatchScopeChain} = require('./scope-helpers')

# Deferred requires
SymbolProvider = null
FuzzyProvider =  null
grim = null
ProviderMetadata = null

module.exports =
class ProviderManager
  fuzzyProvider: null
  fuzzyRegistration: null
  store: null
  subscriptions: null
  globalBlacklist: null

  constructor: ->
    @subscriptions = new CompositeDisposable
    @globalBlacklist = new CompositeDisposable
    @providers = []
    @subscriptions.add(atom.config.observe('autocomplete-plus.enableBuiltinProvider', (value) => @toggleFuzzyProvider(value)))
    @subscriptions.add(atom.config.observe('autocomplete-plus.scopeBlacklist', (value) => @setGlobalBlacklist(value)))

  dispose: ->
    @toggleFuzzyProvider(false)
    @subscriptions?.dispose()
    @subscriptions = null
    @providers = null

  providersForScopeDescriptor: (scopeDescriptor) =>
    scopeChain = scopeChainForScopeDescriptor(scopeDescriptor)
    return [] unless scopeChain
    return [] if @globalBlacklistSelectors? and selectorsMatchScopeChain(@globalBlacklistSelectors, scopeChain)

    matchingProviders = []
    disableDefaultProvider = false
    lowestIncludedPriority = 0

    for providerMetadata in @providers
      {provider} = providerMetadata
      if providerMetadata.matchesScopeChain(scopeChain)
        matchingProviders.push(provider)
        if provider.excludeLowerPriority?
          lowestIncludedPriority = Math.max(lowestIncludedPriority, provider.inclusionPriority ? 0)
        if providerMetadata.shouldDisableDefaultProvider(scopeChain)
          disableDefaultProvider = true

    matchingProviders = _.without(matchingProviders, @fuzzyProvider) if disableDefaultProvider
    matchingProviders = (provider for provider in matchingProviders when (provider.inclusionPriority ? 0) >= lowestIncludedPriority)
    stableSort matchingProviders, (providerA, providerB) =>
      specificityA = @metadataForProvider(providerA).getSpecificity(scopeChain)
      specificityB = @metadataForProvider(providerB).getSpecificity(scopeChain)
      difference = specificityB - specificityA
      difference = (providerB.suggestionPriority ? 1) - (providerA.suggestionPriority ? 1) if difference is 0
      difference

  toggleFuzzyProvider: (enabled) =>
    return unless enabled?

    if enabled
      return if @fuzzyProvider? or @fuzzyRegistration?
      if atom.config.get('autocomplete-plus.defaultProvider') is 'Symbol'
        SymbolProvider ?= require('./symbol-provider')
        @fuzzyProvider = new SymbolProvider()
      else
        FuzzyProvider ?= require('./fuzzy-provider')
        @fuzzyProvider = new FuzzyProvider()
      @fuzzyRegistration = @registerProvider(@fuzzyProvider)
    else
      @fuzzyRegistration.dispose() if @fuzzyRegistration?
      @fuzzyProvider.dispose() if @fuzzyProvider?
      @fuzzyRegistration = null
      @fuzzyProvider = null

  setGlobalBlacklist: (globalBlacklist) =>
    @globalBlacklistSelectors = null
    if globalBlacklist?.length
      @globalBlacklistSelectors = Selector.create(globalBlacklist)

  isValidProvider: (provider, apiVersion) ->
    # TODO API: Check based on the apiVersion
    if semver.satisfies(apiVersion, '>=2.0.0')
      provider? and _.isFunction(provider.getSuggestions) and _.isString(provider.selector) and !!provider.selector.length
    else
      provider? and _.isFunction(provider.requestHandler) and _.isString(provider.selector) and !!provider.selector.length

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

    apiIs20 = semver.satisfies(apiVersion, '>=2.0.0')

    if apiIs20
      if provider.id? and provider isnt @fuzzyProvider
        grim ?= require 'grim'
        grim.deprecate """
          Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
          contains an `id` property.
          An `id` attribute on your provider is no longer necessary.
          See https://github.com/atom-community/autocomplete-plus/wiki/Provider-API
        """
      if provider.requestHandler?
        grim ?= require 'grim'
        grim.deprecate """
          Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
          contains a `requestHandler` property.
          `requestHandler` has been renamed to `getSuggestions`.
          See https://github.com/atom-community/autocomplete-plus/wiki/Provider-API
        """
      if provider.blacklist?
        grim ?= require 'grim'
        grim.deprecate """
          Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
          contains a `blacklist` property.
          `blacklist` has been renamed to `disableForSelector`.
          See https://github.com/atom-community/autocomplete-plus/wiki/Provider-API
        """

    unless @isValidProvider(provider, apiVersion)
      console.warn "Provider #{provider.constructor.name} is not valid", provider
      return

    return if @isProviderRegistered(provider)

    # TODO API: Deprecate the 1.0 APIs
    selector = provider.selector
    disabledSelector = provider.disableForSelector
    disabledSelector = provider.blacklist unless apiIs20

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
