{Point} = require 'atom'
{triggerAutocompletion, buildIMECompositionEvent, buildTextInputEvent} = require './spec-helper'
_ = require 'underscore-plus'

suggestionForWord = (suggestionList, word) ->
  suggestionList.getToken(word)

describe 'SymbolProvider', ->
  [completionDelay, editorView, editor, mainModule, autocompleteManager, provider] = []

  beforeEach ->
    runs ->
      # Set to live completion
      atom.config.set('autocomplete-plus.enableAutoActivation', true)
      atom.config.set('autocomplete-plus.defaultProvider', 'Symbol')

      # Set the completion delay
      completionDelay = 100
      atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
      completionDelay += 100 # Rendering delaya\

      workspaceElement = atom.views.getView(atom.workspace)
      jasmine.attachToDOM(workspaceElement)

  afterEach ->
    atom.config.set('autocomplete-plus.defaultProvider', 'Fuzzy')

  describe "when completing with the default configuration", ->
    beforeEach ->
      runs -> atom.config.set "autocomplete-plus.enableAutoActivation", true

      waitsForPromise -> atom.workspace.open("sample.coffee").then (e) ->
        editor = e

      # Activate the package
      waitsForPromise ->
        atom.packages.activatePackage("language-coffee-script").then ->
          atom.packages.activatePackage("autocomplete-plus").then (a) ->
            mainModule = a.mainModule

      runs ->
        autocompleteManager = mainModule.autocompleteManager
        advanceClock 1
        editorView = atom.views.getView(editor)
        provider = autocompleteManager.providerManager.fuzzyProvider

    it "properly swaps a lower priority type for a higher priority type", ->
      suggestion = suggestionForWord(provider.symbolList, 'SomeModule')
      expect(suggestion.type).toEqual 'class'

    it "does not output suggestions from the other buffer", ->
      results = null
      waitsForPromise ->
        promise = provider.getSuggestions({editor, prefix: 'item', bufferPosition: new Point(7, 0)})
        advanceClock 1
        promise.then (r) -> results = r

      runs ->
        expect(results).toHaveLength 0

  describe "when auto-activation is enabled", ->
    beforeEach ->
      runs ->
        atom.config.set('autocomplete-plus.enableAutoActivation', true)

      waitsForPromise -> atom.workspace.open('sample.js').then (e) ->
        editor = e

      # Activate the package
      waitsForPromise ->
        atom.packages.activatePackage("language-javascript").then ->
          atom.packages.activatePackage("autocomplete-plus").then (a) ->
            mainModule = a.mainModule

      runs ->
        autocompleteManager = mainModule.autocompleteManager
        advanceClock 1
        editorView = atom.views.getView(editor)
        provider = autocompleteManager.providerManager.fuzzyProvider

    it "runs a completion ", ->
      expect(suggestionForWord(provider.symbolList, 'quicksort')).toBeTruthy()

    it "adds words to the symbol list after they have been written", ->
      expect(suggestionForWord(provider.symbolList, 'aNewFunction')).toBeFalsy()
      editor.insertText('function aNewFunction(){};')
      editor.insertText(' ')
      advanceClock provider.changeUpdateDelay
      expect(suggestionForWord(provider.symbolList, 'aNewFunction')).toBeTruthy()

    it "removes words from the symbol list when they do not exist in the buffer", ->
      editor.moveToBottom()
      editor.moveToBeginningOfLine()

      expect(suggestionForWord(provider.symbolList, 'aNewFunction')).toBeFalsy()
      editor.insertText('function aNewFunction(){};')
      advanceClock provider.changeUpdateDelay
      expect(suggestionForWord(provider.symbolList, 'aNewFunction')).toBeTruthy()

      editor.setCursorBufferPosition([13, 21])
      editor.backspace()
      advanceClock provider.changeUpdateDelay

      expect(suggestionForWord(provider.symbolList, 'aNewFunctio')).toBeTruthy()
      expect(suggestionForWord(provider.symbolList, 'aNewFunction')).toBeFalsy()

    it "correctly tracks the buffer row associated with symbols as they change", ->
      editor.setText('')
      advanceClock(provider.changeUpdateDelay)

      editor.setText('function abc(){}\nfunction abc(){}')
      advanceClock(provider.changeUpdateDelay)
      suggestion = suggestionForWord(provider.symbolList, 'abc')
      expect(suggestion.bufferRowsForEditorPath[editor.getPath()]).toEqual [0, 1]

      editor.setCursorBufferPosition([2, 100])
      editor.insertText('\n\nfunction omg(){}; function omg(){}')
      advanceClock(provider.changeUpdateDelay)
      suggestion = suggestionForWord(provider.symbolList, 'omg')
      expect(suggestion.bufferRowsForEditorPath[editor.getPath()]).toEqual [3, 3]

      editor.selectLeft(16)
      editor.backspace()
      advanceClock(provider.changeUpdateDelay)
      suggestion = suggestionForWord(provider.symbolList, 'omg')
      expect(suggestion.bufferRowsForEditorPath[editor.getPath()]).toEqual [3]

      editor.insertText('\nfunction omg(){}')
      advanceClock(provider.changeUpdateDelay)
      suggestion = suggestionForWord(provider.symbolList, 'omg')
      expect(suggestion.bufferRowsForEditorPath[editor.getPath()]).toEqual [4, 3]

      editor.setText('')
      advanceClock(provider.changeUpdateDelay)

      expect(suggestionForWord(provider.symbolList, 'abc')).toBeUndefined()
      expect(suggestionForWord(provider.symbolList, 'omg')).toBeUndefined()

      editor.setText('function abc(){}\nfunction abc(){}')
      editor.setCursorBufferPosition([0, 0])
      editor.insertText('\n')
      editor.setCursorBufferPosition([2, 100])
      editor.insertText('\nfunction abc(){}')
      advanceClock(provider.changeUpdateDelay)

      # This is kind of a mess right now. it does not correctly track buffer
      # rows when there are several changes before the change delay is
      # triggered. So we're just making sure the row is in there.
      suggestion = suggestionForWord(provider.symbolList, 'abc')
      expect(suggestion.bufferRowsForEditorPath[editor.getPath()]).toContain 3

    describe "when includeCompletionsFromAllBuffers is enabled", ->
      beforeEach ->
        atom.config.set('autocomplete-plus.includeCompletionsFromAllBuffers', true)

        waitsForPromise ->
          atom.packages.activatePackage("language-coffee-script").then ->
            atom.workspace.open("sample.coffee").then (e) ->
              editor = e

        runs ->
          provider = autocompleteManager.providerManager.fuzzyProvider

      afterEach ->
        atom.config.set('autocomplete-plus.includeCompletionsFromAllBuffers', false)

      it "outputs unique suggestions", ->
        results = null
        waitsForPromise ->
          promise = provider.getSuggestions({editor, prefix: 'qu', bufferPosition: new Point(7, 0)})
          advanceClock 1
          promise.then (r) -> results = r

        runs ->
          expect(results).toHaveLength 1

      it "outputs suggestions from the other buffer", ->
        results = null
        waitsForPromise ->
          promise = provider.getSuggestions({editor, prefix: 'item', bufferPosition: new Point(7, 0)})
          advanceClock 1
          promise.then (r) -> results = r

        runs ->
          expect(results[0].text).toBe 'items'

    # Fixing This Fixes #76
    xit 'adds words to the wordlist with unicode characters', ->
      expect(provider.symbolList.indexOf('somēthingNew')).toBeFalsy()
      editor.insertText('somēthingNew')
      editor.insertText(' ')
      expect(provider.symbolList.indexOf('somēthingNew')).toBeTruthy()
