RefCountedTokenList = require '../lib/ref-counted-token-list'

describe 'RefCountedTokenList', ->
  [list] = []
  beforeEach ->
    list = new RefCountedTokenList

  describe "when words are added and removed from the list", ->
    it "maintains the word in the list until there are no more references", ->
      expect(list.getTokens()).toEqual []

      list.addToken('abc')
      expect(list.getTokens()).toEqual ['abc']

      list.addToken('abc')
      list.addToken('def')
      expect(list.getTokens()).toEqual ['abc', 'def']

      list.removeToken('abc')
      expect(list.getTokens()).toEqual ['abc', 'def']

      list.removeToken('def')
      expect(list.getTokens()).toEqual ['abc']

      list.removeToken('abc')
      expect(list.getTokens()).toEqual []

      list.removeToken('abc')
      expect(list.getTokens()).toEqual []
