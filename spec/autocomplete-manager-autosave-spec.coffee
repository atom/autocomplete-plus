{waitForAutocomplete} = require('./spec-helper')

describe 'Autocomplete Manager', ->
  [completionDelay, editorView, editor, autocompleteManager, didAutocomplete] = []

  beforeEach ->
    runs ->
      # Enable autosave
      atom.config.set('autosave.enabled', true)

      # Set to live completion
      atom.config.set('autocomplete-plus.enableAutoActivation', true)
      atom.config.set('editor.fontSize', '16')

      # Set the completion delay
      completionDelay = 100
      atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
      completionDelay += 100 # Rendering

      workspaceElement = atom.views.getView(atom.workspace)
      jasmine.attachToDOM(workspaceElement)

    waitsForPromise ->
      atom.packages.activatePackage('autosave')

    waitsForPromise -> atom.workspace.open('sample.js').then (e) ->
      editor = e
      editorView = atom.views.getView(editor)

    waitsForPromise ->
      atom.packages.activatePackage('language-javascript')

    # Activate the package
    waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
      autocompleteManager = a.mainModule.autocompleteManager
      spyOn(autocompleteManager, 'runAutocompletion').andCallThrough()
      spyOn(autocompleteManager, 'showSuggestions').andCallThrough()
      spyOn(autocompleteManager, 'showSuggestionList').andCallThrough()
      spyOn(autocompleteManager, 'hideSuggestionList').andCallThrough()
      autocompleteManager.onDidAutocomplete ->
        didAutocomplete = true

  afterEach ->
    didAutocomplete = false
    jasmine.unspy(autocompleteManager, 'runAutocompletion')
    jasmine.unspy(autocompleteManager, 'showSuggestions')
    jasmine.unspy(autocompleteManager, 'showSuggestionList')
    jasmine.unspy(autocompleteManager, 'hideSuggestionList')

  describe 'autosave compatibility', ->
    it 'keeps the suggestion list open while saving', ->
      runs ->
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
        # Trigger an autocompletion
        editor.moveToBottom()
        editor.moveToBeginningOfLine()
        editor.insertText('f')
        advanceClock(completionDelay)

      waitsFor ->
        didAutocomplete is true

      runs ->
        didAutocomplete = false
        expect(editorView.querySelector('.autocomplete-plus')).toExist()
        editor.insertText('u')
        advanceClock(completionDelay)

      waitsFor ->
        didAutocomplete is true

      runs ->
        expect(editorView.querySelector('.autocomplete-plus')).toExist()
        # Accept suggestion
        suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
        atom.commands.dispatch(suggestionListView, 'autocomplete-plus:confirm')
        expect(editor.getBuffer().getLastLine()).toEqual('function')
