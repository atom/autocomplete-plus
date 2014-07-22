{triggerAutocompletion, buildIMECompositionEvent, buildTextInputEvent} = require "./spec-helper"
{$, EditorView, WorkspaceView} = require 'atom'
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
      atom.config.set "editor.fontSize", "16"

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
        atom.workspaceView.simulateDomAttachment()

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) ->
        autocomplete = a.mainModule
        autocompleteView = autocomplete.autocompleteViews[0]

      runs ->
        editorView = atom.workspaceView.getActiveView()

    describe "on changed events", ->
      it "should attach when finding suggestions", ->
        editorView.attachToDom()
        expect(editorView.find(".autocomplete-plus")).not.toExist()

        # Trigger an autocompletion
        triggerAutocompletion editor
        advanceClock completionDelay
        expect(editorView.find(".autocomplete-plus")).toExist()

        # Check suggestions
        suggestions = ["function", "if", "left", "shift"]
        editorView.find(".autocomplete li span").each (index, item) ->
          $item = $(item)
          expect($item.text()).toEqual suggestions[index]

      it "should not attach when not finding suggestions", ->
        editorView.attachToDom()
        expect(editorView.find(".autocomplete-plus")).not.toExist()

        # Trigger an autocompletion
        editor.moveCursorToBottom()
        editor.insertText("x")
        advanceClock completionDelay
        expect(editorView.find(".autocomplete-plus")).not.toExist()

      it "should not update completions when composing characters", ->
        editorView.attachToDom()
        triggerAutocompletion editor
        advanceClock completionDelay
        inputNode = autocompleteView.hiddenInput[0]

        spyOn(autocompleteView, 'setItems').andCallThrough()

        inputNode.value = "~"
        inputNode.setSelectionRange(0, 1)
        inputNode.dispatchEvent(buildIMECompositionEvent('compositionstart', target: inputNode))
        inputNode.dispatchEvent(buildIMECompositionEvent('compositionupdate', data: "~", target: inputNode))
        advanceClock completionDelay

        expect(autocompleteView.setItems).not.toHaveBeenCalled()

        inputNode.dispatchEvent(buildIMECompositionEvent('compositionend', target: inputNode))
        editorView[0].firstChild.dispatchEvent(buildTextInputEvent(data: 'ã', target: inputNode))

        expect(editor.lineForBufferRow(13)).toBe 'fã'

    describe "accepting suggestions", ->
      describe "when pressing enter while suggestions are visible", ->
        it "inserts the word and moves the cursor to the end of the word", ->
          editorView.attachToDom()
          expect(editorView.find(".autocomplete-plus")).not.toExist()

          # Trigger an autocompletion
          triggerAutocompletion editor
          advanceClock completionDelay

          # Accept suggestion
          autocompleteView.trigger "autocomplete-plus:confirm"

          # Check for result
          expect(editor.getBuffer().getLastLine()).toEqual "function"

          # Check for cursor position
          bufferPosition = editor.getCursorBufferPosition()
          expect(bufferPosition.row).toEqual 13
          expect(bufferPosition.column).toEqual 8

        it "hides the suggestions", ->
          editorView.attachToDom()
          expect(editorView.find(".autocomplete-plus")).not.toExist()

          # Trigger an autocompletion
          editor.moveCursorToBottom()
          editor.moveCursorToBeginningOfLine()
          editor.insertText("f")
          advanceClock completionDelay
          expect(editorView.find(".autocomplete-plus")).toExist()

          # Accept suggestion
          autocompleteView.trigger "autocomplete-plus:confirm"

          expect(editorView.find(".autocomplete-plus")).not.toExist()

    describe "select-previous event", ->
      it "selects the previous item in the list", ->
        editorView.attachToDom()

        # Trigger an autocompletion
        triggerAutocompletion editor
        advanceClock completionDelay

        expect(editorView.find(".autocomplete-plus li:eq(0)")).toHaveClass("selected")
        expect(editorView.find(".autocomplete-plus li:eq(1)")).not.toHaveClass("selected")
        expect(editorView.find(".autocomplete-plus li:eq(2)")).not.toHaveClass("selected")
        expect(editorView.find(".autocomplete-plus li:eq(3)")).not.toHaveClass("selected")

        # Select previous item
        autocompleteView.trigger "autocomplete-plus:select-previous"

        expect(editorView.find(".autocomplete-plus li:eq(0)")).not.toHaveClass("selected")
        expect(editorView.find(".autocomplete-plus li:eq(1)")).not.toHaveClass("selected")
        expect(editorView.find(".autocomplete-plus li:eq(2)")).not.toHaveClass("selected")
        expect(editorView.find(".autocomplete-plus li:eq(3)")).toHaveClass("selected")

    describe "select-next event", ->
      it "selects the next item in the list", ->
        editorView.attachToDom()

        # Trigger an autocompletion
        triggerAutocompletion editor
        advanceClock completionDelay

        expect(editorView.find(".autocomplete-plus li:eq(0)")).toHaveClass("selected")
        expect(editorView.find(".autocomplete-plus li:eq(1)")).not.toHaveClass("selected")
        expect(editorView.find(".autocomplete-plus li:eq(2)")).not.toHaveClass("selected")
        expect(editorView.find(".autocomplete-plus li:eq(3)")).not.toHaveClass("selected")

        # Select next item
        autocompleteView.trigger "autocomplete-plus:select-next"

        expect(editorView.find(".autocomplete-plus li:eq(0)")).not.toHaveClass("selected")
        expect(editorView.find(".autocomplete-plus li:eq(1)")).toHaveClass("selected")
        expect(editorView.find(".autocomplete-plus li:eq(2)")).not.toHaveClass("selected")
        expect(editorView.find(".autocomplete-plus li:eq(3)")).not.toHaveClass("selected")

    describe "when a suggestion is clicked", ->
      it "should select the item and confirm the selection", ->
        editorView.attachToDom()

        # Trigger an autocompletion
        triggerAutocompletion editor
        advanceClock completionDelay

        # Get the second item
        item = editorView.find(".autocomplete-plus li:eq(1)")

        # Click the item, expect list to be hidden and
        # text to be added
        item.mousedown()
        expect(item).toHaveClass "selected"
        item.mouseup()

        expect(editorView.find(".autocomplete-plus")).not.toExist()
        expect(editor.getBuffer().getLastLine()).toEqual item.text()

    describe ".cancel()", ->
      it "unbinds autocomplete event handlers for move-up and move-down", ->
        triggerAutocompletion editor, false
        autocompleteView.cancel()

        editorView.trigger "core:move-down"
        expect(editor.getCursorBufferPosition().row).toBe 1

        editorView.trigger "core:move-up"
        expect(editor.getCursorBufferPosition().row).toBe 0

  describe "when a long completion exists", ->
    beforeEach ->
      runs ->
        atom.config.set "autocomplete-plus.enableAutoActivation", true

      waitsForPromise -> atom.workspace.open("samplelong.js").then (e) ->
        editor = e
        atom.workspaceView.simulateDomAttachment()

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) ->
        autocomplete = a.mainModule
        autocompleteView = autocomplete.autocompleteViews[0]

      runs ->
        editorView = atom.workspaceView.getActiveView()

    it "sets the width of the view to be wide enough to contain the longest completion without scrolling (+ 15 pixels)", ->
      editorView.attachToDom()
      editor.moveCursorToBottom()
      editor.insertNewline()
      editor.insertText "t"
      advanceClock completionDelay
      expect(autocompleteView.list.width()).toBe 430

  describe "css", ->
    [css] = []

    beforeEach ->
      runs -> atom.config.set "autocomplete-plus.enableAutoActivation", true

      waitsForPromise -> atom.workspace.open("css.css").then (e) ->
        editor = e
        atom.workspaceView.simulateDomAttachment()

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("language-css").then (c) -> css = c

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) ->
        autocomplete = a.mainModule
        autocompleteView = autocomplete.autocompleteViews[0]

      runs ->
        editorView = atom.workspaceView.getActiveView()

    it "includes completions for the scope's completion preferences", ->
      runs ->
        editorView.attachToDom()
        editor.moveCursorToEndOfLine()
        editor.insertText "o"
        editor.insertText "u"
        editor.insertText "t"

        advanceClock completionDelay

        expect(editorView.find(".autocomplete-plus")).toExist()
        expect(autocompleteView.list.find("li").length).toBe 10
        expect(autocompleteView.list.find("li:eq(0)")).toHaveText "outline"
        expect(autocompleteView.list.find("li:eq(1)")).toHaveText "outline-color"
        expect(autocompleteView.list.find("li:eq(2)")).toHaveText "outline-width"
        expect(autocompleteView.list.find("li:eq(3)")).toHaveText "outline-style"

  describe "Positioning", ->
    beforeEach ->
      runs -> atom.config.set "autocomplete-plus.enableAutoActivation", true

      waitsForPromise -> atom.workspace.open("sample.js").then (e) ->
        editor = e
        atom.workspaceView.simulateDomAttachment()

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) ->
        autocomplete = a.mainModule
        autocompleteView = autocomplete.autocompleteViews[0]

      runs ->
        editorView = atom.workspaceView.getActiveView()

      runs ->
        editorView.attachToDom()
        setEditorHeightInLines editorView, 13
        editorView.resetDisplay() # Ensures the editor only has 13 lines visible

    describe "when the autocomplete view fits below the cursor", ->
      it "adds the autocomplete view to the editor below the cursor", ->
        editor.setCursorBufferPosition [1, 2]
        editor.insertText "f"
        advanceClock completionDelay
        expect(editorView.find(".autocomplete-plus")).toExist()

        # Check position
        cursorPixelPosition = editorView.pixelPositionForScreenPosition editor.getCursorScreenPosition()
        expect(parseInt autocompleteView.css("top")).toBe cursorPixelPosition.top + editorView.lineHeight
        expect(autocompleteView.position().left).toBe cursorPixelPosition.left

    describe "when the autocomplete view does not fit below the cursor", ->
      it "adds the autocomplete view to the editor above the cursor", ->
        # Trigger autocompletion
        editor.setCursorScreenPosition [11, 0]
        editor.insertText "t"
        advanceClock completionDelay
        expect(editorView.find(".autocomplete-plus")).toExist()

        # Check position
        cursorPixelPosition = editorView.pixelPositionForScreenPosition editor.getCursorScreenPosition()
        expect(parseInt autocompleteView.css("top")).toBe cursorPixelPosition.top
        expect(autocompleteView.position().left).toBe cursorPixelPosition.left

  describe "when auto-activation is disabled", ->
    beforeEach ->
      runs ->
        atom.config.set "autocomplete-plus.enableAutoActivation", false

      waitsForPromise -> atom.workspace.open("sample.js").then (e) ->
        editor = e
        atom.workspaceView.simulateDomAttachment()

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) ->
        autocomplete = a.mainModule
        autocompleteView = autocomplete.autocompleteViews[0]

      runs ->
        editorView = atom.workspaceView.getActiveView()

    it "does not show suggestions after a delay", ->
      triggerAutocompletion editor
      advanceClock completionDelay
      expect(editorView.find(".autocomplete-plus")).not.toExist()

    it "shows suggestions when explicitly triggered", =>
      triggerAutocompletion editor
      advanceClock completionDelay
      expect(editorView.find(".autocomplete-plus")).not.toExist()
      editorView.trigger "autocomplete-plus:activate"
      expect(editorView.find(".autocomplete-plus")).toExist()

  describe "HTML label support", ->
    beforeEach ->
      waitsForPromise -> atom.workspace.open("sample.js").then (e) ->
        editor = e
        atom.workspaceView.simulateDomAttachment()

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) ->
        autocomplete = a.mainModule
        autocompleteView = autocomplete.autocompleteViews[0]

      runs ->
        editorView = atom.workspaceView.getActiveView()

    it "should allow HTML in labels", ->
      runs ->
        # Register the test provider
        testProvider = new TestProvider(editorView)
        autocomplete.registerProviderForEditorView testProvider, editorView

        editorView.attachToDom()
        editor.moveCursorToBottom()
        editor.insertText "o"

        advanceClock completionDelay

        expect(autocompleteView.list.find("li:eq(0) .label")).toHaveHtml "<span style=\"color: red\">ohai</span>"
        expect(autocompleteView.list.find("li:eq(0)")).toHaveClass "ohai"
