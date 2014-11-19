{triggerAutocompletion, buildIMECompositionEvent, buildTextInputEvent} = require "../spec-helper"
{$, TextEditorView, WorkspaceView} = require 'atom'
AutocompleteView = require '../../lib/autocomplete-view'
Autocomplete = require '../../lib/autocomplete'
TestProvider = require '../lib/test-provider'

describe "Autocomplete", ->
  [activationPromise, autocomplete, editorView, editor, completionDelay, autocompleteModule] = []

  describe "Issue 57 - Multiple selection completion", ->
    beforeEach ->
      runs ->
        # Set to live completion
        atom.config.set "autocomplete-plus.enableAutoActivation", true

        # Set the completion delay
        completionDelay = 100
        atom.config.set "autocomplete-plus.autoActivationDelay", completionDelay
        completionDelay += 100 # Rendering delay
        atom.workspaceView = new WorkspaceView()
        atom.workspace = atom.workspaceView.model

      waitsForPromise -> atom.workspace.open("issues/57.js").then (e) ->
        editor = e
        atom.workspaceView.attachToDom()

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage("autocomplete-plus").then (a) -> autocompleteModule = a.mainModule

      runs ->
        editorView = atom.workspaceView.getActiveView()

    describe 'where many cursors are defined', ->
      it 'autocompletes word when there is only a prefix', ->
        editor.getBuffer().insert([10,0] ,"s:extra:s")
        editor.setSelectedBufferRanges([[[10,1],[10,1]], [[10,9],[10,9]]])
        editorView.attachToDom()

        triggerAutocompletion editor, false, 'h'
        advanceClock completionDelay

        autocomplete = autocompleteModule.autocompleteViews[0]

        autocomplete.trigger "autocomplete-plus:confirm"

        expect(editor.lineTextForBufferRow(10)).toBe "shift:extra:shift"
        expect(editor.getCursorBufferPosition()).toEqual [10,12]
        expect(editor.getLastSelection().getBufferRange()).toEqual({
          start:
            row: 10
            column: 12
          end:
            row: 10
            column: 12
        })

        expect(editor.getSelections().length).toEqual(2)

      describe 'where text differs between cursors', ->
        it 'cancels the autocomplete', ->
          editor.getBuffer().insert([10,0] ,"s:extra:a")
          editor.setSelectedBufferRanges([[[10,1],[10,1]], [[10,9],[10,9]]])
          editorView.attachToDom()

          triggerAutocompletion editor, false, 'h'
          advanceClock completionDelay

          autocomplete = autocompleteModule.autocompleteViews[0]
          autocomplete.trigger "autocomplete-plus:confirm"

          expect(editor.lineTextForBufferRow(10)).toBe "sh:extra:ah"
          expect(editor.getSelections().length).toEqual(2)
          expect(editor.getSelections()[0].getBufferRange()).toEqual [[10,2], [10,2]]
          expect(editor.getSelections()[1].getBufferRange()).toEqual [[10,11], [10,11]]

          expect(editorView.find('.autocomplete-plus')).not.toExist()
