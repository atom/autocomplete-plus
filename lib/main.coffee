_ = require('underscore-plus')
AutocompleteManager = require('./autocomplete-manager')
Provider = require('./provider')
Suggestion = require('./suggestion')
{deprecate} = require('grim')

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
      default: ['.*', '*.md']
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

  # Public: Creates AutocompleteManager instances for all active and future editors (soon, just a single AutocompleteManager)
  activate: ->
    @autocompleteManager = new AutocompleteManager()

  # Public: Cleans everything up, removes all AutocompleteManager instances
  deactivate: ->
    @autocompleteManager?.dispose()
    @autocompleteManager = null

  registerProviderForEditorView: (provider, editorView) ->
    @registerProviderForEditor(provider, editorView?.getModel())

  # Public: Finds the autocomplete for the given TextEditor
  # and registers the given provider
  #
  # provider - The new {Provider}
  # editor - The {TextEditor} we should register the provider with
  registerProviderForEditor: (provider, editor) ->
    return unless @autocompleteManager?.providerManager?
    return unless editor?.getGrammar()?.scopeName?
    deprecate """
      registerProviderForEditor and registerProviderForEditorView are no longer supported.
      Use [service-hub](https://github.com/atom/service-hub) instead:
        ```
        # Example:
        provider =
          requestHandler: (options) ->
            # Build your suggestions here...

            # Return your suggestions as an array of anonymous objects
            [{
              word: 'ohai',
              prefix: 'ohai',
              label: '<span style="color: red">ohai</span>',
              renderLabelAsHtml: true,
              className: 'ohai'
            }]
          selector: '.source.js,.source.coffee' # This provider will be run on JavaScript and Coffee files
          dispose: ->
            # Your dispose logic here
        registration = atom.services.provide('autocomplete.provider', '1.0.0', {provider: provider})
        ```
    """
    return @autocompleteManager.providerManager.registerLegacyProvider(provider, '.' + editor?.getGrammar()?.scopeName)

  # Public: unregisters the given provider
  #
  # provider - The {Provider} to unregister
  unregisterProvider: (provider) ->
    return unless @autocompleteManager?.providerManager?
    deprecate """
      unregisterProvider is no longer supported.
      Use [service-hub](https://github.com/atom/service-hub) instead:
        ```
        # Example:
        provider =
          requestHandler: (options) ->
            # Build your suggestions here...

            # Return your suggestions as an array of anonymous objects
            [{
              word: 'ohai',
              prefix: 'ohai',
              label: '<span style="color: red">ohai</span>',
              renderLabelAsHtml: true,
              className: 'ohai'
            }]
          selector: '.source.js,.source.coffee' # This provider will be run on JavaScript and Coffee files
          dispose: ->
            # Your dispose logic here
        registration = atom.services.provide('autocomplete.provider', '1.0.0', {provider: provider})
        registration.dispose() # << unregisters your provider
        ```
    """
    @autocompleteManager.providerManager.unregisterLegacyProvider(provider)

  Provider: Provider # TODO: This is deprecated, and will be removed soon
  Suggestion: Suggestion # TODO: This is deprecated, and will be removed soon
