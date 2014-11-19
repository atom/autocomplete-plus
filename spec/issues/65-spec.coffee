require "../spec-helper"
{$, TextEditorView, WorkspaceView} = require 'atom'
AutocompleteView = require '../../lib/autocomplete-view'
Autocomplete = require '../../lib/autocomplete'

describe "Autocomplete", ->
  [activationPromise, autocomplete, editorView, editor, completionDelay] = []

  describe "Issue 65", ->
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

      waitsForPromise -> atom.workspace.open("sample.js").then (e) ->
        editor = e
        atom.workspaceView.attachToDom()

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) -> autocomplete = a

      runs ->
        editorView = atom.workspaceView.getActiveView()
        autocomplete = new AutocompleteView editorView

    describe "when autocompletion triggers", ->
      it "it hides the autocompletion when user keeps typing", ->
        runs ->
          editorView.attachToDom()
          expect(editorView.find(".autocomplete-plus")).not.toExist()

          # Trigger an autocompletion
          editor.moveToBottom()
          editor.insertText "s"

          advanceClock completionDelay

          expect(editorView.find(".autocomplete-plus")).toExist()

          editor.insertText "b"

          advanceClock completionDelay

          expect(editorView.find(".autocomplete-plus")).not.toExist()
