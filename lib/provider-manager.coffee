{CompositeDisposable, Disposable, Emitter} = require 'event-kit'
_ = require 'underscore-plus'
FuzzyProvider = require './fuzzy-provider'
Suggestion = require './suggestion'
Provider = require './provider'

module.exports =
class ProviderManager
  fuzzyProvider: null
  scopes: null
  subscriptions: null

  constructor: ->
    @subscriptions = new CompositeDisposable
    @scopes = {}
    @fuzzyProvider = new FuzzyProvider()
    @subscriptions.add(@fuzzyProvider)
    @provideApi()

  dispose: ->
    @subscriptions?.dispose()
    @subscriptions = null
    @fuzzyProvider = null
    @scopes = null

  providersForScopes: (scopes) =>
    return [] unless scopes?
    return [] unless @scopes
    providers = []
    for scope in scopes
      if @scopes[scope]?
        providers = _.union(providers, @scopes[scope])
    providers.push(@fuzzyProvider) unless _.size(providers) > 0
    providers

  #  |||              |||
  #  vvv PROVIDER API vvv

  registerProviderForGrammars: (provider, grammars) =>
    return unless provider?
    return unless grammars? and _.size(grammars) > 0
    grammars = _.filter(grammars, (grammar) -> grammar?.scopeName?)
    scopes = _.pluck(grammars, 'scopeName')
    return @registerProviderForScopes(provider, scopes)

  registerProviderForScopes: (provider, scopes) =>
    return unless provider?
    return unless scopes? and _.size(scopes) > 0
    for scope in scopes
      existing = _.findWhere(_.keys(@scopes), scope)
      if existing? and @scopes[scope]?
        @scopes[scope].push(provider)
        @scopes[scope] = _.uniq(@scopes[scope])
      else
        @scopes[scope] = [provider]

    if provider.dispose?
      @subscriptions.add(provider) unless _.contains(@subscriptions, provider)

    new Disposable =>
      @unregisterProviderForScopes(provider, scopes)

  registerProviderForEditor: (provider, editor) =>
    return unless provider?
    return unless editor?
    grammar = editor?.getGrammar()
    return unless grammar?
    return if grammar.scopeName is 'text.plain.null-grammar'
    return @registerProviderForGrammars(provider, [grammar])

  unregisterProviderForGrammars: (provider, grammars) =>
    return unless provider?
    return unless grammars? and _.size(grammars) > 0
    grammars = _.filter(grammars, (grammar) -> grammar?.scopeName?)
    scopes = _.pluck(grammars, 'scopeName')
    return @unregisterProviderForScopes(provider, scopes)

  unregisterProviderForScopes: (provider, scopes) =>
    return unless provider?
    return unless scopes? and _.size(scopes) > 0

    for scope in scopes
      existing = _.findWhere(_.keys(@scopes), scope)
      if existing?
        @scopes[scope] = _.filter(@scopes[scope], (p) -> p isnt provider)
        delete @scopes[scope] unless _.size(@scopes[scope]) > 0

    @subscriptions.remove(provider) unless @providerIsRegistered(provider)

  providerIsRegistered: (provider, scopes) =>
    # TODO: Actually determine if the provider is registered
    return true

  unregisterProviderForEditor: (provider, editor) =>
    return unless provider?
    return unless editor?
    grammar = editor?.getGrammar()
    return unless grammar?
    return @unregisterProviderForGrammars(provider, [grammar])

  unregisterProvider: (provider) =>
    return unless provider?
    return @unregisterProviderForScopes(provider, _.keys(@scopes))
    @subscriptions.remove(provider) if provider.dispose?

  provideApi: =>
    @subscriptions.add atom.services.provide 'autocomplete.provider-api', "1.0.0", {@registerProviderForEditor, @unregisterProviderForEditor, @unregisterProvider, Provider, Suggestion}
    @subscriptions.add atom.services.provide 'autocomplete.provider-api', '2.0.0', {@registerProviderForGrammars, @registerProviderForScopes, @unregisterProviderForGrammars, @unregisterProviderForScopes, @unregisterProvider}

  # ^^^ PROVIDER API ^^^
  # |||              |||
