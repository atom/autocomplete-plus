SymbolStore = require '../lib/symbol-store'
{TextEditor} = require 'atom'
{Selector} = require 'selector-kit'

describe 'SymbolStore', ->
  [store, editor, buffer] = []
  beforeEach ->
    waitsForPromise ->
      Promise.all [
        atom.packages.activatePackage("language-coffee-script")
        atom.workspace.open('sample.coffee').then (e) -> editor = e
      ]

    runs ->
      store = new SymbolStore(/\b\w*[a-zA-Z_-]+\w*\b/g)

      editor.setText('')
      buffer = editor.getBuffer()
      buffer.onWillChange ({oldRange}) ->
        store.removeTokensInBufferRange(editor, oldRange)
      buffer.onDidChange ({newRange}) ->
        store.addTokensInBufferRange(editor, newRange)

  it "adds and removes symbols and counts references", ->
    expect(store.getLength()).toBe 0

    editor.setText('\n\nabc = ->')
    expect(store.getLength()).toBe 1
    expect(store.getSymbol('abc').getCount()).toBe 1

    editor.setText('')
    expect(store.getLength()).toBe 0
    expect(store.getSymbol('abc')).toBeUndefined()

    editor.setText('\n\nabc = ->\nabc = 34')
    expect(store.getLength()).toBe 1
    expect(store.getSymbol('abc').getCount()).toBe 2

    editor.setText('\n\nabc = ->')
    expect(store.getLength()).toBe 1
    expect(store.getSymbol('abc').getCount()).toBe 1

  describe "::symbolsForConfig(config)", ->
    it "gets a list of symbols matching the passed in configuration", ->
      config =
        function:
          selectors: Selector.create('.function')
          typePriority: 1

      editor.setText('\n\nabc = -> cats\n\navar = 1')
      expect(store.getLength()).toBe 3

      symbols = store.symbolsForConfig(config)

      expect(symbols.length).toBe 1
      expect(symbols[0].text).toBe 'abc'
      expect(symbols[0].type).toBe 'function'

    it "updates the symbol types as new tokens come in", ->
      config =
        variable:
          selectors: Selector.create('.variable')
          typePriority: 2
        function:
          selectors: Selector.create('.function')
          typePriority: 3
        class:
          selectors: Selector.create('.class.name')
          typePriority: 4

      editor.setText('\n\nabc = -> cats\n\navar = 1')
      symbols = store.symbolsForConfig(config)

      expect(symbols.length).toBe 2
      expect(symbols[0].text).toBe 'abc'
      expect(symbols[0].type).toBe 'function'
      expect(symbols[1].text).toBe 'avar'
      expect(symbols[1].type).toBe 'variable'

      editor.setCursorBufferPosition([0, 0])
      editor.insertText('class abc')
      symbols = store.symbolsForConfig(config)

      expect(symbols.length).toBe 2
      expect(symbols[0].text).toBe 'abc'
      expect(symbols[0].type).toBe 'class'
      expect(symbols[1].text).toBe 'avar'
      expect(symbols[1].type).toBe 'variable'

    it "returns symbols with an empty type", ->
      config =
        '':
          selectors: Selector.create('.function')
          typePriority: 1

      editor.setText('\n\nabc = -> cats\n\navar = 1')
      symbols = store.symbolsForConfig(config)

      expect(symbols.length).toBe 1
      expect(symbols[0].text).toBe 'abc'
      expect(symbols[0].type).toBe ''

    it "resets the types when a new config is used", ->
      config =
        'function':
          selectors: Selector.create('.function')
          typePriority: 1

      editor.setText('\n\nabc = -> cats\n\navar = 1')
      symbols = store.symbolsForConfig(config)

      expect(symbols.length).toBe 1
      expect(symbols[0].text).toBe 'abc'
      expect(symbols[0].type).toBe 'function'

      config =
        'newtype':
          selectors: Selector.create('.function')
          typePriority: 1

      editor.setText('\n\nabc = -> cats\n\navar = 1')
      symbols = store.symbolsForConfig(config)

      expect(symbols.length).toBe 1
      expect(symbols[0].text).toBe 'abc'
      expect(symbols[0].type).toBe 'newtype'
