{triggerAutocompletion, buildIMECompositionEvent, buildTextInputEvent} = require "./spec-helper"
{$, TextEditorView, WorkspaceView} = require 'atom'
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

    waitsForPromise -> atom.workspace.open("blacklisted.md").then (e) ->
      editor = e
      atom.workspaceView.attachToDom()

    # Activate the package
    waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) -> autocomplete = a.mainModule

    runs ->
      editorView = atom.workspaceView.getActiveView()

  describe "Autocomplete File Blacklist", ->
    it "should not show autocompletion for files that match the blacklist", ->
      editorView.attachToDom()

      editor.insertText "a"
      advanceClock completionDelay

      expect(editorView.find(".autocomplete-plus")).not.toExist()
