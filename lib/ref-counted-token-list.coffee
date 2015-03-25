module.exports =
class RefCountedTokenList
  constructor: ->
    @clear()

  clear: ->
    @references = {}
    @tokens = []

  getTokens: -> @tokens

  getLength: -> @tokens.length

  getToken: (tokenText) ->
    tokenKey = @getTokenKey(tokenText)
    @references[tokenKey]?.token

  addToken: (token, textKey) ->
    tokenKey = @getTokenKey(token, textKey)
    @updateRefCount(tokenKey, token, 1)

  removeToken: (token, textKey) ->
    tokenKey = @getTokenKey(token, textKey)
    @updateRefCount(tokenKey, token, -1)

  ###
  Private Methods
  ###

  updateRefCount: (tokenKey, token, increment) ->
    if increment > 0 and not @references[tokenKey]?
      @references[tokenKey] ?= {token, count: 0}
      @addTokenToList(token)

    @references[tokenKey].count += increment if @references[tokenKey]?

    if @references[tokenKey]?.count <= 0
      delete @references[tokenKey]
      @removeTokenFromList(token)

  addTokenToList: (token) ->
    @tokens.push(token)

  removeTokenFromList: (token) ->
    index = @tokens.indexOf(token)
    @tokens.splice(index, 1) if index > -1

  getTokenKey: (token, textKey) ->
    tokenText = token
    tokenText = token[textKey] if textKey?
    # some words are reserved, like 'constructor' :/
    tokenText + '$$'
