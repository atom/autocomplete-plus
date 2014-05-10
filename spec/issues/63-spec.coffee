require "../spec-helper"
{$, EditorView, WorkspaceView} = require 'atom'
AutocompleteView = require '../../lib/autocomplete-view'
Autocomplete = require '../../lib/autocomplete'

describe "Autocomplete", ->
  [activationPromise, autocomplete, editorView, editor, completionDelay] = []

  describe "Issue 63", ->
    beforeEach ->
      # Create a fake workspace and open a sample file
      atom.workspaceView = new WorkspaceView
      atom.workspaceView.openSync "sample.js"
      atom.workspaceView.simulateDomAttachment()

      # Set to live completion
      atom.config.set "autocomplete-plus.enableAutoActivation", true

      # Set the completion delay
      completionDelay = 100
      atom.config.set "autocomplete-plus.autoActivationDelay", completionDelay
      completionDelay += 100 # Rendering delay

      # Activate the package
      activationPromise = atom.packages.activatePackage "autocomplete-plus"

      editorView = atom.workspaceView.getActiveView()
      {editor} = editorView
      autocomplete = new AutocompleteView editorView

    it "it adds words to the wordlist when pressing a special character", ->

      waitsForPromise ->
        activationPromise

      runs ->
        editorView.attachToDom()
        editor.insertText "somethingNew"
        editor.insertText ")"

        provider = autocomplete.providers[0];
        expect(provider.wordList.indexOf("somethingNew")).not.toEqual(-1)
