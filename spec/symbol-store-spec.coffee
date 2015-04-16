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
      buffer.onWillChange ({oldRange, newRange}) ->
        store.removeTokensInBufferRange(editor, oldRange)
        store.adjustBufferRows(editor, oldRange, newRange)
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

  it "keeps track of token buffer rows after changes to the buffer", ->
    getSymbolBufferRows = (symbol) ->
      store.getSymbol(symbol).bufferRowsForBufferPath(editor.getPath())

    editor.setText('\n\nabc = ->')
    expect(getSymbolBufferRows('abc')).toEqual [2]

    editor.setCursorBufferPosition([0, 0])
    editor.insertNewline()
    expect(getSymbolBufferRows('abc')).toEqual [3]

    editor.setText """
      abc: ->
        onetwo = [one, two]
        multipleLines = 'multipleLines'
        yeah = 'ok'
        multipleLines += 'ok'
    """
    expect(getSymbolBufferRows('abc')).toEqual [0]
    expect(getSymbolBufferRows('onetwo')).toEqual [1]
    expect(getSymbolBufferRows('one')).toEqual [1]
    expect(getSymbolBufferRows('two')).toEqual [1]
    expect(getSymbolBufferRows('multipleLines')).toEqual [2, 2, 4]
    expect(getSymbolBufferRows('yeah')).toEqual [3]
    expect(getSymbolBufferRows('ok')).toEqual [3, 4]

    editor.setSelectedBufferRange([[2, 18], [3, 13]])
    editor.insertText("'ok'")

    expect(getSymbolBufferRows('abc')).toEqual [0]
    expect(getSymbolBufferRows('onetwo')).toEqual [1]
    expect(getSymbolBufferRows('one')).toEqual [1]
    expect(getSymbolBufferRows('two')).toEqual [1]
    expect(getSymbolBufferRows('multipleLines')).toEqual [2, 3]
    expect(store.getSymbol('yeah')).toBeUndefined()
    expect(getSymbolBufferRows('ok')).toEqual [2, 3]

    editor.insertText("\n\nomg = 'ok'; multipleLines += 'wow'\n\n")

    expect(getSymbolBufferRows('abc')).toEqual [0]
    expect(getSymbolBufferRows('onetwo')).toEqual [1]
    expect(getSymbolBufferRows('one')).toEqual [1]
    expect(getSymbolBufferRows('two')).toEqual [1]
    expect(getSymbolBufferRows('wow')).toEqual [4]
    expect(getSymbolBufferRows('multipleLines')).toEqual [2, 4, 7]
    expect(getSymbolBufferRows('ok')).toEqual [2, 4, 7]

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

  describe "when there are multiple files with tokens in the store", ->
    beforeEach ->
      store.addToken({value: 'one', scopes: ['source.coffee']}, 'one.txt', 1)
      store.addToken({value: 'ok', scopes: ['source.coffee']}, 'one.txt', 1)
      store.addToken({value: 'wow', scopes: ['source.coffee']}, 'one.txt', 2)
      store.addToken({value: 'wow', scopes: ['source.coffee']}, 'one.txt', 2)

      store.addToken({value: 'two', scopes: ['source.coffee']}, 'two.txt', 1)
      store.addToken({value: 'ok', scopes: ['source.coffee']}, 'two.txt', 1)
      store.addToken({value: 'wow', scopes: ['source.coffee']}, 'two.txt', 2)

    describe "::symbolsForConfig(config)", ->
      it "returs symbols based on path", ->
        config =
          stuff:
            selectors: Selector.create('.source')
        symbols = store.symbolsForConfig(config, 'one.txt')
        expect(symbols).toHaveLength 3
        expect(symbols[0].text).toBe 'one'
        expect(symbols[1].text).toBe 'ok'
        expect(symbols[2].text).toBe 'wow'

    describe "::clear()", ->
      describe "when an bufferPaths is specified", ->
        it "removes only the path specified", ->
          config =
            stuff:
              selectors: Selector.create('.source')

          symbols = store.symbolsForConfig(config)
          expect(symbols).toHaveLength 4
          expect(symbols[0].text).toBe 'one'
          expect(symbols[1].text).toBe 'ok'
          expect(symbols[2].text).toBe 'wow'
          expect(symbols[3].text).toBe 'two'

          expect(store.getSymbol('one').getCount()).toBe 1
          expect(store.getSymbol('two').getCount()).toBe 1
          expect(store.getSymbol('ok').getCount()).toBe 2
          expect(store.getSymbol('wow').getCount()).toBe 3

          store.clear('one.txt')
          symbols = store.symbolsForConfig(config)
          expect(symbols).toHaveLength 3
          expect(symbols[0].text).toBe 'ok'
          expect(symbols[1].text).toBe 'wow'
          expect(symbols[2].text).toBe 'two'

          expect(store.getSymbol('one')).toBeUndefined()
          expect(store.getSymbol('two').getCount()).toBe 1
          expect(store.getSymbol('ok').getCount()).toBe 1
          expect(store.getSymbol('wow').getCount()).toBe 1
