_ = require 'underscore-plus'
AutocompleteManager = require './autocomplete-manager'
SelectListElement = require './select-list-element'
Provider = require './provider'
Suggestion = require './suggestion'
{deprecate} = require 'grim'

module.exports =
  config:
    enableAutoActivation:
      title: 'Show Suggestions On Keystroke'
      description: 'Suggestions will show as you type if this preference is enabled. If it is disabled, you can still see suggestions by using the keybinding for autocomplete-plus:activate (shown below).'
      type: "boolean"
      default: true
      order: 1
    autoActivationDelay:
      title: 'Delay Before Suggestions Are Shown'
      description: 'This prevents suggestions from being shown too frequently. Usually, the default works well. A lower value than the default has performance implications, and is not advised.'
      type: "integer"
      default: 100
      order: 2
    maxSuggestions:
      title: 'Maximum Suggestions'
      description: 'The list of suggestions will be limited to this number.'
      type: "integer"
      default: 10
      order: 3
    confirmCompletion:
      title: 'Keybinding(s) For Confirming A Suggestion'
      description: 'You should use the key(s) indicated here to confirm a suggestion from the suggestion list and have it inserted into the file.'
      type: "string"
      default: "tab"
      enum: ["tab", "enter", "tab and enter"]
      order: 4
    navigateCompletions:
      title: 'Keybindings For Navigating The Suggestion List'
      description: 'You should use the keys indicated here to select suggestions in the suggestion list (moving up or down).'
      type: "string"
      default: "up,down"
      enum: ["up,down", "ctrl-p,ctrl-n"]
      order: 5
    fileBlacklist:
      type: "string"
      default: ".*, *.md"
      order: 90
    includeCompletionsFromAllBuffers:
      type: "boolean"
      default: false
      order: 100

  autocompleteManagers: []
  editorSubscription: null

  # Public: Creates AutocompleteManager instances for all active and future editors (soon, just a single AutocompleteManager)
  activate: ->

    atom.views.addViewProvider(AutocompleteManager, (model) =>
      element = new SelectListElement()
      element.setModel(model)
      element
    )

    @editorSubscription = atom.workspace.observeTextEditors (editor) =>
      autocompleteManager = new AutocompleteManager(editor)

      editor.onDidDestroy =>
        autocompleteManager.dispose()
        _.remove(@autocompleteManagers, autocompleteManager)

      @autocompleteManagers.push(autocompleteManager)

  # Public: Cleans everything up, removes all AutocompleteManager instances
  deactivate: ->
    @editorSubscription?.dispose()
    @editorSubscription = null
    @autocompleteManagers.forEach((autocompleteManager) -> autocompleteManager.dispose())
    @autocompleteManagers = []

  registerProviderForEditorView: (provider, editorView) ->
    deprecate('Use of editorView is deprecated, use registerProviderForEditor instead')
    @registerProviderForEditor(provider, editorView?.getModel())

  # Public: Finds the autocomplete for the given TextEditor
  # and registers the given provider
  #
  # provider - The new {Provider}
  # editor - The {TextEditor} we should register the provider with
  registerProviderForEditor: (provider, editor) ->
    return unless provider?
    return unless editor?
    autocompleteManager = _.findWhere(@autocompleteManagers, editor: editor)
    unless autocompleteManager?
      throw new Error("Could not register provider", provider.constructor.name)

    autocompleteManager.registerProvider(provider)

  # Public: unregisters the given provider
  #
  # provider - The {Provider} to unregister
  unregisterProvider: (provider) ->
    autocompleteManager.unregisterProvider provider for autocompleteManager in @autocompleteManagers

  Provider: Provider
  Suggestion: Suggestion
