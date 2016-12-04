'use babel'
/* eslint-env jasmine */

import SymbolStore from '../lib/symbol-store'
import { Selector } from 'selector-kit'

describe('SymbolStore', () => {
  let [store, editor] = []
  beforeEach(() => {
    waitsForPromise(() =>
      Promise.all([
        atom.packages.activatePackage('language-coffee-script'),
        atom.workspace.open('sample.coffee').then((e) => { editor = e })
      ]))

    runs(() => {
      store = new SymbolStore(/\b\w*[a-zA-Z_-]+\w*\b/g)

      editor.setText('')
      editor.getBuffer().onDidChange(({oldRange, newRange}) => store.recomputeSymbolsForEditorInBufferRange(editor, oldRange.start, oldRange.getExtent(), newRange.getExtent()))
    })
  })

  describe('::symbolsForConfig(config)', () => {
    it('gets a list of symbols matching the passed in configuration', () => {
      let config = {
        function: {
          selectors: Selector.create('.function'),
          typePriority: 1
        }
      }

      editor.setText('\n\nabc = -> cats\n\navar = 1')

      let occurrences = store.symbolsForConfig(config, null, 'ab')
      expect(occurrences.length).toBe(1)
      expect(occurrences[0].symbol.text).toBe('abc')
      expect(occurrences[0].symbol.type).toBe('function')
    })

    it('updates the symbol types as new tokens come in', () => {
      let config = {
        variable: {
          selectors: Selector.create('.variable'),
          typePriority: 2
        },
        function: {
          selectors: Selector.create('.function'),
          typePriority: 3
        },
        class: {
          selectors: Selector.create('.class.name'),
          typePriority: 4
        }
      }

      editor.setText('\n\nabc = -> cats\n\navar = 1')
      let occurrences = store.symbolsForConfig(config, null, 'a')

      expect(occurrences.length).toBe(2)
      expect(occurrences[0].symbol.text).toBe('abc')
      expect(occurrences[0].symbol.type).toBe('function')
      expect(occurrences[1].symbol.text).toBe('avar')
      expect(occurrences[1].symbol.type).toBe('variable')

      editor.setCursorBufferPosition([0, 0])
      editor.insertText('class abc')
      occurrences = store.symbolsForConfig(config, null, 'a')

      expect(occurrences.length).toBe(2)
      expect(occurrences[0].symbol.text).toBe('abc')
      expect(occurrences[0].symbol.type).toBe('class')
      expect(occurrences[1].symbol.text).toBe('avar')
      expect(occurrences[1].symbol.type).toBe('variable')
    })

    it('returns symbols with an empty type', () => {
      let config = {
        '': {
          selectors: Selector.create('.function'),
          typePriority: 1
        }
      }

      editor.setText('\n\nabc = -> cats\n\navar = 1')
      let occurrences = store.symbolsForConfig(config, null, 'a')

      expect(occurrences.length).toBe(1)
      expect(occurrences[0].symbol.text).toBe('abc')
      expect(occurrences[0].symbol.type).toBe('')
    })

    it('resets the types when a new config is used', () => {
      let config = {
        'function': {
          selectors: Selector.create('.function'),
          typePriority: 1
        }
      }

      editor.setText('\n\nabc = -> cats\n\navar = 1')
      let occurrences = store.symbolsForConfig(config, null, 'a')

      expect(occurrences.length).toBe(1)
      expect(occurrences[0].symbol.text).toBe('abc')
      expect(occurrences[0].symbol.type).toBe('function')

      config = {
        'newtype': {
          selectors: Selector.create('.function'),
          typePriority: 1
        }
      }

      editor.setText('\n\nabc = -> cats\n\navar = 1')
      occurrences = store.symbolsForConfig(config, null, 'a')

      expect(occurrences.length).toBe(1)
      expect(occurrences[0].symbol.text).toBe('abc')
      expect(occurrences[0].symbol.type).toBe('newtype')
    })

    it('doesn\'t override built-in suggestions with the symbols found in the buffer', () => {
      let config = {
        'function': {
          selectors: Selector.create('.function'),
          typePriority: 1
        },
        'builtins': {
          suggestions: [{
            type: 'function',
            rightLabel: 'global function',
            text: 'ValueFromFile',
            description: 'Test description.'
          }]
        }
      }

      editor.moveToBottom()
      editor.insertText('ValueFromFile()')

      let occurrences = store.symbolsForConfig(config, [editor.getBuffer()], 'value')
      expect(occurrences.length).toBe(1)
      expect(occurrences[0].symbol.text).toBe('ValueFromFile')
      expect(occurrences[0].symbol.description).toBe('Test description.')
      expect(occurrences[0].symbol.rightLabel).toBe('global function')
    })
  })

  describe('when there are multiple files with tokens in the store', () => {
    let [config, editor1, editor2] = []
    beforeEach(() => {
      config = {stuff: { selectors: Selector.create('.text.plain.null-grammar') }}

      waitsForPromise(() =>
        Promise.all([
          atom.workspace.open('one.txt').then((editor) => { editor1 = editor }),
          atom.workspace.open('two.txt').then((editor) => { editor2 = editor })
        ]))

      runs(() => {
        editor1.moveToBottom()
        editor1.insertText(' humongous hill')

        editor2.moveToBottom()
        editor2.insertText(' hello hola')

        let start = {row: 0, column: 0}
        let oldExtent = {row: 0, column: 0}
        store.recomputeSymbolsForEditorInBufferRange(editor1, start, oldExtent, editor1.getBuffer().getRange().getExtent())
        store.recomputeSymbolsForEditorInBufferRange(editor2, start, oldExtent, editor2.getBuffer().getRange().getExtent())
      })
    })

    describe('::symbolsForConfig(config)', () =>
      it('returs symbols based on path', () => {
        let occurrences = store.symbolsForConfig(config, [editor1.getBuffer()], 'h')
        expect(occurrences).toHaveLength(2)
        expect(occurrences[0].symbol.text).toBe('humongous')
        expect(occurrences[1].symbol.text).toBe('hill')

        occurrences = store.symbolsForConfig(config, [editor2.getBuffer()], 'h')
        expect(occurrences).toHaveLength(2)
        expect(occurrences[0].symbol.text).toBe('hello')
        expect(occurrences[1].symbol.text).toBe('hola')
      })
    )

    describe('::clear()', () =>
      describe('when a buffer is specified', () =>
        it('removes only the path specified', () => {
          let occurrences = store.symbolsForConfig(config, null, 'h')
          expect(occurrences).toHaveLength(4)
          expect(occurrences[0].symbol.text).toBe('humongous')
          expect(occurrences[1].symbol.text).toBe('hill')
          expect(occurrences[2].symbol.text).toBe('hello')
          expect(occurrences[3].symbol.text).toBe('hola')

          store.clear(editor1.getBuffer())

          occurrences = store.symbolsForConfig(config, null, 'h')
          expect(occurrences).toHaveLength(2)
          expect(occurrences[0].symbol.text).toBe('hello')
          expect(occurrences[1].symbol.text).toBe('hola')
        })
      )
    )
  })
})
