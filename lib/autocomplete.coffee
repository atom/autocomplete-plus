_ = require "underscore-plus"
AutocompleteView = require "./autocomplete-view"

module.exports =
  configDefaults:
    includeCompletionsFromAllBuffers: false
    fileBlacklist: ".*, *.md"
    completionDelay: 100

  autocompleteViews: []
  editorSubscription: null

  ###
   * Creates AutocompleteView instances for all active and future editors
  ###
  activate: ->
    @editorSubscription = atom.workspaceView.eachEditorView (editor) =>
      if editor.attached and not editor.mini
        autocompleteView = new AutocompleteView(editor)
        editor.on "editor:will-be-removed", =>
          autocompleteView.remove() unless autocompleteView.hasParent()
          autocompleteView.dispose()
          _.remove(@autocompleteViews, autocompleteView)
        @autocompleteViews.push(autocompleteView)

  ###
   * Cleans everything up, removes all AutocompleteView instances
  ###
  deactivate: ->
    @editorSubscription?.off()
    @editorSubscription = null
    @autocompleteViews.forEach (autocompleteView) -> autocompleteView.remove()
    @autocompleteViews = []
