{CompositeDisposable, Disposable, Emitter} = require 'event-kit'
ScopedPropertyStore = require 'scoped-property-store'
_ = require 'underscore-plus'
Uuid = require 'node-uuid'
FuzzyProvider = require './fuzzy-provider'
Suggestion = require './suggestion'
Provider = require './provider'

module.exports =
class ProviderManager
  fuzzyProvider: null
  fuzzyRegistration: null
  store: null
  subscriptions: null
  legacyProviderRegistrations: null
  globalBlacklist: null

  constructor: ->
    @subscriptions = new CompositeDisposable
    @globalBlacklist = new CompositeDisposable
    @legacyProviderRegistrations = new WeakMap()
    @providers = new Map()
    @store = new ScopedPropertyStore
    @subscriptions.add(atom.config.observe('autocomplete-plus.enableBuiltinProvider', (value) => @toggleFuzzyProvider(value)))
    @subscriptions.add(atom.config.observe('autocomplete-plus.scopeBlacklist', (value) => @setGlobalBlacklist(value)))
    @consumeApi()

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
    @legacyProviderRegistrations = null

  providersForScopeChain: (scopeChain) =>
    return [] unless scopeChain?
    return [] unless @store?
    providers = []
    return [] if _.contains(@blacklist, scopeChain) # Check Blacklist For Exact Match
    providers = @store.getAll(scopeChain)

    # Check Global Blacklist For Match With Selector
    blacklist = _.chain(providers).map((p) -> p.value.globalBlacklist).filter((p) -> p? and p is true).value()
    return [] if blacklist? and blacklist.length

    # Determine Blacklisted Providers
    blacklistedProviders = _.chain(providers).filter((p) -> p.value.blacklisted? and p.value.blacklisted is true).map((p) -> p.value.provider).value()

    # Exclude Blacklisted Providers
    providers = _.chain(providers).filter((p) -> not p.value.blacklisted?).sortBy((p) -> -p.scopeSelector.length).map((p) -> p.value.provider).uniq().difference(blacklistedProviders).value()
    providers

  toggleFuzzyProvider: (enabled) =>
    return unless enabled?

    if enabled
      return if @fuzzyProvider? or @fuzzyRegistration?
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

  addProvider: (provider) =>
    return unless @isValidProvider(provider)
    @providers.set(provider, Uuid.v4()) unless @providers.has(provider)
    @subscriptions.add(provider) if provider.dispose? and not _.contains(@subscriptions?.disposables, provider)

  isValidProvider: (provider) =>
    return provider? and provider.requestHandler? and typeof provider.requestHandler is 'function' and provider.selector? and provider.selector isnt '' and provider.selector isnt false

  isLegacyProvider: (provider) =>
    return provider? and provider instanceof Provider

  providerUuid: (provider) =>
    return false unless provider?
    return false unless @providers.has(provider)
    @providers.get(provider)

  removeProvider: (provider) =>
    return unless @isValidProvider(provider)
    @providers.delete(provider) if @providers?.has(provider)
    @subscriptions.remove(provider) if provider.dispose? and _.contains(@subscriptions?.disposables, provider)

  #  |||              |||
  #  vvv PROVIDER API vvv

  consumeApi: =>
    @subscriptions.add atom.services.consume 'autocomplete.provider', '1.0.0', (provider) =>
      return unless provider?.provider?
      return @registerProvider(provider.provider)

  registerProvider: (provider) =>
    # Check Validity Of Provider
    return unless @isValidProvider(provider)
    @addProvider(provider)
    id = @providerUuid(provider)
    @removeProvider(provider) unless id?
    return unless id?

    # Register Provider
    selectors = provider.selector.split(',')
    selectors = _.reject selectors, (s) =>
      p = @store.propertiesForSourceAndSelector(id, s)
      return p? and p.provider?

    return unless selectors.length

    properties = {}
    properties[selectors.join(',')] = {provider}
    registration = @store.addProperties(id, properties)
    blacklistRegistration = null

    # Register Provider's Blacklist (If Present)
    if provider.blacklist? and provider.blacklist.length
      blacklistid = id + '-blacklist'
      blacklist = provider.blacklist.split(',')
      blacklist = _.reject blacklist, (s) =>
        p = @store.propertiesForSourceAndSelector(blacklistid, s)
        return p? and p.provider?

      if blacklist.length
        blacklistproperties = {}
        blacklistproperties[blacklist.join(',')] = {provider, blacklisted: true}
        blacklistRegistration = @store.addProperties(blacklistid, blacklistproperties)

    if provider.dispose?
      provider.dispose = _.wrap provider.dispose, (f) =>
        f?()
        registration?.dispose()
        blacklistRegistration?.dispose()
        @removeProvider(provider)

    new Disposable =>
      registration?.dispose()
      blacklistRegistration?.dispose()
      @removeProvider(provider)

  # ^^^ PROVIDER API ^^^
  # |||              |||

  # For Legacy use only!!
  registerLegacyProvider: (legacyProvider, selector) =>
    return unless legacyProvider?
    return unless selector? and selector.trim() isnt ''

    legacyProviderRegistration = @legacyProviderRegistrations.get(legacyProvider.constructor)

    if legacyProviderRegistration
      legacyProviderRegistration.service.dispose()
      legacyProviderRegistration.selectors.push(selector) if legacyProviderRegistration.selectors.indexOf(selector) < 0

    else
      legacyProviderRegistration = {selectors: [selector]}
      @legacyProviderRegistrations.set(legacyProvider.constructor, legacyProviderRegistration)

    selector = legacyProviderRegistration.selectors.join(',')

    legacyProviderRegistration.shim = @shimLegacyProvider(legacyProvider, selector)
    legacyProviderRegistration.service = @registerProvider(legacyProviderRegistration.shim)
    return legacyProviderRegistration.service

  shimLegacyProvider: (legacyProvider, selector) =>
    unless legacyProvider.buildSuggestionsShim
      legacyProvider.buildSuggestionsShim = Provider.prototype.buildSuggestionsShim
    shim =
      legacyProvider: legacyProvider
      requestHandler: legacyProvider.buildSuggestionsShim
      selector: selector
      dispose: ->
        requestHandler = null
        legacyProvider.dispose() if legacyProvider.dispose?
        legacyProvider = null
        selector = null
    shim

  unregisterLegacyProvider: (legacyProvider) =>
    return unless legacyProvider?
    legacyProviderRegistration = @legacyProviderRegistrations.get(legacyProvider.constructor)
    if legacyProviderRegistration
      legacyProviderRegistration.service.dispose()
      @legacyProviderRegistrations.delete(legacyProvider.constructor)
