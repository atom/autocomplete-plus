{waitForAutocomplete} = require '../spec-helper'

describe 'Autocomplete', ->
  [mainModule, autocompleteManager, editorView, editor, completionDelay] = []

  describe 'Issue 56', ->
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

      waitsForPromise -> atom.workspace.open('issues/50.js').then (e) ->
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

    it 'it refocuses the editor after pressing enter', ->
      runs ->
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        # Trigger an autocompletion
        editor.moveToBottom()
        editor.insertText('r')

        waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

          editor.insertText('\n')

          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

          expect(editorView).toHaveFocus()
