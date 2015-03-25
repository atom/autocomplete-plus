RefCountedSymbolList = require '../lib/ref-counted-symbol-list'

describe 'RefCountedSymbolList', ->
  [list] = []
  beforeEach ->
    list = new RefCountedSymbolList

  describe "when words are added and removed from the list", ->
    it "maintains the word in the list until there are no more references", ->
      expect(list.getSymbols()).toEqual []

      list.addSymbol('abc')
      expect(list.getSymbols()).toEqual ['abc']

      list.addSymbol('abc')
      list.addSymbol('def')
      expect(list.getSymbols()).toEqual ['abc', 'def']

      list.removeSymbol('abc')
      expect(list.getSymbols()).toEqual ['abc', 'def']

      list.removeSymbol('def')
      expect(list.getSymbols()).toEqual ['abc']

      list.removeSymbol('abc')
      expect(list.getSymbols()).toEqual []

      list.removeSymbol('abc')
      expect(list.getSymbols()).toEqual []
