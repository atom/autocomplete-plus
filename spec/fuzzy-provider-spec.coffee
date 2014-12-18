{triggerAutocompletion, buildIMECompositionEvent, buildTextInputEvent} = require "./spec-helper"
_ = require "underscore-plus"
TestProvider = require "./lib/test-provider"

describe "Autocomplete", ->
  [completionDelay, editorView, editor, autocomplete, mainModule] = []

  beforeEach ->
    runs ->
      # Set to live completion
      atom.config.set "autocomplete-plus.enableAutoActivation", true

      # Set the completion delay
      completionDelay = 100
      atom.config.set "autocomplete-plus.autoActivationDelay", completionDelay
      completionDelay += 100 # Rendering delaya\

      workspaceElement = atom.views.getView(atom.workspace)
      jasmine.attachToDOM(workspaceElement)

  describe "when auto-activation is enabled", ->
    beforeEach ->
      runs -> atom.config.set "autocomplete-plus.enableAutoActivation", true

      waitsForPromise -> atom.workspace.open("sample.js").then (e) ->
        editor = e

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) ->
        mainModule = a.mainModule
        autocomplete = mainModule.autocompleteManagers[0]

      runs ->
        editorView = atom.views.getView(editor)

    # TODO: Move this to a separate fuzzyprovider spec
    it "adds words to the wordlist after they have been written", ->
      editor.insertText "somethingNew"
      editor.insertText " "

      provider = autocomplete.providers[0];
      expect(provider.wordList.indexOf("somethingNew")).not.toEqual(-1)
