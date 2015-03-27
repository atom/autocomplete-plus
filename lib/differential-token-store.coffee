RefCountedTokenList = require './ref-counted-token-list'

# This computes the XOR of tokens between buffer change events.
# Used in the SymbolProvider.
#
# The expectation is that on a
# * buffer::onWillChange event, all the relevant tokens will be _removed_ from this object
# * buffer::onDidChange event, all the relevant tokens will be _added_ to this object
#
# The complexity here is in bufferRow tracking, which is not perfect.
module.exports =
class DifferentialTokenStore
  tokensForRemoval: new RefCountedTokenList
  tokensForAddition: new RefCountedTokenList

  clear: ->
    @tokensForRemoval.clear()
    @tokensForAddition.clear()

  add: (token, editorPath, bufferRow) ->
    @updateReferenceCounters(@tokensForRemoval, @tokensForAddition, token, editorPath, bufferRow)

  remove: (token, editorPath, bufferRow) ->
    @updateReferenceCounters(@tokensForAddition, @tokensForRemoval, token, editorPath, bufferRow)

  updateReferenceCounters: (counterToRemoveFrom, counterToAddTo, token, editorPath, bufferRow) ->
    return unless token.value.trim()

    tokenKey = @keyForToken(token)
    if counterToRemoveFrom.removeToken(tokenKey)
      tokenWrapper = counterToRemoveFrom.getTokenWrapper(tokenKey)

      # BufferRow tracking is not bullet proof as the row for a give token may
      # have changed. An error here will throw off the locality scoring.
      bufferRows = tokenWrapper?.bufferRowsForEditorPath?[editorPath]
      removeItemFromArray(bufferRows, bufferRow) if bufferRows?
    else
      counterToAddTo.addToken(token, tokenKey)

      # Abusing the token list to keep track of buffer rows. The token list
      # makes a wrapper object for each token.
      tokenWrapper = counterToAddTo.getTokenWrapper(tokenKey)
      tokenWrapper.bufferRowsForEditorPath ?= {}
      tokenWrapper.bufferRowsForEditorPath[editorPath] ?= []
      tokenWrapper.bufferRowsForEditorPath[editorPath].unshift(bufferRow)

  keyForToken: (token) =>
    token.value + token.scopes.join(',')

removeItemFromArray = (array, item) ->
  index = array.indexOf(item)
  array.splice(index, 1) if index > -1
