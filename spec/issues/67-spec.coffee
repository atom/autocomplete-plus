require "../spec-helper"
AutocompleteManager = require '../../lib/autocomplete-manager'

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

        workspaceElement = atom.views.getView(atom.workspace)
        jasmine.attachToDOM(workspaceElement)

      waitsForPromise -> atom.workspace.open("issues/50.js").then (e) ->
        editor = e

      runs ->
        editorView = atom.views.getView(editor)

    it "autocomplete should only show for the editor that currently has focus", ->
      runs ->
        editor2 = atom.workspace.paneForItem(editor).splitRight(copyActiveItem: true).getActiveItem()
        editorView2 = atom.views.getView(editor2)
        editorView.focus()

        autocomplete = new AutocompleteManager(editor)
        autocomplete2 = new AutocompleteManager(editor2)

        autocomplete.name = "autocomplete"
        autocomplete2.name = "autocomplete2"

        expect(editorView).toHaveFocus()
        expect(editorView.querySelector(".autocomplete-plus")).not.toExist()

        expect(editorView2).not.toHaveFocus()
        expect(editorView2.querySelector(".autocomplete-plus")).not.toExist()

        editor.insertText "r"

        expect(editorView).toHaveFocus()
        expect(editorView2).not.toHaveFocus()

        advanceClock completionDelay

        expect(editorView).toHaveFocus()
        expect(editorView2).not.toHaveFocus()

        expect(editorView.querySelector(".autocomplete-plus")).toExist()
        expect(editorView2.querySelector(".autocomplete-plus")).not.toExist()

        autocompleteView = atom.views.getView(autocomplete)
        atom.commands.dispatch autocompleteView, "autocomplete-plus:confirm"

        expect(editorView).toHaveFocus()
        expect(editorView2).not.toHaveFocus()

        expect(editorView.querySelector(".autocomplete-plus")).not.toExist()
        expect(editorView2.querySelector(".autocomplete-plus")).not.toExist()
