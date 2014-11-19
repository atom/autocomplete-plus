{triggerAutocompletion, buildIMECompositionEvent, buildTextInputEvent} = require "./spec-helper"
{$, TextEditorView, WorkspaceView} = require 'atom'
_ = require "underscore-plus"
AutocompleteView = require '../lib/autocomplete-view'
Autocomplete = require '../lib/autocomplete'
TestProvider = require "./lib/test-provider"

describe "AutocompleteView", ->
  [activationPromise, completionDelay, editorView, editor, autocomplete, autocompleteView] = []

  beforeEach ->
    runs ->
      # Set to live completion
      atom.config.set "autocomplete-plus.enableAutoActivation", true

      # Set the completion delay
      completionDelay = 100
      atom.config.set "autocomplete-plus.autoActivationDelay", completionDelay
      completionDelay += 100 # Rendering delay

      # Spy on AutocompleteView#initialize
      spyOn(AutocompleteView.prototype, "initialize").andCallThrough()

      atom.workspaceView = new WorkspaceView()
      atom.workspace = atom.workspaceView.model

  describe "when auto-activation is enabled", ->
    beforeEach ->
      runs -> atom.config.set "autocomplete-plus.enableAutoActivation", true

      waitsForPromise -> atom.workspace.open("sample.js").then (e) ->
        editor = e
        atom.workspaceView.attachToDom()

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) ->
        autocomplete = a.mainModule
        autocompleteView = autocomplete.autocompleteViews[0]

      runs ->
        editorView = atom.workspaceView.getActiveView()

    # TODO: Move this to a separate fuzzyprovider spec
    it "adds words to the wordlist after they have been written", ->
      editorView.attachToDom()
      editor.insertText "somethingNew"
      editor.insertText " "

      provider = autocompleteView.providers[0];
      expect(provider.wordList.indexOf("somethingNew")).not.toEqual(-1)
