{waitForAutocomplete} = require '../spec-helper'

describe 'Autocomplete', ->
  [mainModule, autocompleteManager, editorView, editor, completionDelay] = []

  describe 'Issue 65 - Stop autocomplete after you pass the autocomplete suggestion', ->
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

      waitsForPromise -> atom.workspace.open('sample.js').then (e) ->
        editor = e

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
        mainModule = a.mainModule

      waitsFor ->
        mainModule.autocompleteManager?.ready

      runs ->
        autocompleteManager = mainModule.autocompleteManager

      runs ->
        editorView = atom.views.getView(editor)

    describe 'when autocomplete is triggered', ->
      it 'it hides the suggestion list when the user keeps typing', ->
        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

          # Trigger an autocompletion
          editor.moveToBottom()
          editor.insertText('s')
          waitForAutocomplete()

          runs ->
            expect(editorView.querySelector('.autocomplete-plus')).toExist()

            editor.insertText('b')
            waitForAutocomplete()

          runs ->
            expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
