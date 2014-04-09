require "../spec-helper"
{$, EditorView, WorkspaceView} = require 'atom'
AutocompleteView = require '../../lib/autocomplete-view'
Autocomplete = require '../../lib/autocomplete'

describe "Autocomplete", ->
  [activationPromise, autocomplete, editorView, editor] = []

  describe "Issue 23 and 25", ->
    beforeEach ->
      # Create a fake workspace and open a sample file
      atom.workspaceView = new WorkspaceView
      atom.workspaceView.openSync "issues/23-25.js"
      atom.workspaceView.simulateDomAttachment()

      # Set to live completion
      atom.config.set "autocomplete-plus.liveCompletion", true

      # Activate the package
      activationPromise = atom.packages.activatePackage "autocomplete-plus"

      editorView = atom.workspaceView.getActiveView()
      {editor} = editorView
      autocomplete = new AutocompleteView editorView

    it "does not show suggestions after a word has been completed", ->

      waitsForPromise ->
        activationPromise

      runs ->
        editorView.attachToDom()
        expect(editorView.find(".autocomplete")).not.toExist()

        # Trigger an autocompletion
        editor.moveCursorToBottom()
        editor.insertText c for c in "red"

        expect(editorView.find(".autocomplete")).toExist()

        # Accept suggestion
        autocomplete.trigger "core:confirm"

        expect(editorView.find(".autocomplete")).not.toExist()
