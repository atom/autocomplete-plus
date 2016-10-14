'use babel'
/* eslint-env jasmine */

import RefCountedTokenList from '../lib/ref-counted-token-list'

describe('RefCountedTokenList', function () {
  let [list] = []
  beforeEach(() => {
    list = new RefCountedTokenList()
  })

  describe('::refCountForToken()', () =>
    it('returns the correct count', function () {
      list.addToken('abc')
      expect(list.refCountForToken('abc')).toBe(1)

      list.addToken('abc')
      list.addToken('def')
      expect(list.refCountForToken('abc')).toBe(2)

      list.removeToken('abc')
      expect(list.refCountForToken('abc')).toBe(1)

      list.removeToken('abc')
      expect(list.refCountForToken('abc')).toBe(0)

      list.removeToken('abc')
      return expect(list.refCountForToken('abc')).toBe(0)
    })
  )

  describe('when tokens are added to and removed from the list', () =>
    it('maintains the token in the list until there are no more references', function () {
      expect(list.getTokens()).toEqual([])

      list.addToken('abc')
      expect(list.getTokens()).toEqual(['abc'])
      expect(list.refCountForToken('abc')).toBe(1)

      list.addToken('abc')
      list.addToken('def')
      expect(list.getTokens()).toEqual(['abc', 'def'])
      expect(list.refCountForToken('abc')).toBe(2)

      list.removeToken('abc')
      expect(list.getTokens()).toEqual(['abc', 'def'])
      expect(list.refCountForToken('abc')).toBe(1)

      list.removeToken('def')
      expect(list.getTokens()).toEqual(['abc'])

      list.removeToken('abc')
      expect(list.getTokens()).toEqual([])

      list.removeToken('abc')
      return expect(list.getTokens()).toEqual([])
    })
  )

  return describe('when object tokens are added to and removed from the list', function () {
    describe('when the same tokens are used', () =>
      it('maintains the token in the list until there are no more references', function () {
        expect(list.getTokens()).toEqual([])

        let abcToken = {text: 'abc'}
        let defToken = {text: 'def'}
        list.addToken(abcToken, 'abc')
        expect(list.getTokens()).toEqual([abcToken])

        list.addToken(abcToken, 'abc')
        list.addToken(defToken, 'def')
        expect(list.getTokens()).toEqual([abcToken, defToken])

        list.removeToken(abcToken, 'abc')
        expect(list.getTokens()).toEqual([abcToken, defToken])

        list.removeToken(defToken, 'def')
        expect(list.getTokens()).toEqual([abcToken])

        list.removeToken(abcToken, 'abc')
        expect(list.getTokens()).toEqual([])

        list.removeToken(abcToken, 'abc')
        return expect(list.getTokens()).toEqual([])
      })
    )

    return describe('when tokens with the same key are used', () =>
      it('maintains the token in the list until there are no more references', function () {
        expect(list.getTokens()).toEqual([])

        list.addToken({text: 'abc'}, 'abc')
        expect(list.getTokens()).toEqual([{text: 'abc'}])

        list.addToken({text: 'abc'}, 'abc')
        list.addToken({text: 'def'}, 'def')
        expect(list.getTokens()).toEqual([{text: 'abc'}, {text: 'def'}])

        expect(list.removeToken({text: 'abc'}, 'abc')).toBe(true)
        expect(list.getTokens()).toEqual([{text: 'abc'}, {text: 'def'}])

        expect(list.removeToken('def')).toBe(true)
        expect(list.getTokens()).toEqual([{text: 'abc'}])

        expect(list.removeToken('abc')).toBe(true)
        expect(list.getTokens()).toEqual([])

        expect(list.removeToken('abc')).toBe(false)
        return expect(list.getTokens()).toEqual([])
      })
    )
  })
})
