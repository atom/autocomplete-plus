require "../spec-helper"
Autocomplete = require '../../lib/autocomplete'

describe "Autocomplete", ->
  [autocomplete, editorView, editor, completionDelay] = []

  describe "Issue 63", ->
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


      waitsForPromise -> atom.workspace.open("sample.js").then (e) ->
        editor = e

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus")

      runs ->
        editorView = atom.views.getView(editor)
        autocomplete = new Autocomplete editor

    it "it adds words to the wordlist when pressing a special character", ->
      runs ->
        editor.insertText "somethingNew"
        editor.insertText ")"

        provider = autocomplete.providers[0]
        expect(provider.wordList.indexOf("somethingNew")).not.toEqual(-1)
