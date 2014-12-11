{triggerAutocompletion, buildIMECompositionEvent, buildTextInputEvent} = require "./spec-helper"
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



    waitsForPromise -> atom.workspace.open("blacklisted.md").then (e) ->
      editor = e

    # Activate the package
    waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) -> autocomplete = a.mainModule

    runs ->
      editorView = atom.views.getView(editor)


  describe "Autocomplete File Blacklist", ->
    it "should not show autocompletion for files that match the blacklist", ->
      editor.insertText "a"
      advanceClock completionDelay

      expect(editorView.querySelector(".autocomplete-plus")).not.toExist()
