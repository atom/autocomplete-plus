module.exports =
class RefCountedTokenList
  constructor: ->
    @clear()

  clear: ->
    @references = {}
    @tokens = []

  getLength: -> @tokens.length

  getTokens: -> @tokens

  getTokenWrappers: ->
    (tokenWrapper for key, tokenWrapper of @references)

  getToken: (tokenKey) ->
    @getTokenWrapper(tokenKey)?.token

  getTokenWrapper: (tokenKey) ->
    tokenKey = @getTokenKey(tokenKey)
    @references[tokenKey]

  refCountForToken: (tokenKey) ->
    tokenKey = @getTokenKey(tokenKey)
    @references[tokenKey]?.count ? 0

  addToken: (token, tokenKey) ->
    tokenKey = @getTokenKey(token, tokenKey)
    @updateRefCount(tokenKey, token, 1)

  # Returns true when the token was removed
  # Returns false when the token was not present and thus not removed
  removeToken: (token, tokenKey) ->
    tokenKey = @getTokenKey(token, tokenKey)
    if @references[tokenKey]?
      token = @references[tokenKey].token
      @updateRefCount(tokenKey, token, -1)
      true
    else
      false

  ###
  Private Methods
  ###

  updateRefCount: (tokenKey, token, increment) ->
    if increment > 0 and not @references[tokenKey]?
      @references[tokenKey] ?= {tokenKey, token, count: 0}
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

  getTokenKey: (token, tokenKey) ->
    # some words are reserved, like 'constructor' :/
    (tokenKey ? token) + '$$'
