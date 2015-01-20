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
    @subscriptions.add(@fuzzyProvider)
    fuzzyRegistration = @registerProviderForScope(@fuzzyProvider, '*')
    @subscriptions.add(fuzzyRegistration) if fuzzyRegistration?
    @provideApi()

  dispose: ->
    @subscriptions?.dispose()
    @subscriptions = null
    @store = null
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

  addLegacyProvider: (provider) =>
    # TODO: Shim to anonymous object here, to make legacy Provider work correctly

  isValidProvider: (provider) =>
    return provider? and provider.requestHandler? and typeof provider.requestHandler is 'function' and provider.selector? and provider.selector isnt '' and provider.selector isnt false

  isLegacyProvider: (provider) =>
    return provider? and provider instanceof Provider

  removeProvider: (provider) =>
    return unless @isValidProvider(provider)
    @providers.delete(provider) if @providers.has(provider)
    @subscriptions.remove(provider) if provider.dispose? and _.contains(@subscriptions?.disposables, provider)

  #  |||              |||
  #  vvv PROVIDER API vvv

  provideApi: =>
    @subscriptions.add atom.services.provide 'autocomplete.provider-api', '0.1.0', {@registerProviderForGrammars, @registerProviderForScope, @unregisterProvider}

  registerProviderForGrammars: (provider, grammars) =>
    return unless provider?
    return unless grammars? and _.size(grammars) > 0
    grammars = _.filter(grammars, (grammar) -> grammar?.scopeName?)
    scope = _.pluck(grammars, 'scopeName')
    scope = scope.join(',.')
    scope = '.' + scope
    return @registerProviderForScope(provider, scope)

  registerProviderForScope: (provider, scope) =>
    return unless provider?
    return unless scope?
    return if _.contains(@providersForScopeChain(scope), provider)
    properties = {}
    properties[scope] = {provider}
    registration = @store.addProperties('autocomplete-provider-registration', properties)

    if provider.dispose?
      @subscriptions.add(provider) unless _.contains(@subscriptions?.disposables, provider)

    new Disposable =>
      registration.dispose()
      if _.contains(@subscriptions?.disposables, provider) and not @providerIsRegistered(provider)
        @subscriptions.remove(provider)

  providerIsRegistered: (provider) =>
    return false unless @store?
    registrations = @store.propertiesForSource('autocomplete-provider-registration')
    return false unless _.size(registrations) > 0
    return _.chain(registrations).pluck('provider').filter((p) -> p is provider).size().value() > 0

  unregisterProvider: (provider) =>
    return unless provider?
    @subscriptions.remove(provider) if provider.dispose? and _.contains(@subscriptions?.disposables, provider)
    # TODO: Determine how to actually filter all providers from the @store
    return

  # ^^^ PROVIDER API ^^^
  # |||              |||
