_ = require 'underscore-plus'
AutocompleteView = require './autocomplete-view'
Provider = require './provider'
Suggestion = require './suggestion'
{deprecate} = require 'atom-space-pen-views'

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

  autocompleteViews: []
  editorSubscription: null

  # Public: Creates AutocompleteView instances for all active and future editors
  activate: ->
    @editorSubscription = atom.workspace.observeTextEditors (editor) =>
      autocompleteView = new AutocompleteView(editor)

      editor.onDidDestroy =>
        autocompleteView.remove() unless autocompleteView.hasParent()
        autocompleteView.dispose()
        _.remove(@autocompleteViews, autocompleteView)

      @autocompleteViews.push(autocompleteView)

  # Public: Cleans everything up, removes all AutocompleteView instances
  deactivate: ->
    @editorSubscription?.dispose()
    @editorSubscription = null
    @autocompleteViews.forEach (autocompleteView) -> autocompleteView.remove()
    @autocompleteViews = []

  registerProviderForEditorView: (provider, editorView) ->
    deprecate('Use of editorView is deprecated, use registerProviderForEditor instead')
    @registerProviderForEditor(provider, editor.getModel())

  # Public: Finds the autocomplete view for the given TextEditor
  # and registers the given provider
  #
  # provider - The new {Provider}
  # editor - The {TextEditor} we should register the provider with
  registerProviderForEditor: (provider, editor) ->
    autocompleteView = _.findWhere @autocompleteViews, editor: editor
    unless autocompleteView?
      throw new Error("Could not register provider", provider.constructor.name)

    autocompleteView.registerProvider provider

  # Public: unregisters the given provider
  #
  # provider - The {Provider} to unregister
  unregisterProvider: (provider) ->
    view.unregisterProvider provider for view in @autocompleteViews

  Provider: Provider
  Suggestion: Suggestion
