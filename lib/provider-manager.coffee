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
  store: null
  subscriptions: null

  constructor: ->
    @subscriptions = new CompositeDisposable
    @providers = new Map()
    @store = new ScopedPropertyStore
    @fuzzyProvider = new FuzzyProvider()
    fuzzyRegistration = @registerProvider(@fuzzyProvider)
    @subscriptions.add(fuzzyRegistration) if fuzzyRegistration?
    @consumeApi()

  dispose: ->
    @subscriptions?.dispose()
    @subscriptions = null
    @store?.cache = {}
    @store?.propertySets = []
    @store = null
    @providers?.clear()
    @providers = null
    @fuzzyProvider = null

  providersForScopeChain: (scopeChain) =>
    return [] unless scopeChain?
    return [] unless @store?
    providers = []
    providers = @store.getAll(scopeChain, 'provider')
    return [] unless providers? and _.size(providers) > 0
    providers = _.pluck(providers, 'value')
    providers

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
    @providers.delete(provider) if @providers.has(provider)
    @subscriptions.remove(provider) if provider.dispose? and _.contains(@subscriptions?.disposables, provider)

  #  |||              |||
  #  vvv PROVIDER API vvv

  consumeApi: =>
    @subscriptions.add atom.services.consume 'autocomplete.provider', '0.1.0', (provider) =>
      return unless provider?.provider?
      return @registerProvider(provider.provider)

  # For Legacy use only!!
  registerLegacyProvider: (provider, selector) =>
    return unless provider?
    return unless selector? and selector.trim() isnt ''
    shim = @shimLegacyProvider(provider, selector)
    return @registerProvider(shim)

  shimLegacyProvider: (legacyProvider, selector) =>
    if @providers.has(legacyProvider)
      existingProvider = @providers.get(legacyProvider)
      return existingProvider if selector is existingProvider.selector
      selector = existingProvider.selector + ' ' + selector
      removeProvider(@providers.get(legacyProvider))
      existingProvider = null

    shim =
      requestHandler: legacyProvider.buildSuggestionsShim
      selector: selector
      dispose: ->
        legacyProvider.dispose() if legacyProvider.dispose?
        legacyProvider = null
        selector = null
    @providers.set(legacyProvider, shim)
    shim

  unregisterLegacyProvider: (provider) =>
    return unless provider?
    return unless @providers.has(provider)
    shim = @providers.get(provider)
    @providers.delete(provider)
    @unregisterProvider(shim)

  registerProvider: (provider) =>
    return unless @isValidProvider(provider)
    @addProvider(provider)
    id = @providerUuid(provider)
    @removeProvider(provider) unless id?
    return unless id?
    selectors = provider.selector.split(',')
    selectors = _.reject selectors, (s) =>
      p = @store.propertiesForSourceAndSelector(id, s)
      return p? and p.provider?
    properties = {}
    properties[selectors.join(',')] = {provider}
    registration = @store.addProperties(id, properties)

    new Disposable =>
      registration.dispose()
      unless @providerIsRegistered(provider)
        @removeProvider(provider)

  providerIsRegistered: (provider) =>
    return false unless @store?
    registrations = @store.propertiesForSource('autocomplete-provider-registration')
    return false unless _.size(registrations) > 0
    return _.chain(registrations).pluck('provider').filter((p) -> p is provider).size().value() > 0

  unregisterProvider: (provider) =>
    return unless provider?
    return unless @providers.has(provider)
    id = @providers.get(provider)
    return unless id?
    @store.removePropertiesForSource(id)
    @subscriptions.remove(provider) if provider.dispose? and _.contains(@subscriptions?.disposables, provider)
    @providers.delete(provider)
    return

  # ^^^ PROVIDER API ^^^
  # |||              |||
