{Point} = require 'atom'
{triggerAutocompletion, buildIMECompositionEvent, buildTextInputEvent} = require './spec-helper'
_ = require 'underscore-plus'

suggestionForWord = (suggestionList, word) ->
  suggestionList.getSymbol(word)

suggestionsForPrefix = (provider, editor, prefix, options) ->
  bufferPosition = editor.getCursorBufferPosition()
  scopeDescriptor = editor.getLastCursor().getScopeDescriptor()
  suggestions = provider.findSuggestionsForWord({editor, bufferPosition, prefix, scopeDescriptor})
  if options?.raw
    suggestions
  else
    (sug.text for sug in suggestions)

describe 'SymbolProvider', ->
  [completionDelay, editorView, editor, mainModule, autocompleteManager, provider] = []

  beforeEach ->
    # Set to live completion
    atom.config.set('autocomplete-plus.enableAutoActivation', true)
    atom.config.set('autocomplete-plus.defaultProvider', 'Symbol')

    # Set the completion delay
    completionDelay = 100
    atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
    completionDelay += 100 # Rendering delaya\

    workspaceElement = atom.views.getView(atom.workspace)
    jasmine.attachToDOM(workspaceElement)

    waitsForPromise ->
      Promise.all [
        atom.workspace.open("sample.js").then (e) -> editor = e
        atom.packages.activatePackage("language-javascript")
        atom.packages.activatePackage("autocomplete-plus").then (a) -> mainModule = a.mainModule
      ]

    runs ->
      autocompleteManager = mainModule.autocompleteManager
      advanceClock 1
      editorView = atom.views.getView(editor)
      provider = autocompleteManager.providerManager.fuzzyProvider

  it "does not output suggestions from the other buffer", ->
    [results, coffeeEditor] = []

    waitsForPromise ->
      Promise.all [
        atom.packages.activatePackage("language-coffee-script")
        atom.workspace.open("sample.coffee").then (e) -> coffeeEditor = e
      ]

    runs ->
      advanceClock 1 # build the new wordlist
      expect(suggestionsForPrefix(provider, coffeeEditor, 'item')).toHaveLength 0

  it "runs a completion ", ->
    expect(suggestionForWord(provider.symbolStore, 'quicksort')).toBeTruthy()

  it "adds words to the symbol list after they have been written", ->
    expect(suggestionsForPrefix(provider, editor, 'anew')).not.toContain 'aNewFunction'

    editor.insertText('function aNewFunction(){};')
    editor.insertText(' ')
    advanceClock provider.changeUpdateDelay

    expect(suggestionsForPrefix(provider, editor, 'anew')).toContain 'aNewFunction'

  it "adds words after they have been added to a scope that is not a direct match for the selector", ->
    expect(suggestionsForPrefix(provider, editor, 'some')).not.toContain 'somestring'

    editor.insertText('abc = "somestring"')
    editor.insertText(' ')
    advanceClock provider.changeUpdateDelay

    expect(suggestionsForPrefix(provider, editor, 'some')).toContain 'somestring'

  it "removes words from the symbol list when they do not exist in the buffer", ->
    editor.moveToBottom()
    editor.moveToBeginningOfLine()

    expect(suggestionsForPrefix(provider, editor, 'anew')).not.toContain 'aNewFunction'

    editor.insertText('function aNewFunction(){};')
    advanceClock provider.changeUpdateDelay
    expect(suggestionsForPrefix(provider, editor, 'anew')).toContain 'aNewFunction'

    editor.setCursorBufferPosition([13, 21])
    editor.backspace()
    advanceClock provider.changeUpdateDelay

    expect(suggestionsForPrefix(provider, editor, 'anew')).toContain 'aNewFunctio'
    expect(suggestionsForPrefix(provider, editor, 'anew')).not.toContain 'aNewFunction'

  it "correctly tracks the buffer row associated with symbols as they change", ->
    editor.setText('')
    advanceClock(provider.changeUpdateDelay)

    editor.setText('function abc(){}\nfunction abc(){}')
    advanceClock(provider.changeUpdateDelay)
    suggestion = suggestionForWord(provider.symbolStore, 'abc')
    expect(suggestion.bufferRowsForEditorPath(editor.getPath())).toEqual [0, 1]

    editor.setCursorBufferPosition([2, 100])
    editor.insertText('\n\nfunction omg(){}; function omg(){}')
    advanceClock(provider.changeUpdateDelay)
    suggestion = suggestionForWord(provider.symbolStore, 'omg')
    expect(suggestion.bufferRowsForEditorPath(editor.getPath())).toEqual [3, 3]

    editor.selectLeft(16)
    editor.backspace()
    advanceClock(provider.changeUpdateDelay)
    suggestion = suggestionForWord(provider.symbolStore, 'omg')
    expect(suggestion.bufferRowsForEditorPath(editor.getPath())).toEqual [3]

    editor.insertText('\nfunction omg(){}')
    advanceClock(provider.changeUpdateDelay)
    suggestion = suggestionForWord(provider.symbolStore, 'omg')
    expect(suggestion.bufferRowsForEditorPath(editor.getPath())).toEqual [3, 4]

    editor.setText('')
    advanceClock(provider.changeUpdateDelay)

    expect(suggestionForWord(provider.symbolStore, 'abc')).toBeUndefined()
    expect(suggestionForWord(provider.symbolStore, 'omg')).toBeUndefined()

    editor.setText('function abc(){}\nfunction abc(){}')
    editor.setCursorBufferPosition([0, 0])
    editor.insertText('\n')
    editor.setCursorBufferPosition([2, 100])
    editor.insertText('\nfunction abc(){}')
    advanceClock(provider.changeUpdateDelay)

    # This is kind of a mess right now. it does not correctly track buffer
    # rows when there are several changes before the change delay is
    # triggered. So we're just making sure the row is in there.
    suggestion = suggestionForWord(provider.symbolStore, 'abc')
    expect(suggestion.bufferRowsForEditorPath(editor.getPath())).toContain 3

  describe "when includeCompletionsFromAllBuffers is enabled", ->
    beforeEach ->
      atom.config.set('autocomplete-plus.includeCompletionsFromAllBuffers', true)

      waitsForPromise ->
        Promise.all [
          atom.packages.activatePackage("language-coffee-script")
          atom.workspace.open("sample.coffee").then (e) -> editor = e
        ]

      runs -> advanceClock 1

    afterEach ->
      atom.config.set('autocomplete-plus.includeCompletionsFromAllBuffers', false)

    it "outputs unique suggestions", ->
      editor.setCursorBufferPosition([7, 0])
      results = suggestionsForPrefix(provider, editor, 'qu')
      expect(results).toHaveLength 1

    it "outputs suggestions from the other buffer", ->
      editor.setCursorBufferPosition([7, 0])
      results = suggestionsForPrefix(provider, editor, 'item')
      expect(results[0]).toBe 'items'

  describe "when the completionConfig changes between scopes", ->
    beforeEach ->
      editor.setText '''
        // in-a-comment
        invar = "in-a-string"
      '''

      commentConfig =
        incomment:
          selector: '.comment'

      stringConfig =
        instring:
          selector: '.string'

      atom.config.set('editor.completionConfig', commentConfig, scopeSelector: '.source.js .comment')
      atom.config.set('editor.completionConfig', stringConfig, scopeSelector: '.source.js .string')

    it "uses the config for the scope under the cursor", ->
      # Using the comment config
      editor.setCursorBufferPosition([0, 2])
      suggestions = suggestionsForPrefix(provider, editor, 'in', raw: true)
      expect(suggestions).toHaveLength 1
      expect(suggestions[0].text).toBe 'in-a-comment'
      expect(suggestions[0].type).toBe 'incomment'

      # Using the string config
      editor.setCursorBufferPosition([1, 20])
      suggestions = suggestionsForPrefix(provider, editor, 'in', raw: true)
      expect(suggestions).toHaveLength 1
      expect(suggestions[0].text).toBe 'in-a-string'
      expect(suggestions[0].type).toBe 'instring'

      # Using the default config
      editor.setCursorBufferPosition([1, 5])
      suggestions = suggestionsForPrefix(provider, editor, 'in', raw: true)
      console.log suggestions
      expect(suggestions).toHaveLength 3
      expect(suggestions[0].text).toBe 'invar'
      expect(suggestions[0].type).toBe '' # the js grammar sucks :(

  # Fixing This Fixes #76
  xit 'adds words to the wordlist with unicode characters', ->
    expect(provider.symbolStore.indexOf('somēthingNew')).toBeFalsy()
    editor.insertText('somēthingNew')
    editor.insertText(' ')
    expect(provider.symbolStore.indexOf('somēthingNew')).toBeTruthy()
