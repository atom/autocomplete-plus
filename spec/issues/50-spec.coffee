require "../spec-helper"
{$, EditorView, WorkspaceView} = require 'atom'
AutocompleteView = require '../../lib/autocomplete-view'
Autocomplete = require '../../lib/autocomplete'

describe "Autocomplete", ->
  [activationPromise, autocomplete, editorView, editor, completionDelay] = []

  describe "Issue 50", ->
    beforeEach ->
      # Create a fake workspace and open a sample file
      atom.workspaceView = new WorkspaceView
      atom.workspaceView.openSync "issues/50.js"
      atom.workspaceView.simulateDomAttachment()

      # Set to live completion
      atom.config.set "autocomplete-plus.enableAutoActivation", true

      # Set the completion delay
      completionDelay = 100
      atom.config.set "autocomplete-plus.autoActivationDelay", completionDelay
      completionDelay += 100 # Rendering delay

      # Activate the package
      activationPromise = atom.packages.activatePackage "autocomplete-plus"

      editorView = atom.workspaceView.getActiveView()
      {editor} = editorView

    it "works after closing one of the copied tabs", ->
      waitsForPromise ->
        activationPromise
          .then (pkg) =>
            autocomplete = pkg.mainModule

      runs ->
        expect(autocomplete.autocompleteViews.length).toEqual(1)

        editorView.splitRight()
        expect(autocomplete.autocompleteViews.length).toEqual(2)

        atom.workspaceView.destroyActivePane()
        expect(autocomplete.autocompleteViews.length).toEqual(1)

        editor.moveCursorToEndOfLine
        editor.insertNewline()
        editor.insertText "f"

        advanceClock completionDelay
        expect(editorView.find(".autocomplete-plus")).toExist()
