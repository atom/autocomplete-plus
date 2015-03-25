module.exports =
class RefCountedSymbolList
  constructor: ->
    @clear()

  clear: ->
    @references = {}
    @symbols = []

  getSymbols: -> @symbols

  getLength: -> @symbols.length

  getSymbol: (symbolText) ->
    symbolKey = @getSymbolKey(symbolText)
    @references[symbolKey]?.symbol

  addSymbol: (symbol, textKey) ->
    symbolKey = @getSymbolKey(symbol, textKey)
    @updateRefCount(symbolKey, symbol, 1)

  removeSymbol: (symbol, textKey) ->
    symbolKey = @getSymbolKey(symbol, textKey)
    @updateRefCount(symbolKey, symbol, -1)

  ###
  Private Methods
  ###

  updateRefCount: (symbolKey, symbol, increment) ->
    if increment > 0 and not @references[symbolKey]?
      @references[symbolKey] ?= {symbol, count: 0}
      @addSymbolToList(symbol)

    if @references[symbolKey]?
      @references[symbolKey].count += increment

      if @references[symbolKey].count <= 0
        delete @references[symbolKey]
        @removeSymbolFromList(symbol)

  addSymbolToList: (symbol) ->
    @symbols.push(symbol)

  removeSymbolFromList: (symbol) ->
    index = @symbols.indexOf(symbol)
    @symbols.splice(index, 1) if index > -1

  getSymbolKey: (symbol, textKey) ->
    symbolText = symbol
    symbolText = symbol[textKey] if textKey?
    # some words are reserved, like 'constructor' :/
    symbolText + '$$'
