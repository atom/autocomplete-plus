temp = require('temp').track()
path = require 'path'
fs = require 'fs-plus'

describe 'Autocomplete Manager', ->
  [directory, filePath, completionDelay, editorView, editor, mainModule, autocompleteManager, didAutocomplete] = []

  beforeEach ->
    runs ->
      directory = temp.mkdirSync()
      sample = '''
var quicksort = function () {
  var sort = function(items) {
    if (items.length <= 1) return items;
    var pivot = items.shift(), current, left = [], right = [];
    while(items.length > 0) {
      current = items.shift();
      current < pivot ? left.push(current) : right.push(current);
    }
    return sort(left).concat(pivot).concat(sort(right));
  };

  return sort(Array.apply(this, arguments));
};

      '''
      filePath = path.join(directory, 'sample.js')
      fs.writeFileSync(filePath, sample)

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

    waitsForPromise -> atom.workspace.open(filePath).then (e) ->
      editor = e
      editorView = atom.views.getView(editor)

    waitsForPromise ->
      atom.packages.activatePackage('language-javascript')

    # Activate the package
    waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
      mainModule = a.mainModule

    waitsFor ->
      mainModule.autocompleteManager?.ready

    runs ->
      autocompleteManager = mainModule.autocompleteManager
      displaySuggestions = autocompleteManager.displaySuggestions
      spyOn(autocompleteManager, 'displaySuggestions').andCallFake (suggestions, options) ->
        displaySuggestions(suggestions, options)
        didAutocomplete = true

  afterEach ->
    didAutocomplete = false

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
        editor.save()
        didAutocomplete = false
        expect(editorView.querySelector('.autocomplete-plus')).toExist()
        editor.insertText('u')
        advanceClock(completionDelay)

      waitsFor ->
        didAutocomplete is true

      runs ->
        editor.save()
        didAutocomplete = false
        expect(editorView.querySelector('.autocomplete-plus')).toExist()
        # Accept suggestion
        suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
        atom.commands.dispatch(suggestionListView, 'autocomplete-plus:confirm')
        expect(editor.getBuffer().getLastLine()).toEqual('function')
