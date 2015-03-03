{CompositeDisposable, Disposable} = require 'atom'
ScopedPropertyStore = require 'scoped-property-store'
_ = require 'underscore-plus'
semver = require 'semver'

# Deferred requires
SymbolProvider = null
FuzzyProvider =  null
grim = null

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
    @providers = new Map
    @store = new ScopedPropertyStore
    @subscriptions.add(atom.config.observe('autocomplete-plus.enableBuiltinProvider', (value) => @toggleFuzzyProvider(value)))
    @subscriptions.add(atom.config.observe('autocomplete-plus.scopeBlacklist', (value) => @setGlobalBlacklist(value)))

  dispose: ->
    @toggleFuzzyProvider(false)
    @globalBlacklist?.dispose()
    @globalBlacklist = null
    @blacklist = null
    @subscriptions?.dispose()
    @subscriptions = null
    @store?.cache = {}
    @store?.propertySets = []
    @store = null
    @providers?.clear()
    @providers = null

  providersForScopeDescriptor: (scopeDescriptor) =>
    scopeChain = scopeDescriptor?.getScopeChain?() or scopeDescriptor
    return [] unless scopeChain? and @store?
    return [] if _.contains(@blacklist, scopeChain) # Check Blacklist For Exact Match

    providers = @store.getAll(scopeChain)

    # Check Global Blacklist For Match With Selector
    blacklist = _.chain(providers).map((p) -> p.value.globalBlacklist).filter((p) -> p? and p is true).value()
    return [] if blacklist? and blacklist.length

    # Determine Blacklisted Providers
    blacklistedProviders = _.chain(providers).filter((p) -> p.value.blacklisted? and p.value.blacklisted is true).map((p) -> p.value.provider).value()

    # TODO API: Remove this when 1.0 API is removed
    fuzzyProviderBlacklisted = _.chain(providers).filter((p) -> p.value.providerblacklisted? and p.value.providerblacklisted is 'autocomplete-plus-fuzzyprovider').map((p) -> p.value.provider).value() if @fuzzyProvider?

    providers = _.chain(providers)
      .sortBy((p) -> -p.scopeSelector.length) # Sort by a bad proxy for 'specificity'
      .map((p) -> p.value.provider)
      .uniq()
      .difference(blacklistedProviders) # Exclude Blacklisted Providers
      .value()
    providers = _.without(providers, @fuzzyProvider) if fuzzyProviderBlacklisted? and fuzzyProviderBlacklisted.length and @fuzzyProvider?

    lowestIncludedPriority = 0
    for provider in providers
      if provider.excludeLowerPriority?
        lowestIncludedPriority = Math.max(lowestIncludedPriority, provider.inclusionPriority ? 0)

    (provider for provider in providers when (provider.inclusionPriority ? 0) >= lowestIncludedPriority)

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

  setGlobalBlacklist: (@blacklist) =>
    @globalBlacklist.dispose() if @globalBlacklist?
    @globalBlacklist = new CompositeDisposable
    @blacklist = [] unless @blacklist?
    return unless @blacklist.length
    properties = {}
    properties[blacklist.join(',')] = {globalBlacklist: true}
    registration = @store.addProperties('globalblacklist', properties)
    @globalBlacklist.add(registration)

  isValidProvider: (provider, apiVersion) ->
    # TODO API: Check based on the apiVersion
    if semver.satisfies(apiVersion, '>=2.0.0')
      provider? and _.isFunction(provider.getSuggestions) and _.isString(provider.selector) and !!provider.selector.length
    else
      provider? and _.isFunction(provider.requestHandler) and _.isString(provider.selector) and !!provider.selector.length

  apiVersionForProvider: (provider) =>
    @providers.get(provider)

  isProviderRegistered: (provider) ->
    @providers.has(provider)

  addProvider: (provider, apiVersion='2.0.0') =>
    return if @isProviderRegistered(provider)
    @providers.set(provider, apiVersion)
    @subscriptions.add(provider) if provider.dispose?

  removeProvider: (provider) =>
    @providers?.delete(provider)
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

    return unless @isValidProvider(provider, apiVersion)
    return if @isProviderRegistered(provider)

    # TODO API: Deprecate the 1.0 APIs
    selector = provider.selector
    disabledSelector = provider.disableForSelector
    disabledSelector = provider.blacklist unless apiIs20

    @addProvider(provider, apiVersion)

    properties = {}
    properties[selector] = {provider}
    registration = @store.addProperties(null, properties)

    # Register Provider's Blacklist (If Present)
    blacklistRegistration = null
    if disabledSelector?.length
      blacklistproperties = {}
      blacklistproperties[disabledSelector] = {provider, blacklisted: true}
      blacklistRegistration = @store.addProperties(null, blacklistproperties)

    # TODO API: Remove providerblacklist stuff when 1.0 API is removed
    providerblacklistRegistration = null
    if provider.providerblacklist?['autocomplete-plus-fuzzyprovider']?.length
      providerblacklist = provider.providerblacklist['autocomplete-plus-fuzzyprovider']
      if providerblacklist.length
        providerblacklistproperties = {}
        providerblacklistproperties[providerblacklist] = {provider, providerblacklisted: 'autocomplete-plus-fuzzyprovider'}
        providerblacklistRegistration = @store.addProperties(null, providerblacklistproperties)

    disposable = new Disposable =>
      # TODO API: Remove this when 1.0 API is removed
      providerblacklistRegistation?.dispose()

      registration?.dispose()
      blacklistRegistration?.dispose()
      @removeProvider(provider)

    # When the provider is disposed, remove its registration
    if originalDispose = provider.dispose
      provider.dispose = ->
        originalDispose.call(provider)
        disposable.dispose()

    disposable
