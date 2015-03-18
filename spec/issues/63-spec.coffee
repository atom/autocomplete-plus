{waitForAutocomplete} = require '../spec-helper'

describe 'Autocomplete', ->
  [mainModule, autocompleteManager, editorView, editor, completionDelay] = []

  describe 'Issue 63', ->
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
        advanceClock(mainModule.autocompleteManager.providerManager.fuzzyProvider.deferBuildWordListInterval)
        editorView = atom.views.getView(editor)

    it 'it adds words to the wordlist when pressing a special character', ->
      runs ->
        editor.insertText('somethingNew')
        editor.insertText(')')

        provider = autocompleteManager.providerManager.fuzzyProvider
        expect(provider.wordList.indexOf('somethingNew')).not.toEqual(-1)
