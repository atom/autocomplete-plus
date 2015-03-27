RefCountedTokenList = require './ref-counted-token-list'

class Symbol
  count: 0
  metadataByPath: {}

  constructor: (@text) ->
    console.log @text

  getCount: -> @count

  addInstance: (editorPath, bufferRow, scopes) ->
    @metadataByPath[editorPath] ?= {}
    @metadataByPath[editorPath].bufferRows ?= []
    @metadataByPath[editorPath].bufferRows.push bufferRow
    @metadataByPath[editorPath].scopes ?= {}
    @metadataByPath[editorPath].scopes[scopes] ?= 0
    @metadataByPath[editorPath].scopes[scopes] += 1
    @count += 1

  removeInstance: (editorPath, bufferRow, scopes) ->
    return unless @metadataByPath[editorPath]?

    bufferRows = @metadataByPath[editorPath].bufferRows
    removeItemFromArray(bufferRows, bufferRow) if bufferRows?

    if @metadataByPath[editorPath].scopes[scopes]?
      @count -= 1
      @metadataByPath[editorPath].scopes[scopes] -= 1

      if @metadataByPath[editorPath].scopes[scopes] is 0
        delete @metadataByPath[editorPath].scopes[scopes]

      if getObjectLength(@metadataByPath[editorPath].scopes) is 0
        delete @metadataByPath[editorPath]

module.exports =
class SymbolStore
  constructor: (@wordRegex) ->
    @clear()

  clear: ->
    @symbolMap = {}
    @symbols = []

  getLength: -> @symbols.length

  getSymbol: (symbolKey) ->
    symbolKey = @getKey(symbolKey)
    @symbolMap[symbolKey]

  addToken: (token, editorPath, bufferRow) =>
    # This could be made async...
    text = @getTokenText(token)
    scopes = @getTokenScopes(token)
    matches = text.match(@wordRegex)
    if matches?
      @addSymbol(symbolText, editorPath, bufferRow, scopes) for symbolText in matches
    return

  removeToken: (token, editorPath, bufferRow) =>
    # This could be made async...
    text = @getTokenText(token)
    scopes = @getTokenScopes(token)
    matches = text.match(@wordRegex)
    if matches?
      @removeSymbol(symbolText, editorPath, bufferRow, scopes) for symbolText in matches
    return

  addTokensInBufferRange: (editor, bufferRange) ->
    @operateOnTokensInBufferRange(editor, bufferRange, @addToken)

  removeTokensInBufferRange: (editor, bufferRange) ->
    @operateOnTokensInBufferRange(editor, bufferRange, @removeToken)

  operateOnTokensInBufferRange: (editor, bufferRange, operatorFunc) ->
    tokenizedLines = @getTokenizedLines(editor)[bufferRange.start.row..bufferRange.end.row]
    bufferRowBase = bufferRange.start.row
    for {tokens}, bufferRowIndex in tokenizedLines
      bufferRow = bufferRowBase + bufferRowIndex
      for token in tokens
        operatorFunc(token, editor.getPath(), bufferRow)

  ###
  Private Methods
  ###

  addSymbol: (symbolText, editorPath, bufferRow, scopes) ->
    symbolKey = @getKey(symbolText)
    symbol = @symbolMap[symbolKey]
    unless symbol?
      @symbolMap[symbolKey] = symbol = new Symbol(symbolText)
      @addSymbolToList(symbol)

    symbol.addInstance(editorPath, bufferRow, scopes)

  removeSymbol: (symbolText, editorPath, bufferRow, scopes) =>
    symbolKey = @getKey(symbolText)
    symbol = @symbolMap[symbolKey]
    if symbol?
      symbol.removeInstance(editorPath, bufferRow, scopes)
      delete @symbolMap[symbolKey] if symbol.getCount() is 0

  addSymbolToList: (symbol) ->
    @symbols.push(symbol)

  removeSymbolFromList: (symbol) ->
    index = @symbols.indexOf(symbol)
    @symbols.splice(index, 1) if index > -1

  getTokenizedLines: (editor) ->
    # Warning: displayBuffer and tokenizedBuffer are private APIs. Please do not
    # copy into your own package. If you do, be prepared to have it break
    # without warning.
    editor.displayBuffer.tokenizedBuffer.tokenizedLines

  getTokenText: (token) -> token.value

  getTokenScopes: (token) ->
    selector = ''
    selector += ' .' + scope for scope in token.scopes
    selector

  getKey: (value) ->
    # some words are reserved, like 'constructor' :/
    value + '$$'

removeItemFromArray = (array, item) ->
  index = array.indexOf(item)
  array.splice(index, 1) if index > -1

getObjectLength = (object) ->
  count = 0
  count += 1 for k, v of object
  count
