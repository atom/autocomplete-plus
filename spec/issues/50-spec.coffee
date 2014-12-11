require "../spec-helper"
AutocompleteView = require '../../lib/autocomplete-view'
Autocomplete = require '../../lib/autocomplete'

describe "Autocomplete", ->
  [activationPromise, autocomplete, editorView, editor, completionDelay] = []

  describe "Issue 50", ->
    beforeEach ->
      runs ->
        # Set to live completion
        atom.config.set "autocomplete-plus.enableAutoActivation", true

        # Set the completion delay
        completionDelay = 100
        atom.config.set "autocomplete-plus.autoActivationDelay", completionDelay
        completionDelay += 100 # Rendering delay

        workspaceElement = atom.views.getView(atom.workspace)
        jasmine.attachToDOM(workspaceElement)

      waitsForPromise -> atom.workspace.open("issues/50.js").then (e) ->
        editor = e

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) -> autocomplete = a.mainModule

      runs ->
        editorView = atom.views.getView(editor)

    it "works after closing one of the copied tabs", ->
      runs ->
        expect(autocomplete.autocompleteViews.length).toEqual(1)

        atom.workspace.paneForItem(editor).splitRight(copyActiveItem: true)
        expect(autocomplete.autocompleteViews.length).toEqual(2)

        atom.workspace.getActivePane().destroy()
        expect(autocomplete.autocompleteViews.length).toEqual(1)

        editor.moveCursorToEndOfLine
        editor.insertNewline()
        editor.insertText "f"

        advanceClock completionDelay
        expect(editorView.querySelector(".autocomplete-plus")).toExist()
