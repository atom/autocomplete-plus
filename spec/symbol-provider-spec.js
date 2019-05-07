'use babel'
/* eslint-env jasmine */

import { TextBuffer } from 'atom'

let waitForBufferToStopChanging = () => advanceClock(TextBuffer.prototype.stoppedChangingDelay)

let suggestionsForPrefix = (provider, editor, prefix, options) => {
  let bufferPosition = editor.getCursorBufferPosition()
  let scopeDescriptor = editor.getLastCursor().getScopeDescriptor()
  let suggestions = provider.getSuggestions({editor, bufferPosition, prefix, scopeDescriptor})
  if (options && options.raw) {
    return suggestions
  } else {
    if (suggestions) {
      return (suggestions.map((sug) => sug.text))
    } else {
      return []
    }
  }
}

describe('SymbolProvider', () => {
  let [completionDelay, editor, mainModule, autocompleteManager, provider] = []

  beforeEach(() => {
    // Set to live completion
    atom.config.set('autocomplete-plus.enableAutoActivation', true)
    atom.config.set('autocomplete-plus.defaultProvider', 'Symbol')

    // Set the completion delay
    completionDelay = 100
    atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
    completionDelay += 100 // Rendering delaya\

    let workspaceElement = atom.views.getView(atom.workspace)
    jasmine.attachToDOM(workspaceElement)

    waitsForPromise(() =>
      Promise.all([
        atom.workspace.open('sample.js').then((e) => { editor = e }),
        atom.packages.activatePackage('language-javascript'),
        atom.packages.activatePackage('autocomplete-plus').then((a) => {
          mainModule = a.mainModule
        })
      ]))

    runs(() => {
      autocompleteManager = mainModule.autocompleteManager
      advanceClock(1)
      provider = autocompleteManager.providerManager.defaultProvider
    })
  })

  it('runs a completion ', () => expect(suggestionsForPrefix(provider, editor, 'quick')).toContain('quicksort')
  )

  it('adds words to the symbol list after they have been written', () => {
    expect(suggestionsForPrefix(provider, editor, 'anew')).not.toContain('aNewFunction')

    editor.insertText('function aNewFunction(){};')
    editor.insertText(' ')
    advanceClock(provider.changeUpdateDelay)

    expect(suggestionsForPrefix(provider, editor, 'anew')).toContain('aNewFunction')
  })

  it('adds words after they have been added to a scope that is not a direct match for the selector', () => {
    expect(suggestionsForPrefix(provider, editor, 'some')).not.toContain('somestring')

    editor.insertText('abc = "somestring"')
    editor.insertText(' ')
    advanceClock(provider.changeUpdateDelay)

    expect(suggestionsForPrefix(provider, editor, 'some')).toContain('somestring')
  })

  it('removes words from the symbol list when they do not exist in the buffer', () => {
    editor.moveToBottom()
    editor.moveToBeginningOfLine()

    expect(suggestionsForPrefix(provider, editor, 'anew')).not.toContain('aNewFunction')

    editor.insertText('function aNewFunction(){};')
    editor.moveToEndOfLine()
    advanceClock(provider.changeUpdateDelay)
    expect(suggestionsForPrefix(provider, editor, 'anew')).toContain('aNewFunction')

    editor.setCursorBufferPosition([13, 21])
    editor.backspace()
    editor.moveToTop()
    advanceClock(provider.changeUpdateDelay)

    expect(suggestionsForPrefix(provider, editor, 'anew')).toContain('aNewFunctio')
    expect(suggestionsForPrefix(provider, editor, 'anew')).not.toContain('aNewFunction')
  })

  it('does not return the word under the cursor when there is only a prefix', () => {
    editor.moveToBottom()
    editor.insertText('qu')
    waitForBufferToStopChanging()
    expect(suggestionsForPrefix(provider, editor, 'qu')).not.toContain('qu')

    editor.insertText(' qu')
    waitForBufferToStopChanging()
    expect(suggestionsForPrefix(provider, editor, 'qu')).toContain('qu')
  })

  it('does not return the word under the cursor when there is a suffix and only one instance of the word', () => {
    editor.moveToBottom()
    editor.insertText('catscats')
    editor.moveToBeginningOfLine()
    editor.insertText('omg')
    expect(suggestionsForPrefix(provider, editor, 'omg')).not.toContain('omg')
    expect(suggestionsForPrefix(provider, editor, 'omg')).not.toContain('omgcatscats')
  }
  )

  it('does not return the word under the cursors when are multiple cursors', () => {
    editor.moveToBottom()
    editor.setText('\n\n\n')
    editor.setCursorBufferPosition([0, 0])
    editor.addCursorAtBufferPosition([1, 0])
    editor.addCursorAtBufferPosition([2, 0])
    editor.insertText('omg')
    expect(suggestionsForPrefix(provider, editor, 'omg')).not.toContain('omg')
  })

  it('returns the word under the cursor when there is a suffix and there are multiple instances of the word', () => {
    editor.moveToBottom()
    editor.insertText('icksort')
    waitForBufferToStopChanging()
    editor.moveToBeginningOfLine()
    editor.insertText('qu')
    waitForBufferToStopChanging()

    expect(suggestionsForPrefix(provider, editor, 'qu')).not.toContain('qu')
    expect(suggestionsForPrefix(provider, editor, 'qu')).toContain('quicksort')
  })

  it('does not output suggestions from the other buffer', () => {
    let [coffeeEditor] = []

    waitsForPromise(() =>
      Promise.all([
        atom.packages.activatePackage('language-coffee-script'),
        atom.workspace.open('sample.coffee').then((e) => { coffeeEditor = e })
      ]))

    runs(() => {
      advanceClock(1) // build the new wordlist
      expect(suggestionsForPrefix(provider, coffeeEditor, 'item')).toHaveLength(0)
    })
  })

  describe('when `editor.largeFileMode` is true', () =>
    it("doesn't recompute symbols when the buffer changes", () => {
      let coffeeEditor = null

      waitsForPromise(() => atom.packages.activatePackage('language-coffee-script'))

      waitsForPromise(() =>
        atom.workspace.open('sample.coffee').then((e) => {
          coffeeEditor = e
          coffeeEditor.largeFileMode = true
        })
      )

      runs(() => {
        waitForBufferToStopChanging()
        coffeeEditor.setCursorBufferPosition([2, 0])
        expect(suggestionsForPrefix(provider, coffeeEditor, 'Some')).toEqual([])

        coffeeEditor.getBuffer().setTextInRange([[0, 0], [0, 0]], 'abc')
        waitForBufferToStopChanging()
        expect(suggestionsForPrefix(provider, coffeeEditor, 'abc')).toEqual([])
      })
    })
  )

  describe('when autocomplete-plus.minimumWordLength is > 1', () => {
    beforeEach(() => atom.config.set('autocomplete-plus.minimumWordLength', 3))

    it('only returns results when the prefix is at least the min word length', () => {
      editor.insertText('function aNewFunction(){};')
      advanceClock(provider.changeUpdateDelay)

      expect(suggestionsForPrefix(provider, editor, '')).not.toContain('aNewFunction')
      expect(suggestionsForPrefix(provider, editor, 'a')).not.toContain('aNewFunction')
      expect(suggestionsForPrefix(provider, editor, 'an')).not.toContain('aNewFunction')
      expect(suggestionsForPrefix(provider, editor, 'ane')).toContain('aNewFunction')
      expect(suggestionsForPrefix(provider, editor, 'anew')).toContain('aNewFunction')
    })
  })

  describe('when autocomplete-plus.minimumWordLength is 0', () => {
    beforeEach(() => atom.config.set('autocomplete-plus.minimumWordLength', 0))

    it('only returns results when the prefix is at least the min word length', () => {
      editor.insertText('function aNewFunction(){};')
      advanceClock(provider.changeUpdateDelay)

      expect(suggestionsForPrefix(provider, editor, '')).not.toContain('aNewFunction')
      expect(suggestionsForPrefix(provider, editor, 'a')).toContain('aNewFunction')
      expect(suggestionsForPrefix(provider, editor, 'an')).toContain('aNewFunction')
      expect(suggestionsForPrefix(provider, editor, 'ane')).toContain('aNewFunction')
      expect(suggestionsForPrefix(provider, editor, 'anew')).toContain('aNewFunction')
    })
  })

  describe("when the editor's path changes", () =>
    it('continues to track changes on the new path', () => {
      let buffer = editor.getBuffer()

      expect(provider.isWatchingEditor(editor)).toBe(true)
      expect(provider.isWatchingBuffer(buffer)).toBe(true)
      expect(suggestionsForPrefix(provider, editor, 'qu')).toContain('quicksort')

      buffer.setPath('cats.js')

      expect(provider.isWatchingEditor(editor)).toBe(true)
      expect(provider.isWatchingBuffer(buffer)).toBe(true)

      editor.moveToBottom()
      editor.moveToBeginningOfLine()
      expect(suggestionsForPrefix(provider, editor, 'qu')).toContain('quicksort')
      expect(suggestionsForPrefix(provider, editor, 'anew')).not.toContain('aNewFunction')
      editor.insertText('function aNewFunction(){};')
      waitForBufferToStopChanging()
      expect(suggestionsForPrefix(provider, editor, 'anew')).toContain('aNewFunction')
    })
  )

  describe('when multiple editors track the same buffer', () => {
    let [rightPane, rightEditor] = []
    beforeEach(() => {
      let pane = atom.workspace.paneForItem(editor)
      rightPane = pane.splitRight({copyActiveItem: true})
      rightEditor = rightPane.getItems()[0]

      expect(provider.isWatchingEditor(editor)).toBe(true)
      expect(provider.isWatchingEditor(rightEditor)).toBe(true)
    })

    it('watches the both the old and new editor for changes', () => {
      rightEditor.moveToBottom()
      rightEditor.moveToBeginningOfLine()

      expect(suggestionsForPrefix(provider, rightEditor, 'anew')).not.toContain('aNewFunction')
      rightEditor.insertText('function aNewFunction(){};')
      waitForBufferToStopChanging()
      expect(suggestionsForPrefix(provider, rightEditor, 'anew')).toContain('aNewFunction')

      editor.moveToBottom()
      editor.moveToBeginningOfLine()

      expect(suggestionsForPrefix(provider, editor, 'somenew')).not.toContain('someNewFunction')
      editor.insertText('function someNewFunction(){};')
      waitForBufferToStopChanging()
      expect(suggestionsForPrefix(provider, editor, 'somenew')).toContain('someNewFunction')
    })

    it('stops watching editors and removes content from symbol store as they are destroyed', () => {
      expect(suggestionsForPrefix(provider, editor, 'quick')).toContain('quicksort')

      let buffer = editor.getBuffer()
      editor.destroy()
      expect(provider.isWatchingBuffer(buffer)).toBe(true)
      expect(provider.isWatchingEditor(editor)).toBe(false)
      expect(provider.isWatchingEditor(rightEditor)).toBe(true)

      expect(suggestionsForPrefix(provider, editor, 'quick')).toContain('quicksort')
      expect(suggestionsForPrefix(provider, editor, 'anew')).not.toContain('aNewFunction')

      rightEditor.insertText('function aNewFunction(){};')
      waitForBufferToStopChanging()
      expect(suggestionsForPrefix(provider, editor, 'anew')).toContain('aNewFunction')

      rightPane.destroy()
      expect(provider.isWatchingBuffer(buffer)).toBe(false)
      expect(provider.isWatchingEditor(editor)).toBe(false)
      expect(provider.isWatchingEditor(rightEditor)).toBe(false)

      expect(suggestionsForPrefix(provider, editor, 'quick')).not.toContain('quicksort')
      expect(suggestionsForPrefix(provider, editor, 'anew')).not.toContain('aNewFunction')
    })
  })

  describe('when includeCompletionsFromAllBuffers is enabled', () => {
    beforeEach(() => {
      atom.config.set('autocomplete-plus.includeCompletionsFromAllBuffers', true)

      waitsForPromise(() =>
        Promise.all([
          atom.packages.activatePackage('language-coffee-script'),
          atom.workspace.open('sample.coffee').then((e) => { editor = e })
        ]))

      runs(() => advanceClock(1))
    })

    afterEach(() => atom.config.set('autocomplete-plus.includeCompletionsFromAllBuffers', false))

    it('outputs unique suggestions', () => {
      editor.setCursorBufferPosition([7, 0])
      let results = suggestionsForPrefix(provider, editor, 'qu')
      expect(results).toHaveLength(1)
    })

    it('outputs suggestions from the other buffer', () => {
      editor.setCursorBufferPosition([7, 0])
      let results = suggestionsForPrefix(provider, editor, 'item')
      expect(results[0]).toBe('items')
    })
  })

  describe('when the autocomplete.symbols changes between scopes', () => {
    beforeEach(() => {
      editor.setText(`// in-a-comment
inVar = "in-a-string"`
      )
      waitForBufferToStopChanging()

      let commentConfig = {
        incomment: {
          selector: '.comment'
        }
      }

      let stringConfig = {
        instring: {
          selector: '.string'
        }
      }

      atom.config.set('autocomplete.symbols', commentConfig, {scopeSelector: '.source.js .comment'})
      atom.config.set('autocomplete.symbols', stringConfig, {scopeSelector: '.source.js .string'})
    })

    it('uses the config for the scope under the cursor', () => {
      // Using the comment config
      editor.setCursorBufferPosition([0, 2])
      let suggestions = suggestionsForPrefix(provider, editor, 'in', {raw: true})
      expect(suggestions).toHaveLength(1)
      expect(suggestions[0].text).toBe('in-a-comment')
      expect(suggestions[0].type).toBe('incomment')

      // Using the string config
      editor.setCursorBufferPosition([1, 20])
      editor.insertText(' ')
      waitForBufferToStopChanging()
      suggestions = suggestionsForPrefix(provider, editor, 'in', {raw: true})
      expect(suggestions).toHaveLength(1)
      expect(suggestions[0].text).toBe('in-a-string')
      expect(suggestions[0].type).toBe('instring')

      // Using the default config
      editor.setCursorBufferPosition([1, Infinity])
      editor.insertText(' ')
      waitForBufferToStopChanging()
      suggestions = suggestionsForPrefix(provider, editor, 'in', {raw: true})
      expect(suggestions).toHaveLength(3)
      expect(suggestions[0].text).toBe('inVar')
      expect(suggestions[0].type).toBe('')
    })
  })

  describe('when the config contains a list of suggestion strings', () => {
    beforeEach(() => {
      editor.setText('// abcomment')
      waitForBufferToStopChanging()

      let commentConfig = {
        comment: { selector: '.comment' },
        builtin: {
          suggestions: ['abcd', 'abcde', 'abcdef']
        }
      }

      atom.config.set('autocomplete.symbols', commentConfig, {scopeSelector: '.source.js .comment'})
    })

    it('adds the suggestions to the results', () => {
      // Using the comment config
      editor.setCursorBufferPosition([0, 2])
      let suggestions = suggestionsForPrefix(provider, editor, 'ab', {raw: true})
      expect(suggestions).toHaveLength(4)
      expect(suggestions[0].text).toBe('abcomment')
      expect(suggestions[0].type).toBe('comment')
      expect(suggestions[1].text).toBe('abcd')
      expect(suggestions[1].type).toBe('builtin')
    })
  })

  describe('when the symbols config contains a list of suggestion objects', () => {
    beforeEach(() => {
      editor.setText('// abcomment')
      waitForBufferToStopChanging()

      let commentConfig = {
        comment: { selector: '.comment' },
        builtin: {
          suggestions: [
            {nope: 'nope1', rightLabel: 'will not be added to the suggestions'},
            {text: 'abcd', rightLabel: 'one', type: 'function'},
            []
          ]
        }
      }
      atom.config.set('autocomplete.symbols', commentConfig, {scopeSelector: '.source.js .comment'})
    })

    it('adds the suggestion objects to the results', () => {
      // Using the comment config
      editor.setCursorBufferPosition([0, 2])
      let suggestions = suggestionsForPrefix(provider, editor, 'ab', {raw: true})
      expect(suggestions).toHaveLength(2)
      expect(suggestions[0].text).toBe('abcomment')
      expect(suggestions[0].type).toBe('comment')
      expect(suggestions[1].text).toBe('abcd')
      expect(suggestions[1].type).toBe('function')
      expect(suggestions[1].rightLabel).toBe('one')
    })
  })

  describe('when the legacy completions array is used', () => {
    beforeEach(() => {
      editor.setText('// abcomment')
      waitForBufferToStopChanging()
      atom.config.set('editor.completions', ['abcd', 'abcde', 'abcdef'], {scopeSelector: '.source.js .comment'})
    })

    it('uses the config for the scope under the cursor', () => {
      // Using the comment config
      editor.setCursorBufferPosition([0, 2])
      let suggestions = suggestionsForPrefix(provider, editor, 'ab', {raw: true})
      expect(suggestions).toHaveLength(4)
      expect(suggestions[0].text).toBe('abcomment')
      expect(suggestions[0].type).toBe('')
      expect(suggestions[1].text).toBe('abcd')
      expect(suggestions[1].type).toBe('builtin')
    })
  })

  it('adds words to the wordlist with unicode characters', () => {
    atom.config.set('autocomplete-plus.enableExtendedUnicodeSupport', true)
    let suggestions = suggestionsForPrefix(provider, editor, 'somē', {raw: true})
    expect(suggestions).toHaveLength(0)
    editor.insertText('somēthingNew')
    editor.insertText(' ')
    waitForBufferToStopChanging()
    suggestions = suggestionsForPrefix(provider, editor, 'somē', {raw: true})
    expect(suggestions).toHaveLength(1)
  })
})
