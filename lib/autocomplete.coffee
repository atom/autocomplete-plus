_ = require 'underscore'

AutocompleteView = require './autocomplete-view'

module.exports =
  configDefaults:
    includeCompletionsFromAllBuffers: false

  autocompleteViews: []
  editorSubscription: null

  activate: ->
    @editorSubscription = rootView.eachEditor (editor) =>
      if editor.attached and not editor.mini
        autocompleteView = new AutocompleteView(editor)
        editor.on 'editor:will-be-removed', =>
          _.remove(@autocompleteViews, autocompleteView)
        @autocompleteViews.push(autocompleteView)

  deactivate: ->
    @editorSubscription?.off()
    @editorSubscription = null
    @autocompleteViews.forEach (autocompleteView) -> autocompleteView.remove()
    @autocompleteViews = []
