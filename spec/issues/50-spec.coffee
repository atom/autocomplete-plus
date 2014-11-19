require "../spec-helper"
{$, TextEditorView, WorkspaceView} = require 'atom'
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
        atom.workspaceView = new WorkspaceView()
        atom.workspace = atom.workspaceView.model

      waitsForPromise -> atom.workspace.open("issues/50.js").then (e) ->
        editor = e
        atom.workspaceView.attachToDom()

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) -> autocomplete = a.mainModule

      runs -> editorView = atom.workspaceView.getActiveView()

    it "works after closing one of the copied tabs", ->
      runs ->
        expect(autocomplete.autocompleteViews.length).toEqual(1)

        editorView.getPaneView().getModel().splitRight(copyActiveItem: true)
        expect(autocomplete.autocompleteViews.length).toEqual(2)

        atom.workspaceView.destroyActivePane()
        expect(autocomplete.autocompleteViews.length).toEqual(1)

        editor.moveCursorToEndOfLine
        editor.insertNewline()
        editor.insertText "f"

        advanceClock completionDelay
        expect(editorView.find(".autocomplete-plus")).toExist()
