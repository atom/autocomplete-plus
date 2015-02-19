{waitForAutocomplete} = require('../spec-helper')

describe 'Autocomplete', ->
  [mainModule, autocompleteManager, editorView, editor, completionDelay] = []

  describe 'Issue 64', ->
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

      waitsForPromise -> atom.workspace.open('issues/64.css').then (e) ->
        editor = e
        editorView = atom.views.getView(editor)

      waitsForPromise ->
        atom.packages.activatePackage('language-css')

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
        mainModule = a.mainModule

      waitsFor ->
        mainModule.autocompleteManager?.ready

      waitsFor ->
        mainModule.autocompleteManager.providerManager?

      runs ->
        autocompleteManager = mainModule.autocompleteManager

    it 'it adds words hyphens to the wordlist', ->
      runs ->
        editor.insertText(c) for c in 'bla'

        waitForAutocomplete()

        runs ->

          expect(editorView.querySelector('.autocomplete-plus')).toExist()

          suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
          expect(suggestionListView.querySelector('li')).toHaveText('bla-foo--bar')
