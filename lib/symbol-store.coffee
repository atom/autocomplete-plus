RefCountedTokenList = require './ref-counted-token-list'
{selectorsMatchScopeChain} = require './scope-helpers'

class Symbol
  count: 0
  metadataByPath: null
  cachedConfig: null

  type: null

  constructor: (@text) ->
    @metadataByPath = new Map

  getCount: -> @count

  bufferRowsForBuffer: (buffer) ->
    @metadataByPath.get(buffer)?.bufferRows

  countForBuffer: (buffer) ->
    metadata = @metadataByPath.get(buffer)
    bufferCount = 0
    if metadata?
      bufferCount += scopeCount for scopeChain, scopeCount of metadata.scopeChains
    bufferCount

  clearForBuffer: (buffer) ->
    bufferCount = @countForBuffer(buffer)
    if bufferCount > 0
      @count -= bufferCount
      delete @metadataByPath.get(buffer)

  adjustBufferRows: (buffer, adjustmentStartRow, adjustmentDelta) ->
    bufferRows = @metadataByPath.get(buffer)?.bufferRows
    return unless bufferRows?
    index = binaryIndexOf(bufferRows, adjustmentStartRow)
    length = bufferRows.length
    while index < length
      bufferRows[index] += adjustmentDelta
      index++
    return

  addInstance: (buffer, bufferRow, scopeChain) ->
    metadata = @metadataByPath.get(buffer)
    unless metadata?
      metadata ?= {}
      @metadataByPath.set(buffer, metadata)

    @addBufferRow(buffer, bufferRow)
    metadata.scopeChains ?= {}
    unless metadata.scopeChains[scopeChain]?
      @type = null
      metadata.scopeChains[scopeChain] = 0
    metadata.scopeChains[scopeChain] += 1
    @count += 1

  removeInstance: (buffer, bufferRow, scopeChain) ->
    return unless metadata = @metadataByPath.get(buffer)

    @removeBufferRow(buffer, bufferRow)

    if metadata.scopeChains[scopeChain]?
      @count -= 1
      metadata.scopeChains[scopeChain] -= 1

      if metadata.scopeChains[scopeChain] is 0
        delete metadata.scopeChains[scopeChain]
        @type = null

      if getObjectLength(metadata.scopeChains) is 0
        @metadataByPath.delete(buffer)

  addBufferRow: (buffer, row) ->
    metadata = @metadataByPath.get(buffer)
    metadata.bufferRows ?= []
    bufferRows = metadata.bufferRows
    index = binaryIndexOf(bufferRows, row)
    bufferRows.splice(index, 0, row)

  removeBufferRow: (buffer, row) ->
    metadata = @metadataByPath.get(buffer)
    bufferRows = metadata.bufferRows
    return unless bufferRows
    index = binaryIndexOf(bufferRows, row)
    bufferRows.splice(index, 1) if bufferRows[index] is row

  isEqualToWord: (word) ->
    @text is word

  instancesForWord: (word) ->
    if @text is word
      @count
    else
      0

  appliesToConfig: (config, buffer) ->
    @type = null if @cachedConfig isnt config

    unless @type?
      typePriority = 0
      for type, options of config
        continue unless options.selectors?
        @metadataByPath.forEach ({scopeChains}) =>
          for scopeChain, __ of scopeChains
            if (not @type or options.typePriority > typePriority) and selectorsMatchScopeChain(options.selectors, scopeChain)
              @type = type
              typePriority = options.typePriority
          return
      @cachedConfig = config

    if buffer?
      @type? and @countForBuffer(buffer) > 0
    else
      @type?

