_ = require 'underscore-plus'
AutocompleteManager = require './autocomplete-manager'
Provider = require './provider'
Suggestion = require './suggestion'
{deprecate} = require 'grim'

module.exports =
  config:
    enableAutoActivation:
      title: 'Show Suggestions On Keystroke'
      description: 'Suggestions will show as you type if this preference is enabled. If it is disabled, you can still see suggestions by using the keybinding for autocomplete-plus:activate (shown below).'
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
      title: 'Keybinding(s) For Confirming A Suggestion'
      description: 'You should use the key(s) indicated here to confirm a suggestion from the suggestion list and have it inserted into the file.'
      type: 'string'
      default: 'tab'
      enum: ['tab', 'enter', 'tab and enter']
      order: 4
    navigateCompletions:
      title: 'Keybindings For Navigating The Suggestion List'
      description: 'You should use the keys indicated here to select suggestions in the suggestion list (moving up or down).'
      type: 'string'
      default: 'up,down'
      enum: ['up,down', 'ctrl-p,ctrl-n']
      order: 5
    fileBlacklist:
      title: 'File Blacklist'
      description: 'Suggestions will not be provided for files matching this list.'
      type: 'string'
      default: '.*, *.md'
      order: 6
    scopeBlacklist:
      title: 'Scope Blacklist'
      description: 'Suggestions will not be provided for scopes matching this list. See: https://atom.io/docs/latest/advanced/scopes-and-scope-descriptors'
      type: 'string'
      default: ''
      order: 7
    includeCompletionsFromAllBuffers:
      title: 'Include Completions From All Buffers'
      description: 'For grammars with no registered provider(s), FuzzyProvider will include completions from all buffers, instead of just the buffer you are currently editing.'
      type: 'boolean'
      default: false
      order: 8

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
    deprecate """
      registerProviderForEditor and registerProviderForEditorView are no longer supported.
      Use [service-hub](https://github.com/atom/service-hub) instead:
        ```
        # Backward-compatible example:
        disposable = atom.services.consume "autocomplete.provider-api", "1.0.0", (a) ->
          testProvider = new TestProvider(editor)
          a.registerProviderForEditor(testProvider, editor) # Note that this is a deprecated API, you should update to v2.0.0.
        ```
    """
    # No-Op: Determine If We Will Temporarily Provide Legacy API
    # return @autocompleteManager.providerManager.registerProviderForEditor(provider, editor)
    return null

  # Public: unregisters the given provider
  #
  # provider - The {Provider} to unregister
  unregisterProvider: (provider) ->
    return unless @autocompleteManager?.providerManager?
    deprecate """
      unregisterProvider is no longer supported.
      Use [service-hub](https://github.com/atom/service-hub) instead:
        ```
        disposable = atom.services.consume "autocomplete.provider-api", "1.0.0", (a) ->
          a.unregisterProvider(testProvider)
        ```
    """
    # No-Op: Determine If We Will Temporarily Provide Legacy API
    # @autocompleteManager.providerManager.unregisterProvider(provider)
    return null

  Provider: Provider # TODO: Remove
  Suggestion: Suggestion # TODO: Remove
