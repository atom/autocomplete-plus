_ = require 'underscore-plus'
AutocompleteView = require './autocomplete-view'

module.exports =
  configDefaults:
    liveCompletion: false
    includeCompletionsFromAllBuffers: false
    fileBlacklist: ".*, *.md"

  autocompleteViews: []
  editorSubscription: null

  activate: ->
    @editorSubscription = atom.workspaceView.eachEditorView (editor) =>
      if editor.attached and not editor.mini
        autocompleteView = new AutocompleteView(editor)
        editor.on 'editor:will-be-removed', =>
          autocompleteView.remove() unless autocompleteView.hasParent()
          autocompleteView.dispose()
          _.remove(@autocompleteViews, autocompleteView)
        @autocompleteViews.push(autocompleteView)

  deactivate: ->
    @editorSubscription?.off()
    @editorSubscription = null
    @autocompleteViews.forEach (autocompleteView) -> autocompleteView.remove()
    @autocompleteViews = []
