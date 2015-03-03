{waitForAutocomplete} = require '../spec-helper'

describe 'Autocomplete', ->
  [mainModule, autocompleteManager, editorView, editor, completionDelay] = []

  describe 'Issue 23 and 25', ->
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

      waitsForPromise -> atom.workspace.open('issues/23-25.js').then (e) ->
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

    it 'does not show suggestions after a word has been confirmed', ->
      runs ->
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        # Trigger an autocompletion
        editor.moveToBottom()
        editor.insertText(c) for c in 'red'

        waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

          # Accept suggestion
          suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
          atom.commands.dispatch(suggestionListView, 'autocomplete-plus:confirm')

          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
