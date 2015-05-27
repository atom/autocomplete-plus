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

  bufferRowsForBufferPath: (bufferPath) ->
    @metadataByPath[bufferPath]?.bufferRows

  countForBufferPath: (bufferPath) ->
    metadata = @metadataByPath[bufferPath]
    bufferPathCount = 0
    if metadata?
      bufferPathCount += scopeCount for scopeChain, scopeCount of metadata.scopeChains
    bufferPathCount

  clearForBufferPath: (bufferPath) ->
    bufferPathCount = @countForBufferPath(bufferPath)
    if bufferPathCount > 0
      @count -= bufferPathCount
      delete @metadataByPath[bufferPath]

  updateForPathChange: (oldPath, newPath) ->
    if @metadataByPath[oldPath]?
      # Each symbol may not be in each path
      @metadataByPath[newPath] = @metadataByPath[oldPath]
    delete @metadataByPath[oldPath]

  adjustBufferRows: (bufferPath, adjustmentStartRow, adjustmentDelta) ->
    bufferRows = @metadataByPath[bufferPath]?.bufferRows
    return unless bufferRows?
    index = binaryIndexOf(bufferRows, adjustmentStartRow)
    length = bufferRows.length
    while index < length
      bufferRows[index] += adjustmentDelta
      index++
    return

  addInstance: (bufferPath, bufferRow, scopeChain) ->
    @metadataByPath[bufferPath] ?= {}
    @addBufferRow(bufferPath, bufferRow)
    @metadataByPath[bufferPath].scopeChains ?= {}
    unless @metadataByPath[bufferPath].scopeChains[scopeChain]?
      @type = null
      @metadataByPath[bufferPath].scopeChains[scopeChain] = 0
    @metadataByPath[bufferPath].scopeChains[scopeChain] += 1
    @count += 1

  removeInstance: (bufferPath, bufferRow, scopeChain) ->
    return unless @metadataByPath[bufferPath]?

    @removeBufferRow(bufferPath, bufferRow)

    if @metadataByPath[bufferPath].scopeChains[scopeChain]?
      @count -= 1
      @metadataByPath[bufferPath].scopeChains[scopeChain] -= 1

      if @metadataByPath[bufferPath].scopeChains[scopeChain] is 0
        delete @metadataByPath[bufferPath].scopeChains[scopeChain]
        @type = null

      if getObjectLength(@metadataByPath[bufferPath].scopeChains) is 0
        delete @metadataByPath[bufferPath]

  addBufferRow: (bufferPath, row) ->
    @metadataByPath[bufferPath].bufferRows ?= []
    bufferRows = @metadataByPath[bufferPath].bufferRows
    index = binaryIndexOf(bufferRows, row)
    bufferRows.splice(index, 0, row)

  removeBufferRow: (bufferPath, row) ->
    bufferRows = @metadataByPath[bufferPath].bufferRows
    return unless bufferRows
    index = binaryIndexOf(bufferRows, row)
    bufferRows.splice(index, 1) if bufferRows[index] is row

  isSingleInstanceOf: (word) ->
    @text is word and @count is 1

  appliesToConfig: (config, bufferPath) ->
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

    if bufferPath?
      @type? and @countForBufferPath(bufferPath) > 0
    else
      @type?

module.exports =
class SymbolStore
  count: 0

  constructor: (@wordRegex) ->
    @clear()

  clear: (bufferPath) ->
    if bufferPath?
      for symbolKey, symbol of @symbolMap
        symbol.clearForBufferPath(bufferPath)
        delete @symbolMap[symbolKey] if symbol.getCount() is 0
    else
      @symbolMap = {}
    return

  getLength: -> @count

  getSymbol: (symbolKey) ->
    symbolKey = @getKey(symbolKey)
    @symbolMap[symbolKey]

  symbolsForConfig: (config, bufferPath, wordUnderCursor) ->
    symbols = []
    for symbolKey, symbol of @symbolMap
      symbols.push(symbol) if symbol.appliesToConfig(config, bufferPath) and not symbol.isSingleInstanceOf(wordUnderCursor)
    for type, options of config
      symbols = symbols.concat(options.suggestions) if options.suggestions
    symbols

  adjustBufferRows: (editor, oldRange, newRange) ->
    adjustmentStartRow = oldRange.end.row + 1
    adjustmentDelta = newRange.getRowCount() - oldRange.getRowCount()
    for key, symbol of @symbolMap
      symbol.adjustBufferRows(editor.getPath(), adjustmentStartRow, adjustmentDelta)
    return

  updateForPathChange: (oldPath, newPath) ->
    for key, symbol of @symbolMap
      symbol.updateForPathChange(oldPath, newPath)
    return

  addToken: (text, scopeChain, bufferPath, bufferRow) =>
    # This could be made async...
    matches = text.match(@wordRegex)
    if matches?
      @addSymbol(symbolText, bufferPath, bufferRow, scopeChain) for symbolText in matches
    return

  removeToken: (text, scopeChain, bufferPath, bufferRow) =>
    # This could be made async...
    matches = text.match(@wordRegex)
    if matches?
      @removeSymbol(symbolText, bufferPath, bufferRow, scopeChain) for symbolText in matches
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
          operatorFunc(iterator.getText(), @buildScopeChainString(iterator.getScopes()), editor.getPath(), bufferRow)
      else
        for token in tokenizedLine.tokens
          operatorFunc(token.value, @buildScopeChainString(token.scopes), editor.getPath(), bufferRow)

    return

  ###
  Private Methods
  ###

  addSymbol: (symbolText, bufferPath, bufferRow, scopeChain) ->
    symbolKey = @getKey(symbolText)
    symbol = @symbolMap[symbolKey]
    unless symbol?
      @symbolMap[symbolKey] = symbol = new Symbol(symbolText)
      @count += 1

    symbol.addInstance(bufferPath, bufferRow, scopeChain)

  removeSymbol: (symbolText, bufferPath, bufferRow, scopeChain) =>
    symbolKey = @getKey(symbolText)
    symbol = @symbolMap[symbolKey]
    if symbol?
      symbol.removeInstance(bufferPath, bufferRow, scopeChain)
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
