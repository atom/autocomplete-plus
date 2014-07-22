{triggerAutocompletion, buildIMECompositionEvent, buildTextInputEvent} = require "./spec-helper"
{$, EditorView, WorkspaceView} = require 'atom'
_ = require "underscore-plus"
AutocompleteView = require '../lib/autocomplete-view'
Autocomplete = require '../lib/autocomplete'
TestProvider = require "./lib/test-provider"

describe "Autocomplete", ->
  [activationPromise, completionDelay, editorView, editor, autocomplete] = []

  beforeEach ->
    runs ->
      # Set to live completion
      atom.config.set "autocomplete-plus.enableAutoActivation", true
      atom.config.set "autocomplete-plus.fileBlacklist", ".*, *.md"

      # Set the completion delay
      completionDelay = 100
      atom.config.set "autocomplete-plus.autoActivationDelay", completionDelay
      completionDelay += 100 # Rendering delay

      # Spy on AutocompleteView#initialize
      spyOn(AutocompleteView.prototype, "initialize").andCallThrough()

      atom.workspaceView = new WorkspaceView()
      atom.workspace = atom.workspaceView.model

    waitsForPromise -> atom.workspace.open("sample.js").then (e) ->
      editor = e
      atom.workspaceView.simulateDomAttachment()

    # Activate the package
    waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) -> autocomplete = a.mainModule

    runs ->
      editorView = atom.workspaceView.getActiveView()

  describe "@activate()", ->
    it "activates autocomplete and initializes AutocompleteView instances", ->
      expect(AutocompleteView.prototype.initialize).toHaveBeenCalled()

      runs ->
        expect(editorView.find(".autocomplete-plus")).not.toExist()

  describe "@deactivate()", ->
    it "removes all autocomplete views", ->

      runs ->
        buffer = editor.getBuffer()

        # Trigger an autocompletion
        editor.moveCursorToBottom()
        editor.insertText("A")

        advanceClock completionDelay

        expect(editorView.find(".autocomplete-plus")).toExist()

        # Deactivate the package
        atom.packages.deactivatePackage "autocomplete-plus"
        expect(editorView.find(".autocomplete-plus")).not.toExist()

  describe "Providers", ->
    describe "registerProviderForEditorView", ->
      it "registers the given provider for the given editor view", ->
        runs ->
          testProvider = new TestProvider(editorView)
          autocomplete.registerProviderForEditorView testProvider, editorView

          autocompleteView = autocomplete.autocompleteViews[0]
          expect(autocompleteView.providers[1]).toBe testProvider

    describe "registerMultipleIdenticalProvidersForEditorView", ->
      it "registers the given provider once when called multiple times for the given editor view", ->

        runs ->
          testProvider = new TestProvider(editorView)
          autocomplete.registerProviderForEditorView testProvider, editorView
          autocomplete.registerProviderForEditorView testProvider, editorView
          autocomplete.registerProviderForEditorView testProvider, editorView

          autocompleteView = autocomplete.autocompleteViews[0]
          expect(autocompleteView.providers[1]).toBe testProvider
          expect(_.size(autocompleteView.providers)).toBe 2

    describe "unregisterProviderFromEditorView", ->
      it "unregisters the provider from all editor views", ->
        runs ->
          testProvider = new TestProvider(editorView)
          autocomplete.registerProviderForEditorView testProvider, editorView

          autocompleteView = autocomplete.autocompleteViews[0]
          expect(autocompleteView.providers[1]).toBe testProvider

          autocomplete.unregisterProvider testProvider
          expect(autocompleteView.providers[1]).not.toExist

    describe "a registered provider", ->
      it "calls buildSuggestions()", ->
        runs ->
          testProvider = new TestProvider(editorView)
          autocomplete.registerProviderForEditorView testProvider, editorView

          spyOn(testProvider, "buildSuggestions").andCallThrough()

          editorView.attachToDom()

          # Trigger an autocompletion
          triggerAutocompletion editor
          advanceClock completionDelay

          expect(testProvider.buildSuggestions).toHaveBeenCalled()

      it "calls confirm()", ->
        runs ->
          testProvider = new TestProvider(editorView)
          autocomplete.registerProviderForEditorView testProvider, editorView

          spyOn(testProvider, "confirm").andCallThrough()

          editorView.attachToDom()

          # Trigger an autocompletion
          triggerAutocompletion editor
          advanceClock completionDelay

          autocompleteView = autocomplete.autocompleteViews[0]
          autocompleteView.trigger "autocomplete-plus:confirm"

          expect(testProvider.confirm).toHaveBeenCalled()
