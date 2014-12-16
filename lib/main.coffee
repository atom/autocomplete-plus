_ = require "underscore-plus"
Autocomplete = require "./autocomplete"
SelectListElement = require "./select-list-element.coffee"
Provider = require "./provider"
Suggestion = require "./suggestion"
semver = require "semver"
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

  autocompletes: []
  editorSubscription: null

  # Public: Creates Autocomplete instances for all active and future editors
  activate: ->

    atom.views.addViewProvider(Autocomplete, (model) =>
      element = new SelectListElement()
      element.setModel(model)
      element
    )
    # If both autosave and autocomplete+'s auto-activation feature are enabled,
    # disable the auto-activation
    if atom.packages.isPackageLoaded("autosave") and
      semver.lt(atom.packages.getLoadedPackage("autosave").metadata.version, "0.17.0") and
      atom.config.get("autosave.enabled") and
      atom.config.get("autocomplete-plus.enableAutoActivation")
        atom.config.set "autocomplete-plus.enableAutoActivation", false

        console.log(atom.packages)

        alert """Warning from autocomplete+:

        autocomplete+ is not compatible with the autosave package when the auto-activation feature is enabled. Therefore, auto-activation has been disabled.

        autocomplete+ can now only be triggered using the keyboard shortcut `ctrl+space`."""

    @editorSubscription = atom.workspace.observeTextEditors (editor) =>
      autocomplete = new Autocomplete(editor)

      editor.onDidDestroy =>
        autocomplete.dispose()
        _.remove(@autocompletes, autocomplete)

      @autocompletes.push(autocomplete)

  # Public: Cleans everything up, removes all Autocomplete instances
  deactivate: ->
    @editorSubscription?.dispose()
    @editorSubscription = null
    @autocompletes.forEach (autocomplete) -> autocomplete.dispose()
    @autocompletes = []

  registerProviderForEditorView: (provider, editorView) ->
    deprecate('Use of editorView is deprecated, use registerProviderForEditor instead')
    @registerProviderForEditor(provider, editor.getModel())

  # Public: Finds the autocomplete for the given TextEditor
  # and registers the given provider
  #
  # provider - The new {Provider}
  # editor - The {TextEditor} we should register the provider with
  registerProviderForEditor: (provider, editor) ->
    return unless provider?
    return unless editor?
    autocomplete = _.findWhere @autocompletes, editor: editor
    unless autocomplete?
      throw new Error("Could not register provider", provider.constructor.name)

    autocomplete.registerProvider(provider)

  # Public: unregisters the given provider
  #
  # provider - The {Provider} to unregister
  unregisterProvider: (provider) ->
    autocomplete.unregisterProvider provider for autocomplete in @autocompletes

  Provider: Provider
  Suggestion: Suggestion
