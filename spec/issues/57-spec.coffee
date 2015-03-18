{waitForAutocomplete, triggerAutocompletion, buildIMECompositionEvent, buildTextInputEvent} = require '../spec-helper'

describe 'Autocomplete', ->
  [mainModule, autocompleteManager, editorView, editor, completionDelay, mainModule] = []

  describe 'Issue 57 - Multiple selection completion', ->
    beforeEach ->
      runs ->
        # Set to live completion
        atom.config.set('autocomplete-plus.enableAutoActivation', true)

        # Set the completion delay
        completionDelay = 100
        atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
        completionDelay += 100 # Rendering delay

        workspaceElement = atom.views.getView(atom.workspace)
        jasmine.attachToDOM(workspaceElement)

      waitsForPromise -> atom.workspace.open('issues/57.js').then (e) ->
        editor = e

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
        mainModule = a.mainModule

      waitsFor ->
        mainModule.autocompleteManager?.ready

      runs ->
        autocompleteManager = mainModule.autocompleteManager

      runs ->
        advanceClock(mainModule.autocompleteManager.providerManager.fuzzyProvider.deferBuildWordListInterval)
        editorView = atom.views.getView(editor)

    describe 'where many cursors are defined', ->
      it 'autocompletes word when there is only a prefix', ->
        editor.getBuffer().insert([10, 0], 's:extra:s')
        editor.setSelectedBufferRanges([[[10, 1], [10, 1]], [[10, 9], [10, 9]]])

        runs ->
          triggerAutocompletion(editor, false, 'h')

        waits(completionDelay)

        runs ->
          editorView = atom.views.getView(editor)
          console.log editorView.classList
          autocompleteManager = mainModule.autocompleteManager
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

          atom.commands.dispatch(editorView, 'autocomplete-plus:confirm')

          expect(editor.lineTextForBufferRow(10)).toBe('shift:extra:shift')
          expect(editor.getCursorBufferPosition()).toEqual([10, 17])
          expect(editor.getLastSelection().getBufferRange()).toEqual({
            start:
              row: 10
              column: 17
            end:
              row: 10
              column: 17
          })

          expect(editor.getSelections().length).toEqual(2)

      describe 'where text differs between cursors', ->
        it 'cancels the autocomplete', ->
          editor.getBuffer().insert([10, 0], 's:extra:a')
          editor.setCursorBufferPosition([10, 1])
          editor.addCursorAtBufferPosition([10, 9])

          runs ->
            triggerAutocompletion(editor, false, 'h')

          waits(completionDelay)

          runs ->
            autocompleteManager = mainModule.autocompleteManager

            editorView = atom.views.getView(editor)
            atom.commands.dispatch(editorView, 'autocomplete-plus:confirm')

            expect(editor.lineTextForBufferRow(10)).toBe('sh:extra:ah')
            expect(editor.getSelections().length).toEqual(2)
            expect(editor.getSelections()[0].getBufferRange()).toEqual([[10, 2], [10, 2]])
            expect(editor.getSelections()[1].getBufferRange()).toEqual([[10, 11], [10, 11]])

            expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
