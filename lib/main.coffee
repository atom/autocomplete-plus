{CompositeDisposable} = require 'atom'

module.exports =
  autocompleteManager: null
  subscriptions: null

  # Public: Creates AutocompleteManager instances for all active and future editors (soon, just a single AutocompleteManager)
  activate: ->
    @subscriptions = new CompositeDisposable
    @requireAutocompleteManagerAsync()

  # Public: Cleans everything up, removes all AutocompleteManager instances
  deactivate: ->
    @subscriptions?.dispose()
    @subscriptions = null
    @autocompleteManager = null

  requireAutocompleteManagerAsync: (callback) ->
    if @autocompleteManager?
      callback?(@autocompleteManager)
    else
      setImmediate =>
        autocompleteManager = @getAutocompleteManager()
        callback?(autocompleteManager)

  getAutocompleteManager: ->
    unless @autocompleteManager?
      AutocompleteManager = require './autocomplete-manager'
      @autocompleteManager = new AutocompleteManager()
      @subscriptions.add(@autocompleteManager)
    @autocompleteManager

  consumeSnippets: (snippetsManager) ->
    @requireAutocompleteManagerAsync (autocompleteManager) ->
      autocompleteManager.setSnippetsManager(snippetsManager)

  ###
  Section: Provider API
  ###

  # 1.0.0 API
  # service - {provider: provider1}
  consumeProvider_1_0: (service) ->
    # TODO API: Deprecate, tell them to upgrade to 2.1
    return unless service?.provider?
    @consumeProvider([service.provider], '1.0.0')

  # 1.1.0 API
  # service - {providers: [provider1, provider2, ...]}
  consumeProvider_1_1: (service) ->
    # TODO API: Deprecate, tell them to upgrade to 2.1
    @consumeProvider(service?.providers, '1.1.0')

  # 2.0.0 API
  # providers - either a provider or a list of providers
  consumeProvider_2_0: (providers) ->
    @consumeProvider(providers, '2.0.0')

  # 2.1.0 API
  # providers - either a provider or a list of providers
  consumeProvider_2_1: (providers) ->
    @consumeProvider(providers, '2.1.0')

  consumeProvider: (providers, apiVersion='2.1.0') ->
    providers = [providers] if providers? and not Array.isArray(providers)
    return unless providers?.length > 0
    registrations = new CompositeDisposable
    @requireAutocompleteManagerAsync (autocompleteManager) ->
      for provider in providers
        registrations.add autocompleteManager.providerManager.registerProvider(provider, apiVersion)
      return
    registrations
