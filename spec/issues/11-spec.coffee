{waitForAutocomplete} = require('../spec-helper')

describe 'Autocomplete', ->
  [mainModule, autocompleteManager, editorView, editor, completionDelay] = []

  describe 'Issue 11', ->
    beforeEach ->
      runs ->
        jasmine.unspy(window, 'setTimeout')
        jasmine.unspy(window, 'clearTimeout')

        # Set to live completion
        atom.config.set('autocomplete-plus.enableAutoActivation', true)

        # Set the completion delay
        completionDelay = 100
        atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
        completionDelay += 100 # Rendering delay

        workspaceElement = atom.views.getView(atom.workspace)
        jasmine.attachToDOM(workspaceElement)

      waitsForPromise -> atom.workspace.open('issues/11.js').then (e) ->
        editor = e

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
        mainModule = a.mainModule

      waitsFor ->
        mainModule.autocompleteManager?.ready

      waitsFor ->
        mainModule.autocompleteManager.providerManager?

      runs ->
        autocompleteManager = mainModule.autocompleteManager

      runs ->
        editorView = atom.views.getView(editor)

    it 'does not show the suggestion list when pasting', ->

      runs ->
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        # Trigger an autocompletion
        editor.moveToBottom()
        editor.insertText('red')

        waitForAutocomplete()

      runs ->
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
