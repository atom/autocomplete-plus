require "../spec-helper"
path = require 'path'
temp = require('temp').track()

describe "Autocomplete", ->
  [directory, editorView, editor, completionDelay] = []

  describe "Issue 15", ->
    beforeEach ->
      runs ->
        directory = temp.mkdirSync()

        # Set to live completion
        atom.config.set "autocomplete-plus.enableAutoActivation", true

        # Set the completion delay
        completionDelay = 100
        atom.config.set "autocomplete-plus.autoActivationDelay", completionDelay
        completionDelay += 100 # Rendering delay

        workspaceElement = atom.views.getView(atom.workspace)
        jasmine.attachToDOM(workspaceElement)

      waitsForPromise -> atom.workspace.open("issues/11.js").then (e) ->
        editor = e

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus")

      runs ->
        editorView = atom.views.getView(editor)

    it "closes the suggestion list when saving", ->
      runs ->
        expect(editorView.querySelector(".autocomplete-plus")).not.toExist()

        # Trigger an autocompletion
        editor.moveToBottom()
        editor.insertText "r"

        advanceClock completionDelay

        expect(editorView.querySelector(".autocomplete-plus")).toExist()

        editor.saveAs(path.join(directory, "spec", "tmp", "issue-11.js"))

        expect(editorView.querySelector(".autocomplete-plus")).not.toExist()
