{CompositeDisposable, Disposable} = require 'atom'
_ = require 'underscore-plus'
semver = require 'semver'
{specificity} = require 'clear-cut'
{Selector} = require 'selector-kit'
stableSort = require 'stable'

slick = require 'atom-slick'
window.Selector = Selector

# Deferred requires
SymbolProvider = null
FuzzyProvider =  null
grim = null

escapeCharacterRegex = /[-!"#$%&'*+,/:;=?@|^~()<>{}[\]]/g
parseScopeChain = (scopeChain) ->
  scopeChain = scopeChain.replace escapeCharacterRegex, (match) -> "\\#{match[0]}"
  scope for scope in slick.parse(scopeChain)[0] ? []

selectorForScopeChain = (selectors, scopeChain) ->
  scopes = parseScopeChain(scopeChain)
  for selector in selectors
    while scopes.length > 0
      return selector if selector.matches(scopes)
      scopes.pop()
  null

selectorsMatchScopeChain = (selectors, scopeChain) ->
  selectorForScopeChain(selectors, scopeChain)?

class ProviderMetadata
  constructor: (@provider, @apiVersion) ->
    @selectors = Selector.create(@provider.selector)
    @disableForSelectors = Selector.create(@provider.disableForSelector) if @provider.disableForSelector?

    # TODO API: remove this when 1.0 is pulled out
    if providerBlacklist = @provider.providerblacklist?['autocomplete-plus-fuzzyprovider']
      @disableDefaultProviderSelectors = Selector.create(providerBlacklist)

  matchesScopeDescriptor: (scopeChain) ->
    if @disableForSelectors?
      return false if selectorsMatchScopeChain(@disableForSelectors, scopeChain)

    if selectorsMatchScopeChain(@selectors, scopeChain)
      true
    else
      false

  shouldDisableDefaultProvider: (scopeChain) ->
    if @disableDefaultProviderSelectors?
      selectorsMatchScopeChain(@disableDefaultProviderSelectors, scopeChain)
    else
      false

  getSpecificity: (scopeChain) ->
    if selector = selectorForScopeChain(@selectors, scopeChain)
      selector.getSpecificity()
    else
      0

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
    scopeChain = scopeDescriptor?.getScopeChain?() or scopeDescriptor
    return [] unless scopeChain
    return [] if @globalBlacklistSelectors? and selectorsMatchScopeChain(@globalBlacklistSelectors, scopeChain)

    matchingProviders = []
    disableDefaultProvider = false

    for providerMetadata in @providers
      {provider} = providerMetadata
      if providerMetadata.matchesScopeDescriptor(scopeChain)
        matchingProviders.push(provider)
        disableDefaultProvider = true if providerMetadata.shouldDisableDefaultProvider(scopeChain)

    matchingProviders = _.without(matchingProviders, @fuzzyProvider) if disableDefaultProvider

    matchingProviders = stableSort matchingProviders, (providerA, providerB) =>
      specificityA = @metadataForProvider(providerA).getSpecificity(scopeChain)
      specificityB = @metadataForProvider(providerB).getSpecificity(scopeChain)
      difference = specificityB - specificityA

      if difference isnt 0
        difference
      else
        (providerB.suggestionPriority ? 1) - (providerA.suggestionPriority ? 1)

    lowestIncludedPriority = 0
    for provider in matchingProviders
      if provider.excludeLowerPriority?
        lowestIncludedPriority = Math.max(lowestIncludedPriority, provider.inclusionPriority ? 0)
    (provider for provider in matchingProviders when (provider.inclusionPriority ? 0) >= lowestIncludedPriority)

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
    @providers.push new ProviderMetadata(provider, apiVersion)
    @subscriptions.add(provider) if provider.dispose?

  removeProvider: (provider) =>
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

    return unless @isValidProvider(provider, apiVersion)
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
