{triggerAutocompletion, buildIMECompositionEvent, buildTextInputEvent} = require './spec-helper'
_ = require 'underscore-plus'

describe 'Autocomplete', ->
  [completionDelay, editorView, editor, mainModule, autocompleteManager] = []

  beforeEach ->
    runs ->
      # Set to live completion
      atom.config.set('autocomplete-plus.enableAutoActivation', true)

      # Set the completion delay
      completionDelay = 100
      atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
      completionDelay += 100 # Rendering delaya\

      workspaceElement = atom.views.getView(atom.workspace)
      jasmine.attachToDOM(workspaceElement)

  describe 'when auto-activation is enabled', ->
    beforeEach ->
      runs ->
        atom.config.set('autocomplete-plus.enableAutoActivation', true)

      waitsForPromise -> atom.workspace.open('sample.js').then (e) ->
        editor = e

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
        mainModule = a.mainModule

      runs ->
        autocompleteManager = mainModule.autocompleteManager
        advanceClock(mainModule.autocompleteManager.providerManager.fuzzyProvider.deferBuildWordListInterval)
        editorView = atom.views.getView(editor)

    it 'adds words to the wordlist after they have been written', ->
      editor.moveToBottom()
      editor.moveToBeginningOfLine()
      provider = autocompleteManager.providerManager.fuzzyProvider

      expect(provider.tokenList.getToken('somethingNew')).toBeUndefined()
      editor.insertText('somethingNew')
      expect(provider.tokenList.getToken('somethingNew')).toBe 'somethingNew'

    it 'removes words that are no longer in the buffer', ->
      editor.moveToBottom()
      editor.moveToBeginningOfLine()
      provider = autocompleteManager.providerManager.fuzzyProvider

      expect(provider.tokenList.getToken('somethingNew')).toBeUndefined()
      editor.insertText('somethingNew')
      expect(provider.tokenList.getToken('somethingNew')).toBe 'somethingNew'

      editor.backspace()
      expect(provider.tokenList.getToken('somethingNew')).toBe undefined
      expect(provider.tokenList.getToken('somethingNe')).toBe 'somethingNe'

    # Fixing This Fixes #76
    xit 'adds words to the wordlist with unicode characters', ->
      provider = autocompleteManager.providerManager.fuzzyProvider

      expect(provider.tokenList.indexOf('somēthingNew')).toEqual(-1)
      editor.insertText('somēthingNew')
      editor.insertText(' ')
      expect(provider.tokenList.indexOf('somēthingNew')).not.toEqual(-1)

    # Fixing This Fixes #196
    xit 'removes words from the wordlist when they no longer exist in any open buffers', ->
      # Not sure we should fix this; could have a significant performance impacts
      provider = autocompleteManager.providerManager.fuzzyProvider

      expect(provider.tokenList.indexOf('bogos')).toEqual(-1)
      editor.insertText('bogos = 1')
      editor.insertText(' ')
      expect(provider.tokenList.indexOf('bogos')).not.toEqual(-1)
      expect(provider.tokenList.indexOf('bogus')).toEqual(-1)
      editor.backspace() for [1..7]
      editor.insertText('us = 1')
      editor.insertText(' ')
      expect(provider.tokenList.indexOf('bogus')).not.toEqual(-1)
      expect(provider.tokenList.indexOf('bogos')).toEqual(-1)
