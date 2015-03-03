{Point} = require 'atom'
{triggerAutocompletion, buildIMECompositionEvent, buildTextInputEvent} = require './spec-helper'
_ = require 'underscore-plus'

indexOfWord = (suggestionList, word) ->
  for suggestion, i in suggestionList
    return i if suggestion.text is word
  -1

suggestionForWord = (suggestionList, word) ->
  for suggestion in suggestionList
    return suggestion if suggestion.text is word
  null

describe 'SymbolProvider', ->
  [completionDelay, editorView, editor, mainModule, autocompleteManager] = []

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

      waitsFor ->
        mainModule.autocompleteManager?.ready

      runs ->
        autocompleteManager = mainModule.autocompleteManager

      runs ->
        advanceClock 1
        editorView = atom.views.getView(editor)

    it "properly swaps a lower priority type for a higher priority type", ->
      provider = autocompleteManager.providerManager.fuzzyProvider
      suggestion = suggestionForWord(provider.symbolList, 'SomeModule')
      expect(suggestion.type).toEqual 'class'

    it "does not output suggestions from the other buffer", ->
      provider = autocompleteManager.providerManager.fuzzyProvider
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

      waitsFor ->
        mainModule.autocompleteManager?.ready

      runs ->
        autocompleteManager = mainModule.autocompleteManager

      runs ->
        advanceClock 1
        editorView = atom.views.getView(editor)

    it "runs a completion ", ->
      provider = autocompleteManager.providerManager.fuzzyProvider
      expect(indexOfWord(provider.symbolList, 'quicksort')).not.toEqual(-1)

    it "adds words to the symbol list after they have been written", ->
      provider = autocompleteManager.providerManager.fuzzyProvider

      expect(indexOfWord(provider.symbolList, 'aNewFunction')).toEqual(-1)
      editor.insertText('function aNewFunction(){};')
      editor.insertText(' ')
      advanceClock provider.changeUpdateDelay
      expect(indexOfWord(provider.symbolList, 'aNewFunction')).not.toEqual(-1)

    describe "when includeCompletionsFromAllBuffers is enabled", ->
      beforeEach ->
        atom.config.set('autocomplete-plus.includeCompletionsFromAllBuffers', true)

        waitsForPromise ->
          atom.packages.activatePackage("language-coffee-script").then ->
            atom.workspace.open("sample.coffee").then (e) ->
              editor = e

      afterEach ->
        atom.config.set('autocomplete-plus.includeCompletionsFromAllBuffers', false)

      it "outputs unique suggestions", ->
        provider = autocompleteManager.providerManager.fuzzyProvider
        results = null
        waitsForPromise ->
          promise = provider.getSuggestions({editor, prefix: 'qu', bufferPosition: new Point(7, 0)})
          advanceClock 1
          promise.then (r) -> results = r

        runs ->
          expect(results).toHaveLength 1

      it "outputs suggestions from the other buffer", ->
        provider = autocompleteManager.providerManager.fuzzyProvider
        results = null
        waitsForPromise ->
          promise = provider.getSuggestions({editor, prefix: 'item', bufferPosition: new Point(7, 0)})
          advanceClock 1
          promise.then (r) -> results = r

        runs ->
          expect(results[0].text).toBe 'items'

    # Fixing This Fixes #76
    xit 'adds words to the wordlist with unicode characters', ->
      provider = autocompleteManager.providerManager.fuzzyProvider

      expect(provider.symbolList.indexOf('somēthingNew')).toEqual(-1)
      editor.insertText('somēthingNew')
      editor.insertText(' ')
      expect(provider.symbolList.indexOf('somēthingNew')).not.toEqual(-1)
