{CompositeDisposable} = require 'atom'

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
    maxVisibleSuggestions:
      title: 'Maximum Visible Suggestions'
      description: 'The suggestion list will only show this many suggestions.'
      type: 'integer'
      default: 10
      minimum: 1
      order: 3
    confirmCompletion:
      title: 'Keymap For Confirming A Suggestion'
      description: 'You should use the key(s) indicated here to confirm a suggestion from the suggestion list and have it inserted into the file.'
      type: 'string'
      default: 'tab'
      enum: ['tab', 'enter', 'tab and enter']
      order: 4
    fileBlacklist:
      title: 'File Blacklist'
      description: 'Suggestions will not be provided for files matching this list.'
      type: 'array'
      default: ['.*']
      items:
        type: 'string'
      order: 5
    scopeBlacklist:
      title: 'Scope Blacklist'
      description: 'Suggestions will not be provided for scopes matching this list. See: https://atom.io/docs/latest/behind-atom-scoped-settings-scopes-and-scope-descriptors'
      type: 'array'
      default: []
      items:
        type: 'string'
      order: 6
    includeCompletionsFromAllBuffers:
      title: 'Include Completions From All Buffers'
      description: 'For grammars with no registered provider(s), the default provider will include completions from all buffers, instead of just the buffer you are currently editing.'
      type: 'boolean'
      default: false
      order: 7
    strictMatching:
      title: 'Use Strict Matching For Built-In Provider'
      description: 'Fuzzy searching is performed if this is disabled; if it is enabled, suggestions must begin with the prefix from the current word.'
      type: 'boolean'
      default: false
      order: 8
    minimumWordLength:
      description: "Only autocomplete when you've typed at least this many characters."
      type: 'integer'
      default: 3
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
      default: false
      order: 12
    suggestionListFollows:
      title: 'Suggestions List Follows'
      description: 'With "Cursor" the suggestion list appears at the cursor\'s position. With "Word" it appears at the beginning of the word that\'s being completed.'
      type: 'string'
      default: 'Word'
      enum: ['Word', 'Cursor']
      order: 13
    defaultProvider:
      description: 'Using the Symbol provider is experimental. You must reload Atom to use a new provider after changing this option.'
      type: 'string'
      default: 'Fuzzy'
      enum: ['Fuzzy', 'Symbol']
      order: 14
    suppressActivationForEditorClasses:
      title: 'Suppress Activation For Editor Classes'
      description: 'Don\'t auto-activate when any of these classes are present in the editor.'
      type: 'array'
      default: ['vim-mode.command-mode', 'vim-mode.visual-mode', 'vim-mode.operator-pending-mode']
      items:
        type: 'string'
      order: 15

  autocompleteManager: null
  subscriptions: null

  # Public: Creates AutocompleteManager instances for all active and future editors (soon, just a single AutocompleteManager)
  activate: ->
    @subscriptions = new CompositeDisposable
    setImmediate =>
      @getAutocompleteManager()

  # Public: Cleans everything up, removes all AutocompleteManager instances
  deactivate: ->
    @subscriptions?.dispose()
    @subscriptions = null
    @autocompleteManager = null

  getAutocompleteManager: ->
    unless @autocompleteManager?
      AutocompleteManager = require './autocomplete-manager'
      @autocompleteManager = new AutocompleteManager()
      @subscriptions.add(@autocompleteManager)
    @autocompleteManager

  consumeSnippets: (snippetsManager) ->
    @getAutocompleteManager().setSnippetsManager(snippetsManager)

  ###
  Section: Provider API
  ###

  # 1.0.0 API
  # service - {provider: provider1}
  consumeProviderLegacy: (service) ->
    # TODO API: Deprecate, tell them to upgrade to 2.0
    return unless service?.provider?
    @consumeProvider([service.provider], '1.0.0')

  # 1.1.0 API
  # service - {providers: [provider1, provider2, ...]}
  consumeProvidersLegacy: (service) ->
    # TODO API: Deprecate, tell them to upgrade to 2.0
    @consumeProvider(service?.providers, '1.1.0')

  # 2.0.0 API
  # providers - either a provider or a list of providers
  consumeProvider: (providers, apiVersion='2.0.0') ->
    providers = [providers] if providers? and not Array.isArray(providers)
    return unless providers?.length > 0
    registrations = new CompositeDisposable
    for provider in providers
      registrations.add @getAutocompleteManager().providerManager.registerProvider(provider, apiVersion)
    registrations
