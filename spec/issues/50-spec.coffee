require "../spec-helper"
Autocomplete = require '../../lib/autocomplete'

describe "Autocomplete", ->
  [activationPromise, mainModule, editorView, editor, completionDelay] = []

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
      waitsForPromise ->
        atom.packages.activatePackage("autocomplete-plus")
          .then (a) -> mainModule = a.mainModule

      runs ->
        editorView = atom.views.getView(editor)

    it "works after closing one of the copied tabs", ->
      runs ->
        expect(mainModule.autocompletes.length).toEqual(1)

        atom.workspace.paneForItem(editor).splitRight(copyActiveItem: true)
        expect(mainModule.autocompletes.length).toEqual(2)

        atom.workspace.getActivePane().destroy()
        expect(mainModule.autocompletes.length).toEqual(1)

        editor.moveCursorToEndOfLine
        editor.insertNewline()
        editor.insertText "f"

        advanceClock completionDelay
        expect(editorView.querySelector(".autocomplete-plus")).toExist()
