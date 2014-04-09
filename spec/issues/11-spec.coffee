require "../spec-helper"
{$, EditorView, WorkspaceView} = require 'atom'
AutocompleteView = require '../../lib/autocomplete-view'
Autocomplete = require '../../lib/autocomplete'

describe "Autocomplete", ->
  [activationPromise, autocomplete, editorView, editor] = []

  describe "Issue 11", ->
    beforeEach ->
      # Create a fake workspace and open a sample file
      atom.workspaceView = new WorkspaceView
      atom.workspaceView.openSync "issues/11.js"
      atom.workspaceView.simulateDomAttachment()

      # Set to live completion
      atom.config.set "autocomplete-plus.liveCompletion", true

      # Activate the package
      activationPromise = atom.packages.activatePackage "autocomplete-plus"

      editorView = atom.workspaceView.getActiveView()
      {editor} = editorView
      autocomplete = new AutocompleteView editorView

    it "does not trigger autocompletion when pasting", ->

      waitsForPromise ->
        activationPromise

      runs ->
        editorView.attachToDom()
        expect(editorView.find(".autocomplete-plus")).not.toExist()

        # Trigger an autocompletion
        editor.moveCursorToBottom()
        editor.insertText "red"

        expect(editorView.find(".autocomplete-plus")).not.toExist()
