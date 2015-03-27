# This provider is currently experimental.

_ = require 'underscore-plus'
fuzzaldrin = require 'fuzzaldrin'
{TextEditor, CompositeDisposable}  = require 'atom'
{Selector} = require 'selector-kit'
RefCountedTokenList = require './ref-counted-token-list'
DifferentialTokenStore = require './differential-token-store'

module.exports =
class SymbolProvider
  wordRegex: /\b\w*[a-zA-Z_-]+\w*\b/g
  symbolList: new RefCountedTokenList
  editor: null
  buffer: null
  changeUpdateDelay: 300

  selector: '*'
  inclusionPriority: 0
  suggestionPriority: 0

  realtimeUpdateTokenStore: new DifferentialTokenStore

  config: null
  defaultConfig:
    class:
      selector: '.class.name, .inherited-class'
      priority: 4
    function:
      selector: '.function.name'
      priority: 3
    variable:
      selector: '.variable'
      priority: 2
    '':
      selector: '.source'
      priority: 1

  constructor: ->
    @subscriptions = new CompositeDisposable
    @subscriptions.add(atom.workspace.observeActivePaneItem(@updateCurrentEditor))

  dispose: =>
    @editorSubscriptions?.dispose()
    @subscriptions.dispose()

  updateCurrentEditor: (currentPaneItem) =>
    return unless currentPaneItem?
    return if currentPaneItem is @editor

    @editorSubscriptions?.dispose()
    @editorSubscriptions = new CompositeDisposable

    @editor = null
    @buffer = null

    return unless @paneItemIsValid(currentPaneItem)

    @editor = currentPaneItem
    @buffer = @editor.getBuffer()

    @editorSubscriptions.add @editor.displayBuffer.onDidTokenize(@buildWordListOnNextTick)
    @editorSubscriptions.add @buffer.onDidSave(@buildWordListOnNextTick)
    @editorSubscriptions.add @buffer.onWillChange(@bufferWillChange)
    @editorSubscriptions.add @buffer.onDidChange(@bufferDidChange)

    @buildConfig()
    @buildWordListOnNextTick()

  buildConfig: ->
    @config = {}

    allConfig = @settingsForScopeDescriptor(@editor.getRootScopeDescriptor(), 'editor.completionSymbols')
    allConfig.push @defaultConfig unless allConfig.length

    for config in allConfig
      for type, options of config
        @config[type] = _.clone(options)
        @config[type].selectors = Selector.create(options.selector) if options.selector?
        @config[type].selectors ?= []
        @config[type].priority ?= 1
        @config[type].wordRegex ?= @wordRegex

    return

  paneItemIsValid: (paneItem) ->
    return false unless paneItem?
    # Should we disqualify TextEditors with the Grammar text.plain.null-grammar?
    return paneItem instanceof TextEditor

  # Buffer change handling. The goal is to remove symbols from the `symbolList`
  # that were removed from the buffer, and add symbols that were added.
  #
  # 1. Use onWillChange, and onDidChange events to build an XOR list of tokens
  #    to add and remove from the `symbolList`. This XOR list is
  #    `realtimeUpdateTokenStore`
  # 2. Trigger an async update to the `symbolList`
  #
  # In `updateChangedTokens` will add and remove necessary tokens from `symbolList`
  #
  # Why do it this way?
  #
  # * Reading of the tokens must happen synchonously in the event handlers as
  #   thats the only time the buffer will have the tokens matching the change events.
  # * The slow part is the token scope selector matching to bucket tokens
  #   by type. So we try to minimize the amount of selector matching that
  #   happens, and group as much as possible into one event.
  bufferWillChange: ({oldRange}) =>
    tokenizedLines = @getTokenizedLines(@editor)[oldRange.start.row..oldRange.end.row]
    bufferRowBase = oldRange.start.row
    for {tokens}, bufferRowIndex in tokenizedLines
      bufferRow = bufferRowBase + bufferRowIndex
      for token in tokens
        @realtimeUpdateTokenStore.remove(token, @editor.getPath(), bufferRow)
    return

  bufferDidChange: ({newRange}) =>
    tokenizedLines = @getTokenizedLines(@editor)[newRange.start.row..newRange.end.row]
    bufferRowBase = newRange.start.row
    for {tokens}, bufferRowIndex in tokenizedLines
      bufferRow = bufferRowBase + bufferRowIndex
      for token in tokens
        @realtimeUpdateTokenStore.add(token, @editor.getPath(), bufferRow)
    @debouncedUpdateChangedTokens()

  debouncedUpdateChangedTokens: =>
    clearTimeout(@updateChangedTokensTimeout)
    @updateChangedTokensTimeout = setTimeout =>
      @updateChangedTokens()
    , @changeUpdateDelay

  updateChangedTokens: ->
    minimumWordLength = atom.config.get('autocomplete-plus.minimumWordLength')

    tokensToRemove = @realtimeUpdateTokenStore.tokensForRemoval.getTokenWrappers()
    for {token, count, bufferRowsForEditorPath} in tokensToRemove
      index = 0
      for editorPath, bufferRows of bufferRowsForEditorPath
        for bufferRow in bufferRows
          @removeSymbolsForToken(token, editorPath, bufferRow)
          index += 1
        break if index is count

    tokensToAdd = @realtimeUpdateTokenStore.tokensForAddition.getTokenWrappers()
    for {token, count, bufferRowsForEditorPath} in tokensToAdd
      index = 0
      for editorPath, bufferRows of bufferRowsForEditorPath
        for bufferRow in bufferRows
          @addSymbolsForToken(token, editorPath, bufferRow, minimumWordLength)
          index += 1
        break if index is count

    @realtimeUpdateTokenStore.clear()

  ###
  Section: Suggesting Completions
  ###

  getSuggestions: (options) =>
    # No prefix? Don't autocomplete!
    return unless options.prefix.trim().length

    new Promise (resolve) =>
      suggestions = @findSuggestionsForWord(options)
      resolve(suggestions)

  findSuggestionsForWord: (options) =>
    return unless @symbolList.getLength()
    # Merge the scope specific words into the default word list
    symbolList = @symbolList.getTokens().concat(@builtinCompletionsForCursorScope())

    words =
      if atom.config.get("autocomplete-plus.strictMatching")
        symbolList.filter((match) -> match.text?.indexOf(options.prefix) is 0)
      else
        @fuzzyFilter(symbolList, @editor.getPath(), options)

    for word in words
      word.replacementPrefix = options.prefix
      word.rightLabel = word.type

    return words

  fuzzyFilter: (symbolList, editorPath, {bufferPosition, prefix}) ->
    # Probably inefficient to do a linear search
    candidates = []
    for symbol in symbolList
      continue if symbol.text is prefix
      continue unless prefix[0].toLowerCase() is symbol.text[0].toLowerCase() # must match the first char!
      score = fuzzaldrin.score(symbol.text, prefix)
      score *= @getLocalityScore(bufferPosition, symbol.bufferRowsForEditorPath?[editorPath]) if symbol.path is @editor.getPath()
      candidates.push({symbol, score, locality, rowDifference}) if score > 0

    candidates.sort(@symbolSortReverseIterator)

    results = []
    for {symbol, score, locality, rowDifference}, index in candidates
      break if index is 20
      results.push(symbol)
    results

  symbolSortReverseIterator: (a, b) -> b.score - a.score

  getLocalityScore: (bufferPosition, bufferRowsContainingSymbol) ->
    if bufferRowsContainingSymbol?
      rowDifference = Number.MAX_VALUE
      rowDifference = Math.min(rowDifference, bufferRow - bufferPosition.row) for bufferRow in bufferRowsContainingSymbol
      locality = @computeLocalityModifier(rowDifference)
      locality
    else
      1

  computeLocalityModifier: (rowDifference) ->
    rowDifference = Math.abs(rowDifference)
    # Will be between 1 and ~2.75
    1 + Math.max(-Math.pow(.2 * rowDifference - 3, 3) / 25 + .5, 0)

  settingsForScopeDescriptor: (scopeDescriptor, keyPath) ->
    atom.config.getAll(keyPath, scope: scopeDescriptor)

  builtinCompletionsForCursorScope: =>
    cursorScope = @editor.scopeDescriptorForBufferPosition(@editor.getCursorBufferPosition())
    completions = @settingsForScopeDescriptor(cursorScope, "editor.completions")
    scopedCompletions = []
    for properties in completions
      if suggestions = _.valueForKeyPath(properties, "editor.completions")
        for suggestion in suggestions
          scopedCompletions.push
            text: suggestion
            type: 'builtin'

    _.uniq scopedCompletions, (completion) -> completion.text

  ###
  Section: Word List Building
  ###

  buildWordListOnNextTick: =>
    _.defer => @buildSymbolList()

  buildSymbolList: =>
    return unless @editor?

    @symbolList.clear()

    minimumWordLength = atom.config.get('autocomplete-plus.minimumWordLength')
    @cacheSymbolsFromEditor(@editor, minimumWordLength)

    if atom.config.get('autocomplete-plus.includeCompletionsFromAllBuffers')
      for editor in atom.workspace.getTextEditors()
        # FIXME: downside is that some of these editors will not be tokenized :/
        @cacheSymbolsFromEditor(editor, minimumWordLength)
    return

  cacheSymbolsFromEditor: (editor, minimumWordLength, tokenizedLines) ->
    tokenizedLines ?= @getTokenizedLines(editor)

    editorPath = editor.getPath()
    for {tokens}, bufferRow in tokenizedLines
      for token in tokens
        @addSymbolsForToken(token, editorPath, bufferRow, minimumWordLength)
    return

  addSymbolsForToken: (token, editorPath, bufferRow, minimumWordLength) ->
    scopes = @cssSelectorFromScopes(token.scopes)
    for type, options of @config
      for selector in options.selectors
        if selector.matches(scopes) and matches = token.value.match(options.wordRegex)
          for matchText in matches
            if matchText.length >= minimumWordLength
              @addSymbol(matchText, type, scopes, editorPath, bufferRow)
          break
    return

  addSymbol: (text, type, scopes, editorPath, bufferRow) =>
    # By using one symbol object all the time, we handle the case where a symbol
    # is a variable in some cases and, say, a class in others. We want all
    # symbols of the same name to have the same type. e.g.
    #
    # ```coffee
    # SomeModule = require 'some-module' # This line parses SomeModule as a var
    # class MyClass extends SomeModule # This line parses SomeModule as a class
    # ```
    # `class` types are higher priority than `variables`
    symbol = @symbolList.getToken(text)
    if symbol?
      currentTypePriority = @config[type].priority
      cachedTypePriority = @config[symbol.type].priority
      symbol.type = type if currentTypePriority > cachedTypePriority
      symbol.scopes.push(scopes)
      symbol.bufferRowsForEditorPath[editorPath] ?= []
      symbol.bufferRowsForEditorPath[editorPath].unshift(bufferRow)
    else
      bufferRowsForEditorPath = {}
      bufferRowsForEditorPath[editorPath] = [bufferRow]
      symbol = {text, type, scopes: [scopes], bufferRowsForEditorPath}
    @symbolList.addToken(symbol, symbol.text)

  removeSymbolsForToken: (token, editorPath, bufferRow) ->
    scopes = @cssSelectorFromScopes(token.scopes)
    for type, options of @config
      for selector in options.selectors
        if selector.matches(scopes) and matches = token.value.match(options.wordRegex)
          for matchText in matches
            @removeSymbol(matchText, editorPath, bufferRow)
          break
    return

  removeSymbol: (symbolText, editorPath, bufferRow) ->
    @symbolList.removeToken(symbolText)
    symbol = @symbolList.getToken(symbolText)
    bufferRows = symbol?.bufferRowsForEditorPath?[editorPath]
    removeItemFromArray(bufferRows, bufferRow) if bufferRows?

  getTokenizedLines: (editor) ->
    # Warning: displayBuffer and tokenizedBuffer are private APIs. Please do not
    # copy into your own package. If you do, be prepared to have it break
    # without warning.
    editor.displayBuffer.tokenizedBuffer.tokenizedLines

  cssSelectorFromScopes: (scopes) ->
    selector = ''
    selector += ' .' + scope for scope in scopes
    selector

removeItemFromArray = (array, item) ->
  index = array.indexOf(item)
  array.splice(index, 1) if index > -1
