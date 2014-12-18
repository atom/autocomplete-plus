require "../spec-helper"

describe "Autocomplete", ->
  [mainModule, autocompleteManager, editorView, editor, completionDelay] = []

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
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) ->
        mainModule = a.mainModule
        autocompleteManager = mainModule.autocompleteManagers[0]

      runs ->
        editorView = atom.views.getView(editor)

    it "it adds words hyphens to the wordlist", ->
      runs ->
        editor.insertText c for c in "bla"

        advanceClock completionDelay

        expect(editorView.querySelector(".autocomplete-plus")).toExist()

        autocompleteView = atom.views.getView(autocompleteManager)
        expect(autocompleteView.querySelector("li")).toHaveText "bla-foo--bar"
