{waitForAutocomplete} = require './spec-helper'

describe 'Autocomplete Manager', ->
  [completionDelay, editorView, editor, mainModule, autocompleteManager] = []

  beforeEach ->
    runs ->
      # Set to live completion
      atom.config.set('autocomplete-plus.enableAutoActivation', true)
      atom.config.set('editor.fontSize', '16')

      # Set the completion delay
      completionDelay = 100
      atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
      completionDelay += 100 # Rendering

      workspaceElement = atom.views.getView(atom.workspace)
      jasmine.attachToDOM(workspaceElement)

  describe 'Undo a completion', ->
    beforeEach ->
      runs ->
        atom.config.set('autocomplete-plus.enableAutoActivation', true)

      waitsForPromise -> atom.workspace.open('sample.js').then (e) ->
        editor = e

      waitsForPromise ->
        atom.packages.activatePackage('language-javascript')

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
        mainModule = a.mainModule

      waitsFor ->
        mainModule.autocompleteManager?.ready

      runs ->
        autocompleteManager = mainModule.autocompleteManager
        advanceClock(autocompleteManager.providerManager.defaultProvider.deferBuildWordListInterval)

    it 'restores the previous state', ->

      # Trigger an autocompletion
      editor.moveToBottom()
      editor.moveToBeginningOfLine()
      editor.insertText('f')

      waitForAutocomplete()

      runs ->
        # Accept suggestion
        editorView = atom.views.getView(editor)
        atom.commands.dispatch(editorView, 'autocomplete-plus:confirm')

        expect(editor.getBuffer().getLastLine()).toEqual('function')

        editor.undo()

        expect(editor.getBuffer().getLastLine()).toEqual('f')
