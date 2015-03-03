{waitForAutocomplete} = require './spec-helper'

describe 'Autocomplete', ->
  [completionDelay, editorView, editor, autocompleteManager, mainModule] = []

  beforeEach ->
    runs ->
      # Set to live completion
      atom.config.set('autocomplete-plus.enableAutoActivation', true)
      atom.config.set('autocomplete-plus.fileBlacklist', ['.*', '*.md'])

      # Set the completion delay
      completionDelay = 100
      atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
      completionDelay += 100 # Rendering delay

      workspaceElement = atom.views.getView(atom.workspace)
      jasmine.attachToDOM(workspaceElement)

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

    runs ->
      editorView = atom.views.getView(editor)

  describe '@activate()', ->
    it 'activates autocomplete and initializes AutocompleteManager', ->
      runs ->
        expect(autocompleteManager).toBeDefined()
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

  describe '@deactivate()', ->
    it 'removes all autocomplete views', ->
      runs ->
        buffer = editor.getBuffer()

        # Trigger an autocompletion
        editor.moveToBottom()
        editor.insertText('A')

        waitForAutocomplete()

        runs ->
          editorView = editorView
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

          # Deactivate the package
          atom.packages.deactivatePackage('autocomplete-plus')
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
