_ = require 'underscore-plus'
AutocompleteManager = require './autocomplete-manager'
SelectListElement = require './select-list-element'
Provider = require './provider'
Suggestion = require './suggestion'
FuzzyProvider = require './fuzzy-provider'

{deprecate} = require 'grim'

module.exports =
  config:
    includeCompletionsFromAllBuffers:
      type: "boolean"
      default: false
    fileBlacklist:
      type: "string"
      default: ".*, *.md"
    enableAutoActivation:
      type: "boolean"
      default: true
    autoActivationDelay:
      type: "integer"
      default: 100
    maxSuggestions:
      type: "integer"
      default: 10

  autocompleteManagers: []
  editorSubscription: null
  providerClasses: [FuzzyProvider]

  # Public: Creates AutocompleteManager instances for all active and future editors (soon, just a single AutocompleteManager)
  activate: ->

    atom.views.addViewProvider(AutocompleteManager, (model) =>
      element = new SelectListElement()
      element.setModel(model)
      element
    )

    @editorSubscription = atom.workspace.observeTextEditors (editor) =>
      autocompleteManager = new AutocompleteManager(editor)
      for ProviderClass in @providerClasses
        autocompleteManager.registerProvider new ProviderClass(editor)

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

  registerProviderForEditorView: (provider) ->
    deprecate('Use of editorView is deprecated, use registerProviderForEditor instead')
    @registerProviderForEditor(provider)

  # Public: Finds the autocomplete for the given TextEditor
  # and registers the given provider
  #
  # provider - The new {Provider}
  # editor - The {TextEditor} we should register the provider with
  registerProviderForEditor: (provider) ->
    editor = provider.editor
    autocompleteManager = _.findWhere(@autocompleteManagers, editor: editor)
    unless autocompleteManager?
      throw new Error("Could not register provider", provider.constructor.name)

    autocompleteManager.registerProvider(provider)

  registerProviderClass: (ProviderClass) ->
    @providerClasses.push(ProviderClass)
    for autocompleteManager in @autocompleteManagers
      autocompleteManager.registerProvider(new ProviderClass(autocompleteManager.editor))

  unregisterProviderClass: (ProviderClass) ->
    _.remove(@providerClasses, ProviderClass)
    for autocompleteManager in @autocompleteManagers
      autocompleteManager.unregisterProviderClass(ProviderClass)

  # Public: unregisters the given provider
  #
  # provider - The {Provider} to unregister
  unregisterProvider: (provider) ->
    autocompleteManager.unregisterProvider provider for autocompleteManager in @autocompleteManagers

  Provider: Provider
  Suggestion: Suggestion
  FuzzyProvider: FuzzyProvider
