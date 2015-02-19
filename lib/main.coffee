{Disposable} = require('atom')

module.exports =
  config:
    enableAutoActivation:
      title: 'Show Suggestions On Keystroke'
      description: 'Suggestions will show as you type if this preference is enabled. If it is disabled, you can still see suggestions by using the keymapping for autocomplete-plus:activate (shown below).'
      type: 'boolean'
      default: true
      order: 1
    autoActivationDelay:
      title: 'Delay Before Suggestions Are Shown'
      description: 'This prevents suggestions from being shown too frequently. Usually, the default works well. A lower value than the default has performance implications, and is not advised.'
      type: 'integer'
      default: 100
      order: 2
    maxSuggestions:
      title: 'Maximum Suggestions'
      description: 'The list of suggestions will be limited to this number.'
      type: 'integer'
      default: 10
      order: 3
    confirmCompletion:
      title: 'Keymap For Confirming A Suggestion'
      description: 'You should use the key(s) indicated here to confirm a suggestion from the suggestion list and have it inserted into the file.'
      type: 'string'
      default: 'tab'
      enum: ['tab', 'enter', 'tab and enter']
      order: 4
    navigateCompletions:
      title: 'Keymap For Navigating The Suggestion List'
      description: 'You should use the keys indicated here to select suggestions in the suggestion list (moving up or down).'
      type: 'string'
      default: 'up,down'
      enum: ['up,down', 'ctrl-p,ctrl-n']
      order: 5
    fileBlacklist:
      title: 'File Blacklist'
      description: 'Suggestions will not be provided for files matching this list.'
      type: 'array'
      default: ['.*']
      items:
        type: 'string'
      order: 6
    scopeBlacklist:
      title: 'Scope Blacklist'
      description: 'Suggestions will not be provided for scopes matching this list. See: https://atom.io/docs/latest/advanced/scopes-and-scope-descriptors'
      type: 'array'
      default: []
      items:
        type: 'string'
      order: 7
    includeCompletionsFromAllBuffers:
      title: 'Include Completions From All Buffers'
      description: 'For grammars with no registered provider(s), FuzzyProvider will include completions from all buffers, instead of just the buffer you are currently editing.'
      type: 'boolean'
      default: false
      order: 8
    strictMatching:
      title: 'Use Strict Matching For Built-In Provider'
      description: 'Fuzzy searching is performed if this is disabled; if it is enabled, suggestions must begin with the prefix from the current word.'
      type: 'boolean'
      default: false
      order: 9
    enableBuiltinProvider:
      title: 'Enable Built-In Provider'
      description: 'The package comes with a built-in provider that will provide suggestions using the words in your current buffer or all open buffers. You will get better suggestions by installing additional autocomplete+ providers. To stop using the built-in provider, disable this option.'
      type: 'boolean'
      default: true
      order: 10
    builtinProviderBlacklist:
      title: 'Built-In Provider Blacklist'
      description: 'Don\'t use the built-in provider for these selector(s).'
      type: 'string'
      default: '.source.gfm'
      order: 11
    backspaceTriggersAutocomplete:
      title: 'Allow Backspace To Trigger Autocomplete'
      description: 'If enabled, typing `backspace` will show the suggestion list if suggestions are available. If disabled, suggestions will not be shown while backspacing.'
      type: 'boolean'
      default: true
      order: 12
    suggestionListFollows:
      title: 'Suggestions List Follows'
      description: 'With "Cursor" the suggestion list appears at the cursor\'s position. With "Word" it appers at the beginning of the word that\'s being completed.'
      type: 'string'
      default: 'Cursor'
      enum: ['Cursor', 'Word']
      order: 13

  # Public: Creates AutocompleteManager instances for all active and future editors (soon, just a single AutocompleteManager)
  activate: ->
    run = =>
      @getAutocompleteManager()
    setTimeout(run.bind(this), 0)

  # Public: Cleans everything up, removes all AutocompleteManager instances
  deactivate: ->
    @autocompleteManager?.dispose()
    @autocompleteManager = null
    @providerManager = null

  getAutocompleteManager: ->
    if @activateTimeout?
      clearTimeout(@activateTimeout)
      @activateTimeout = null
    return @autocompleteManager if @autocompleteManager?
    AutocompleteManager = require('./autocomplete-manager')
    @autocompleteManager = new AutocompleteManager()
    @getProviderManager()
    @autocompleteManager.setProviderManager(@providerManager)
    return @autocompleteManager

  getProviderManager: ->
    return @providerManager if @providerManager?
    ProviderManager = require('./provider-manager')
    @providerManager = new ProviderManager()
    return @providerManager

  #  |||              |||
  #  vvv PROVIDER API vvv

  # Private: Consumes the given provider, from package.json configuration.
  # Do not use this directly or depend on `autocomplete-plus` directly.
  #
  # service - The service to consume
  consumeProvider: (service) ->
    return unless service?.provider?
    service.providers = [service.provider]
    return @consumeProviders(service)

  # Private: Consumes the given provider, from package.json configuration.
  # Do not use this directly or depend on `autocomplete-plus` directly.
  #
  # service - The service to consume
  consumeProviders: (service) ->
    return unless service?.providers?.length > 0
    registrations = for provider in service.providers
      @getProviderManager().registerProvider(provider)
    if registrations?.length > 0
      return new Disposable(->
        for registration in registrations
          registration?.dispose?()
      )