module.exports =
class SymbolStore
  count: 0

  constructor: (@wordRegex) ->
    @clear()

  clear: (buffer) ->
    if buffer?
      for symbolKey, symbol of @symbolMap
        symbol.clearForBuffer(buffer)
        delete @symbolMap[symbolKey] if symbol.getCount() is 0
    else
      @symbolMap = {}
    return

  getLength: -> @count

  getSymbol: (symbolKey) ->
    symbolKey = @getKey(symbolKey)
    @symbolMap[symbolKey]

  symbolsForConfig: (config, buffer, wordUnderCursor, numberOfCursors) ->
    symbols = []
    for symbolKey, symbol of @symbolMap
      if symbol.appliesToConfig(config, buffer) and (not symbol.isEqualToWord(wordUnderCursor) or symbol.instancesForWord(wordUnderCursor) > numberOfCursors)
        symbols.push(symbol)
    for type, options of config
      symbols = symbols.concat(options.suggestions) if options.suggestions
    symbols

  adjustBufferRows: (editor, oldRange, newRange) ->
    adjustmentStartRow = oldRange.end.row + 1
    adjustmentDelta = newRange.getRowCount() - oldRange.getRowCount()
    return if adjustmentDelta is 0
    for key, symbol of @symbolMap
      symbol.adjustBufferRows(editor.getBuffer(), adjustmentStartRow, adjustmentDelta)
    return

  addToken: (text, scopeChain, buffer, bufferRow) =>
    # This could be made async...
    matches = text.match(@wordRegex)
    if matches?
      @addSymbol(symbolText, buffer, bufferRow, scopeChain) for symbolText in matches
    return

  removeToken: (text, scopeChain, buffer, bufferRow) =>
    # This could be made async...
    matches = text.match(@wordRegex)
    if matches?
      @removeSymbol(symbolText, buffer, bufferRow, scopeChain) for symbolText in matches
    return

  addTokensInBufferRange: (editor, bufferRange) ->
    @operateOnTokensInBufferRange(editor, bufferRange, @addToken)

  removeTokensInBufferRange: (editor, bufferRange) ->
    @operateOnTokensInBufferRange(editor, bufferRange, @removeToken)

  operateOnTokensInBufferRange: (editor, bufferRange, operatorFunc) ->
    tokenizedLines = @getTokenizedLines(editor)

    useTokenIterator = null

    for bufferRow in [bufferRange.start.row..bufferRange.end.row] by 1
      tokenizedLine = tokenizedLines[bufferRow]
      continue unless tokenizedLine?
      useTokenIterator ?= typeof tokenizedLine.getTokenIterator is 'function'

      if useTokenIterator
        iterator = tokenizedLine.getTokenIterator?()
        while iterator.next()
          operatorFunc(iterator.getText(), @buildScopeChainString(iterator.getScopes()), editor.getBuffer(), bufferRow)
      else
        for token in tokenizedLine.tokens
          operatorFunc(token.value, @buildScopeChainString(token.scopes), editor.getBuffer(), bufferRow)

    return

  ###
  Private Methods
  ###

  addSymbol: (symbolText, buffer, bufferRow, scopeChain) ->
    symbolKey = @getKey(symbolText)
    symbol = @symbolMap[symbolKey]
    unless symbol?
      @symbolMap[symbolKey] = symbol = new Symbol(symbolText)
      @count += 1

    symbol.addInstance(buffer, bufferRow, scopeChain)

  removeSymbol: (symbolText, buffer, bufferRow, scopeChain) =>
    symbolKey = @getKey(symbolText)
    symbol = @symbolMap[symbolKey]
    if symbol?
      symbol.removeInstance(buffer, bufferRow, scopeChain)
      if symbol.getCount() is 0
        delete @symbolMap[symbolKey]
        @count -= 1

  getTokenizedLines: (editor) ->
    # Warning: displayBuffer and tokenizedBuffer are private APIs. Please do not
    # copy into your own package. If you do, be prepared to have it break
    # without warning.
    editor.displayBuffer.tokenizedBuffer.tokenizedLines

  buildScopeChainString: (scopes) ->
    '.' + scopes.join(' .')

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
