{CompositeDisposable, Disposable, Emitter} = require 'event-kit'
ScopedPropertyStore = require 'scoped-property-store'
_ = require 'underscore-plus'
FuzzyProvider = require './fuzzy-provider'
Suggestion = require './suggestion'
Provider = require './provider'

module.exports =
class ProviderManager
  fuzzyProvider: null
  scopedPropertyStore: null
  subscriptions: null

  constructor: ->
    @subscriptions = new CompositeDisposable
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

  #  |||              |||
  #  vvv PROVIDER API vvv

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
    properties = {}
    properties[scope] = {provider}
    registration = @store.addProperties('autocomplete-provider-registration', properties)

    if provider.dispose?
      @subscriptions.add(provider) unless _.contains(@subscriptions?.disposables, provider)

    new Disposable =>
      console.log @providerIsRegistered(provider)
      registration.dispose()
      if _.contains(@subscriptions?.disposables, provider) and not @providerIsRegistered(provider)
        @subscriptions.remove(provider)
      console.log @providerIsRegistered(provider)

  registerProviderForEditor: (provider, editor) =>
    return unless provider?
    return unless editor?
    grammar = editor?.getGrammar()
    return unless grammar?
    return if grammar.scopeName is 'text.plain.null-grammar'
    return @registerProviderForGrammars(provider, [grammar])

  providerIsRegistered: (provider, scopes) =>
    return false unless @store?
    registrations = @store.propertiesForSource('autocomplete-provider-registration')
    return false unless _.size(registrations) > 0
    return _.chain(registrations).pluck('provider').filter((p) -> p is provider).size().value() > 0

  unregisterProviderForEditor: (provider, editor) =>
    return unless provider?
    return unless editor?
    grammar = editor?.getGrammar()
    return unless grammar?
    return @unregisterProviderForGrammars(provider, [grammar])

  # Required For Legacy API Compatibility
  unregisterProvider: (provider) =>
    return unless provider?
    @subscriptions.remove(provider) if provider.dispose? and _.contains(@subscriptions?.disposables, provider)
    # TODO: Determine how to actually filter all providers from the @store
    return

  provideApi: =>
    @subscriptions.add atom.services.provide 'autocomplete.provider-api', '0.1.0', {@registerProviderForGrammars, @registerProviderForScope, @unregisterProvider}

  # ^^^ PROVIDER API ^^^
  # |||              |||
