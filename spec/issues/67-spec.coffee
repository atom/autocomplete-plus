require "../spec-helper"
{$, TextEditorView, WorkspaceView} = require 'atom'
AutocompleteView = require '../../lib/autocomplete-view'

describe "Autocomplete", ->
  [activationPromise, editorView, editor, completionDelay] = []

  describe "Issue 67", ->
    beforeEach ->
      runs ->
        # Set to live completion
        atom.config.set "autocomplete-plus.enableAutoActivation", true

        # Set the completion delay
        completionDelay = 100
        atom.config.set "autocomplete-plus.autoActivationDelay", completionDelay
        completionDelay += 100 # Rendering delay

        spyOn(AutocompleteView.prototype, "initialize").andCallThrough()

        atom.workspaceView = new WorkspaceView()
        atom.workspace = atom.workspaceView.model

      waitsForPromise -> atom.workspace.open("issues/50.js").then (e) ->
        editor = e
        atom.workspaceView.attachToDom()

      runs ->
        editorView = atom.workspaceView.getActiveView()

    it "autocomplete should show on only focus editorView", ->
      runs ->
        editorView2 = editorView.splitRight()
        editorView.focus()

        autocomplete = new AutocompleteView editorView
        autocomplete2 = new AutocompleteView editorView2

        autocomplete.name = "autocomplete"
        autocomplete2.name = "autocomplete2"

        expect(editorView).toHaveFocus()
        expect(editorView.find(".autocomplete-plus")).not.toExist()

        expect(editorView2).not.toHaveFocus()
        expect(editorView2.find(".autocomplete-plus")).not.toExist()

        editor.insertText "r"

        expect(editorView).toHaveFocus()
        expect(editorView2).not.toHaveFocus()

        advanceClock completionDelay

        expect(editorView).toHaveFocus()
        expect(editorView2).not.toHaveFocus()

        expect(editorView.find(".autocomplete-plus")).toExist()
        expect(editorView2.find(".autocomplete-plus")).not.toExist()

        autocomplete.trigger "autocomplete-plus:confirm"

        expect(editorView).toHaveFocus()
        expect(editorView2).not.toHaveFocus()

        expect(editorView.find(".autocomplete-plus")).not.toExist()
        expect(editorView2.find(".autocomplete-plus")).not.toExist()
