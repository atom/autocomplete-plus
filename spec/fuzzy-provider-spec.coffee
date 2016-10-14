describe 'FuzzyProvider', ->
  [completionDelay, editor, mainModule, autocompleteManager] = []

  beforeEach ->
    atom.config.set('autocomplete-plus.includeCompletionsFromAllBuffers', false)

    # Set to live completion
    atom.config.set('autocomplete-plus.enableAutoActivation', true)
    atom.config.set('autocomplete-plus.defaultProvider', 'Fuzzy')

    # Set the completion delay
    completionDelay = 100
    atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
    completionDelay += 100 # Rendering delaya\

    workspaceElement = atom.views.getView(atom.workspace)
    jasmine.attachToDOM(workspaceElement)

  describe 'when auto-activation is enabled', ->
    beforeEach ->
      waitsForPromise ->
        Promise.all [
          atom.packages.activatePackage("language-javascript")
          atom.workspace.open('sample.js').then (e) -> editor = e
          atom.packages.activatePackage('autocomplete-plus').then (a) ->
            mainModule = a.mainModule
        ]

      runs ->
        autocompleteManager = mainModule.autocompleteManager
        advanceClock(mainModule.autocompleteManager.providerManager.defaultProvider.deferBuildWordListInterval)

    it 'adds words to the wordlist after they have been written', ->
      editor.moveToBottom()
      editor.moveToBeginningOfLine()
      provider = autocompleteManager.providerManager.defaultProvider

      expect(provider.tokenList.getToken('somethingNew')).toBeUndefined()
      editor.insertText('somethingNew')
      expect(provider.tokenList.getToken('somethingNew')).toBe 'somethingNew'

    describe "when `editor.largeFileMode` is true", ->
      it "doesn't add words to the wordlist when the buffer changes", ->
        provider = autocompleteManager.providerManager.defaultProvider
        coffeeEditor = null

        waitsForPromise ->
          atom.packages.activatePackage("language-coffee-script")

        waitsForPromise ->
          atom.workspace.open('sample.coffee').then (e) ->
            coffeeEditor = e
            coffeeEditor.largeFileMode = true

        runs ->
          advanceClock(provider.deferBuildWordListInterval)
          expect(provider.tokenList.getToken('SomeModule')).toBeUndefined()

          coffeeEditor.getBuffer().insert([0, 0], 'abc')
          advanceClock(provider.deferBuildWordListInterval)
          expect(provider.tokenList.getToken('abcSomeModule')).toBeUndefined()

    it 'removes words that are no longer in the buffer', ->
      editor.moveToBottom()
      editor.moveToBeginningOfLine()
      provider = autocompleteManager.providerManager.defaultProvider

      expect(provider.tokenList.getToken('somethingNew')).toBeUndefined()
      editor.insertText('somethingNew')
      expect(provider.tokenList.getToken('somethingNew')).toBe 'somethingNew'

      editor.backspace()
      expect(provider.tokenList.getToken('somethingNew')).toBe undefined
      expect(provider.tokenList.getToken('somethingNe')).toBe 'somethingNe'

    it "adds completions from editor.completions", ->
      provider = autocompleteManager.providerManager.defaultProvider
      atom.config.set('editor.completions', ['abcd', 'abcde', 'abcdef'], scopeSelector: '.source.js')

      editor.moveToBottom()
      editor.insertText('ab')

      bufferPosition = editor.getLastCursor().getBufferPosition()
      scopeDescriptor = editor.getRootScopeDescriptor()
      prefix = 'ab'

      results = provider.getSuggestions({editor, bufferPosition, scopeDescriptor, prefix})
      expect(results[0].text).toBe 'abcd'

    it "adds completions from settings", ->
      provider = autocompleteManager.providerManager.defaultProvider
      atom.config.set('editor.completions', {builtin: suggestions: ['nope']}, scopeSelector: '.source.js')

      editor.moveToBottom()
      editor.insertText('ab')

      bufferPosition = editor.getLastCursor().getBufferPosition()
      scopeDescriptor = editor.getRootScopeDescriptor()
      prefix = 'ab'

      results = provider.getSuggestions({editor, bufferPosition, scopeDescriptor, prefix})
      expect(results).toBeUndefined()

    it 'adds words to the wordlist with unicode characters', ->
      atom.config.set('autocomplete-plus.enableExtendedUnicodeSupport', true)
      editor.moveToBottom()
      editor.moveToBeginningOfLine()
      provider = autocompleteManager.providerManager.defaultProvider

      expect(provider.tokenList.getToken('somēthingNew')).toBeUndefined()
      editor.insertText('somēthingNew')
      expect(provider.tokenList.getToken('somēthingNew')).toBe 'somēthingNew'

    # Fixing This Fixes #196
    xit 'removes words from the wordlist when they no longer exist in any open buffers', ->
      # Not sure we should fix this; could have a significant performance impacts
      provider = autocompleteManager.providerManager.defaultProvider

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
