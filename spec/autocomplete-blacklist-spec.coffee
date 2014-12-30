{triggerAutocompletion, buildIMECompositionEvent, buildTextInputEvent} = require "./spec-helper"
_ = require "underscore-plus"
TestProvider = require "./lib/test-provider"

describe "Autocomplete", ->
  [completionDelay, editorView, editor, mainModule] = []

  beforeEach ->
    runs ->
      # Set to live completion
      atom.config.set "autocomplete-plus.enableAutoActivation", true
      atom.config.set "autocomplete-plus.fileBlacklist", ".*, *.md"

      # Set the completion delay
      completionDelay = 100
      atom.config.set "autocomplete-plus.autoActivationDelay", completionDelay
      completionDelay += 100 # Rendering delay

    waitsForPromise -> atom.workspace.open("blacklisted.md").then (e) ->
      editor = e

    # Activate the package
    waitsForPromise -> atom.packages.activatePackage("autocomplete-plus")

    runs ->
      editorView = atom.views.getView(editor)


  describe "Autocomplete File Blacklist", ->
    it "should not show suggestions when working with files that match the blacklist", ->
      editor.insertText "a"
      advanceClock completionDelay

      expect(editorView.querySelector(".autocomplete-plus")).not.toExist()
