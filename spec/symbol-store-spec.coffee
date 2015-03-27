SymbolStore = require '../lib/symbol-store'
{TextEditor} = require 'atom'

###
symbolProviderState =
  'abc$$':
    text: 'abc'
    cachedType: "function" # invalidated when a scope is added/removed
    metadataByPath:
      '/foo/bar/baz':
        scopes:
          ".source.coffee .function": 3
          ".source.coffee .variable": 1
        bufferRows: [0, 1, 5, 7, 11, 20, 22] # could be updated by row delta on change via binary-search
###

fdescribe 'SymbolStore', ->
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

  it "", ->
    expect(store.getLength()).toBe 0

    editor.setText('\n\nabc = ->')
    expect(store.getSymbol('abc').getCount()).toBe 1

    editor.setText('')
    expect(store.getSymbol('abc')).toBeUndefined()

    editor.setText('\n\nabc ->\nabc = 34')
    expect(store.getSymbol('abc').getCount()).toBe 2

    editor.setText('\n\nabc ->')
    expect(store.getSymbol('abc').getCount()).toBe 1
