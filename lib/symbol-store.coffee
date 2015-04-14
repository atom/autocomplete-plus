RefCountedTokenList = require './ref-counted-token-list'
{selectorsMatchScopeChain} = require './scope-helpers'

class Symbol
  count: 0
  metadataByPath: null
  cachedConfig: null

  type: null

  constructor: (@text) ->
    @metadataByPath = {}

  getCount: -> @count

  bufferRowsForEditorPath: (editorPath) ->
    @metadataByPath[editorPath]?.bufferRows

  adjustBufferRows: (editorPath, adjustmentStartRow, adjustmentDelta) ->
    bufferRows = @metadataByPath[editorPath].bufferRows
    return unless bufferRows?
    index = binaryIndexOf(bufferRows, adjustmentStartRow)
    length = bufferRows.length
    while index < length
      bufferRows[index] += adjustmentDelta
      index++
    return

  addInstance: (editorPath, bufferRow, scopeChain) ->
    @metadataByPath[editorPath] ?= {}
    @addBufferRow(editorPath, bufferRow)
    @metadataByPath[editorPath].scopeChains ?= {}
    unless @metadataByPath[editorPath].scopeChains[scopeChain]?
      @type = null
      @metadataByPath[editorPath].scopeChains[scopeChain] = 0
    @metadataByPath[editorPath].scopeChains[scopeChain] += 1
    @count += 1

  removeInstance: (editorPath, bufferRow, scopeChain) ->
    return unless @metadataByPath[editorPath]?

    @removeBufferRow(editorPath, bufferRow)

    if @metadataByPath[editorPath].scopeChains[scopeChain]?
      @count -= 1
      @metadataByPath[editorPath].scopeChains[scopeChain] -= 1

      if @metadataByPath[editorPath].scopeChains[scopeChain] is 0
        delete @metadataByPath[editorPath].scopeChains[scopeChain]
        @type = null

      if getObjectLength(@metadataByPath[editorPath].scopeChains) is 0
        delete @metadataByPath[editorPath]

  addBufferRow: (editorPath, row) ->
    @metadataByPath[editorPath].bufferRows ?= []
    bufferRows = @metadataByPath[editorPath].bufferRows
    index = binaryIndexOf(bufferRows, row)
    bufferRows.splice(index, 0, row)

  removeBufferRow: (editorPath, row) ->
    bufferRows = @metadataByPath[editorPath].bufferRows
    return unless bufferRows
    index = binaryIndexOf(bufferRows, row)
    bufferRows.splice(index, 1) if bufferRows[index] is row

  isSingleInstanceOf: (word) ->
    @text is word and @count is 1

  appliesToConfig: (config) ->
    @type = null if @cachedConfig isnt config

    unless @type?
      typePriority = 0
      for type, options of config
        continue unless options.selectors?
        for filePath, {scopeChains} of @metadataByPath
          for scopeChain, __ of scopeChains
            if (!@type or options.typePriority > typePriority) and selectorsMatchScopeChain(options.selectors, scopeChain)
              @type = type
              typePriority = options.typePriority
      @cachedConfig = config

    @type?

module.exports =
class SymbolStore
  count: 0

  constructor: (@wordRegex) ->
    @clear()

  clear: ->
    @symbolMap = {}

  getLength: -> @count

  getSymbol: (symbolKey) ->
    symbolKey = @getKey(symbolKey)
    @symbolMap[symbolKey]

  symbolsForConfig: (config, wordUnderCursor) ->
    symbols = []
    for symbolKey, symbol of @symbolMap
      symbols.push(symbol) if symbol.appliesToConfig(config) and not symbol.isSingleInstanceOf(wordUnderCursor)
    for type, options of config
      symbols = symbols.concat(options.suggestions) if options.suggestions
    symbols

  adjustBufferRows: (editor, oldRange, newRange) ->
    adjustmentStartRow = oldRange.end.row + 1
    adjustmentDelta = newRange.getRowCount() - oldRange.getRowCount()
    for key, symbol of @symbolMap
      symbol.adjustBufferRows(editor.getPath(), adjustmentStartRow, adjustmentDelta)
    return


  addToken: (token, editorPath, bufferRow) =>
    # This could be made async...
    text = @getTokenText(token)
    scopeChain = @getTokenScopeChain(token)
    matches = text.match(@wordRegex)
    if matches?
      @addSymbol(symbolText, editorPath, bufferRow, scopeChain) for symbolText in matches
    return

  removeToken: (token, editorPath, bufferRow) =>
    # This could be made async...
    text = @getTokenText(token)
    scopeChain = @getTokenScopeChain(token)
    matches = text.match(@wordRegex)
    if matches?
      @removeSymbol(symbolText, editorPath, bufferRow, scopeChain) for symbolText in matches
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
    return

  ###
  Private Methods
  ###

  addSymbol: (symbolText, editorPath, bufferRow, scopeChain) ->
    symbolKey = @getKey(symbolText)
    symbol = @symbolMap[symbolKey]
    unless symbol?
      @symbolMap[symbolKey] = symbol = new Symbol(symbolText)
      @count += 1

    symbol.addInstance(editorPath, bufferRow, scopeChain)

  removeSymbol: (symbolText, editorPath, bufferRow, scopeChain) =>
    symbolKey = @getKey(symbolText)
    symbol = @symbolMap[symbolKey]
    if symbol?
      symbol.removeInstance(editorPath, bufferRow, scopeChain)
      if symbol.getCount() is 0
        delete @symbolMap[symbolKey]
        @count -= 1

  getTokenizedLines: (editor) ->
    # Warning: displayBuffer and tokenizedBuffer are private APIs. Please do not
    # copy into your own package. If you do, be prepared to have it break
    # without warning.
    editor.displayBuffer.tokenizedBuffer.tokenizedLines

  getTokenText: (token) -> token.value

  getTokenScopeChain: (token) ->
    scopeChain = ''
    scopeChain += ' .' + scope for scope in token.scopes
    scopeChain

  getKey: (value) ->
    # some words are reserved, like 'constructor' :/
    value + '$$'

getObjectLength = (object) ->
  count = 0
  count += 1 for k, v of object
  count

binaryIndexOf = (array, searchElement) ->
  minIndex = 0
  maxIndex = array.length - 1

  while minIndex <= maxIndex
    currentIndex = (minIndex + maxIndex) / 2 | 0
    currentElement = array[currentIndex]

    if currentElement < searchElement
      minIndex = currentIndex + 1
    else if (currentElement > searchElement)
      maxIndex = currentIndex - 1
    else
      return currentIndex

  minIndex
