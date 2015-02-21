{CompositeDisposable, Disposable, Emitter} = require('atom')
ScopedPropertyStore = require('scoped-property-store')
_ = require('underscore-plus')
Uuid = require('node-uuid')
SymbolProvider = require('./symbol-provider')
FuzzyProvider = require('./fuzzy-provider')

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
    fuzzyProviderBlacklisted = _.chain(providers).filter((p) -> p.value.providerblacklisted? and p.value.providerblacklisted is 'autocomplete-plus-fuzzyprovider').map((p) -> p.value.provider).value() if @fuzzyProvider?

    # Exclude Blacklisted Providers
    providers = _.chain(providers).filter((p) -> not p.value.blacklisted?).sortBy((p) -> -p.scopeSelector.length).map((p) -> p.value.provider).uniq().difference(blacklistedProviders).value()
    providers = _.without(providers, @fuzzyProvider) if fuzzyProviderBlacklisted? and fuzzyProviderBlacklisted.length and @fuzzyProvider?
    providers

  toggleFuzzyProvider: (enabled) =>
    return unless enabled?

    if enabled
      return if @fuzzyProvider? or @fuzzyRegistration?
      if atom.config.get('autocomplete-plus.defaultProvider') is 'Symbol'
        @fuzzyProvider = new SymbolProvider()
      else
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

  isValidProvider: (provider) ->
    return provider? and provider.requestHandler? and typeof provider.requestHandler is 'function' and provider.selector? and provider.selector isnt '' and provider.selector isnt false

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
    if provider.blacklist?.length
      blacklistid = id + '-blacklist'
      blacklist = provider.blacklist.split(',')
      blacklist = _.reject blacklist, (s) =>
        p = @store.propertiesForSourceAndSelector(blacklistid, s)
        return p? and p.provider? and p.blacklisted? and p.blacklisted

      if blacklist.length
        blacklistproperties = {}
        blacklistproperties[blacklist.join(',')] = {provider, blacklisted: true}
        blacklistRegistration = @store.addProperties(blacklistid, blacklistproperties)

    # Register Provider's Provider Blacklist (If Present)
    # TODO: Support Providers Other Than SymbolProvider
    if provider.providerblacklist?['autocomplete-plus-fuzzyprovider']?.length
      providerblacklistid = id + '-providerblacklist'
      providerblacklist = provider.providerblacklist['autocomplete-plus-fuzzyprovider'].split(',')
      providerblacklist = _.reject providerblacklist, (s) =>
        p = @store.propertiesForSourceAndSelector(providerblacklistid, s)
        return p? and p.provider? and p.providerblacklisted? and p.providerblacklisted is 'autocomplete-plus-fuzzyprovider'

      if providerblacklist.length
        providerblacklistproperties = {}
        providerblacklistproperties[providerblacklist.join(',')] = {provider, providerblacklisted: 'autocomplete-plus-fuzzyprovider'}
        providerblacklistRegistration = @store.addProperties(providerblacklistid, providerblacklistproperties)

    if provider.dispose?
      provider.dispose = _.wrap provider.dispose, (f) =>
        f?()
        registration?.dispose()
        blacklistRegistration?.dispose()
        providerblacklistRegistation?.dispose()
        @removeProvider(provider)

    new Disposable(=>
      registration?.dispose()
      blacklistRegistration?.dispose()
      providerblacklistRegistation?.dispose()
      @removeProvider(provider)
    )

  # ^^^ PROVIDER API ^^^
  # |||              |||
