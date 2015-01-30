{waitForAutocomplete} = require('../spec-helper')
AutocompleteManager = require('../../lib/autocomplete-manager')

describe 'Autocomplete', ->
  [activationPromise, editorView, editor, completionDelay, autocompleteManager] = []

  describe 'Issue 67', ->
    [autocomplete] = []

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
        autocompleteManager = a.mainModule.autocompleteManager

      runs ->
        editorView = atom.views.getView(editor)

    afterEach ->
      autocomplete?.dispose()

    it 'autocomplete should only show for the editor that currently has focus', ->
      runs ->
        editor2 = atom.workspace.paneForItem(editor).splitRight({copyActiveItem: true}).getActiveItem()
        editorView2 = atom.views.getView(editor2)
        editorView.focus()

        expect(editorView).toHaveFocus()
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        expect(editorView2).not.toHaveFocus()
        expect(editorView2.querySelector('.autocomplete-plus')).not.toExist()

        editor.insertText('r')

        expect(editorView).toHaveFocus()
        expect(editorView2).not.toHaveFocus()

        waitForAutocomplete()

        runs ->
          expect(editorView).toHaveFocus()
          expect(editorView2).not.toHaveFocus()

          expect(editorView.querySelector('.autocomplete-plus')).toExist()
          expect(editorView2.querySelector('.autocomplete-plus')).not.toExist()

          suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
          atom.commands.dispatch(suggestionListView, 'autocomplete-plus:confirm')

          expect(editorView).toHaveFocus()
          expect(editorView2).not.toHaveFocus()

          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          expect(editorView2.querySelector('.autocomplete-plus')).not.toExist()
