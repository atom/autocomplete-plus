require "../spec-helper"
AutocompleteView = require '../../lib/autocomplete-view'
Autocomplete = require '../../lib/autocomplete'

describe "Autocomplete", ->
  [activationPromise, autocomplete, editorView, editor, completionDelay] = []

  describe "Issue 64", ->
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

      waitsForPromise -> atom.workspace.open("issues/64.css").then (e) ->
        editor = e

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) -> autocomplete = a

      runs ->
        editorView = atom.views.getView(editor)
        autocomplete = new AutocompleteView editor

    it "it adds words hyphens to the wordlist", ->
      runs ->
        editor.insertText c for c in "bla"

        advanceClock completionDelay

        expect(editorView.querySelector(".autocomplete-plus")).toExist()

        expect(autocomplete.list.find("li:eq(0)")).toHaveText "bla-foo--bar"
