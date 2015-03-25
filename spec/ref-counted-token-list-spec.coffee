RefCountedTokenList = require '../lib/ref-counted-token-list'

describe 'RefCountedTokenList', ->
  [list] = []
  beforeEach ->
    list = new RefCountedTokenList

  describe "when tokens are added to and removed from the list", ->
    it "maintains the token in the list until there are no more references", ->
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

  describe "when object tokens are added to and removed from the list", ->
    it "maintains the token in the list until there are no more references", ->
      expect(list.getTokens()).toEqual []

      abcToken = {text: 'abc'}
      defToken = {text: 'def'}
      list.addToken(abcToken, 'text')
      expect(list.getTokens()).toEqual [abcToken]

      list.addToken(abcToken, 'text')
      list.addToken(defToken, 'text')
      expect(list.getTokens()).toEqual [abcToken, defToken]

      list.removeToken(abcToken, 'text')
      expect(list.getTokens()).toEqual [abcToken, defToken]

      list.removeToken(defToken, 'text')
      expect(list.getTokens()).toEqual [abcToken]

      list.removeToken(abcToken, 'text')
      expect(list.getTokens()).toEqual []

      list.removeToken(abcToken, 'text')
      expect(list.getTokens()).toEqual []
