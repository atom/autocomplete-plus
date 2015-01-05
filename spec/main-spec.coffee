{triggerAutocompletion, buildIMECompositionEvent, buildTextInputEvent} = require "./spec-helper"
_ = require "underscore-plus"
TestProvider = require "./lib/test-provider"

describe "Autocomplete", ->
  [completionDelay, editorView, editor, autocomplete, mainModule] = []

  beforeEach ->
    runs ->
      # Set to live completion
      atom.config.set "autocomplete-plus.enableAutoActivation", true
      atom.config.set "autocomplete-plus.fileBlacklist", ".*, *.md"

      # Set the completion delay
      completionDelay = 100
      atom.config.set "autocomplete-plus.autoActivationDelay", completionDelay
      completionDelay += 100 # Rendering delay

      workspaceElement = atom.views.getView(atom.workspace)
      jasmine.attachToDOM(workspaceElement)

    waitsForPromise -> atom.workspace.open("sample.js").then (e) ->
      editor = e

    # Activate the package
    waitsForPromise ->
      atom.packages.activatePackage("autocomplete-plus")
        .then (a) -> mainModule = a.mainModule

    runs ->
      editorView = atom.views.getView(editor)


  describe "@activate()", ->
    it "activates autocomplete and initializes AutocompleteManager", ->
      runs ->
        expect(mainModule.autocompleteManager).toBeDefined()
        expect(editorView.querySelector(".autocomplete-plus")).not.toExist()

  describe "@deactivate()", ->
    it "removes all autocomplete views", ->

      runs ->
        buffer = editor.getBuffer()

        # Trigger an autocompletion
        editor.moveToBottom()
        editor.insertText("A")

        advanceClock completionDelay
        editorView = editorView
        expect(editorView.querySelector(".autocomplete-plus")).toExist()

        # Deactivate the package
        atom.packages.deactivatePackage "autocomplete-plus"
        expect(editorView.querySelector(".autocomplete-plus")).not.toExist()

  describe "Providers", ->
    describe "registerProviderForEditor", ->
      it "registers the given provider for the given editor view", ->
        runs ->
          testProvider = new TestProvider(editor)
          mainModule.registerProviderForEditor(testProvider, editor)

          autocomplete = mainModule.autocompleteManager
          expect(autocomplete.providers[1]).toBe testProvider

    describe "registerMultipleIdenticalProvidersForEditorView", ->
      it "registers the given provider once when called multiple times for the given editor view", ->

        runs ->
          testProvider = new TestProvider(editorView)
          mainModule.registerProviderForEditor(testProvider, editor)
          mainModule.registerProviderForEditor(testProvider, editor)
          mainModule.registerProviderForEditor(testProvider, editor)

          autocompleteManager = mainModule.autocompleteManager
          expect(autocompleteManager.providers[1]).toBe(testProvider)
          expect(_.size(autocompleteManager.providers)).toBe(2)

    describe "unregisterProviderFromEditorView", ->
      it "unregisters the provider from all editor views", ->
        runs ->
          testProvider = new TestProvider(editor)
          mainModule.registerProviderForEditor(testProvider, editor)

          autocompleteManager = mainModule.autocompleteManager
          expect(autocompleteManager.providers[1]).toBe(testProvider)

          mainModule.unregisterProvider(testProvider)
          expect(autocompleteManager.providers[1]).not.toExist()

    describe "a registered provider", ->
      it "calls buildSuggestions()", ->
        runs ->
          testProvider = new TestProvider(editor)
          mainModule.registerProviderForEditor testProvider, editor

          spyOn(testProvider, "buildSuggestions").andCallThrough()

          # Trigger an autocompletion
          triggerAutocompletion editor
          advanceClock completionDelay

          expect(testProvider.buildSuggestions).toHaveBeenCalled()

      it "calls confirm()", ->
        runs ->
          testProvider = new TestProvider(editorView)
          mainModule.registerProviderForEditor testProvider, editor

          spyOn(testProvider, 'confirm').andCallThrough()

          # Trigger an autocompletion
          triggerAutocompletion editor
          advanceClock completionDelay

          autocompleteManager = mainModule.autocompleteManager
          suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
          atom.commands.dispatch(suggestionListView, 'autocomplete-plus:confirm')

          expect(testProvider.confirm).toHaveBeenCalled()
