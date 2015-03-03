# This provider is currently experimental.

_ = require 'underscore-plus'
fuzzaldrin = require 'fuzzaldrin'
{TextEditor, CompositeDisposable}  = require 'atom'
{Selector} = require 'selector-kit'

module.exports =
class SymbolProvider
  wordRegex: /\b\w*[a-zA-Z_-]+\w*\b/g
  symbolList: null
  editor: null
  buffer: null
  changeUpdateDelay: 300

  selector: '*'
  inclusionPriority: 0

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
      selector: '.comment, .string'
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
    @editorSubscriptions.add @buffer.onDidChange(@bufferChanged)

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

  bufferChanged: ({newRange}) =>
    @changeUpdateRange ?=
      start: newRange.start.row
      end: newRange.end.row

    @changeUpdateRange.start = Math.min(@changeUpdateRange.start, newRange.start.row)
    @changeUpdateRange.end = Math.max(@changeUpdateRange.end, newRange.end.row)

    clearTimeout(@changeUpdateTimeout)
    @changeUpdateTimeout = setTimeout =>
      @updateSymbolListForRange(@editor, @changeUpdateRange.start, @changeUpdateRange.end)
      @changeUpdateRange = null
    , @changeUpdateDelay

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
    return unless @symbolList?
    # Merge the scope specific words into the default word list
    symbolList = @symbolList.concat(@builtinCompletionsForCursorScope())

    words =
      if atom.config.get("autocomplete-plus.strictMatching")
        symbolList.filter((match) -> match.text?.indexOf(options.prefix) is 0)
      else
        @fuzzyFilter(symbolList, options)

    for word in words
      word.replacementPrefix = options.prefix
      word.rightLabel = word.type

    return words

  fuzzyFilter: (symbolList, {bufferPosition, prefix}) ->
    # Probably inefficient to do a linear search
    candidates = []
    for symbol in symbolList
      continue unless prefix[0].toLowerCase() is symbol.text[0].toLowerCase() # must match the first char!
      score = fuzzaldrin.score(symbol.text, prefix)
      score *= @getLocalityScore(symbol, bufferPosition) if symbol.path is @editor.getPath()
      candidates.push({symbol, score, locality, rowDifference}) if score > 0

    candidates.sort(@symbolSortReverseIterator)

    # Just get the first unique 20
    wordsSeen = {}
    results = []
    for {symbol, score, locality, rowDifference}, i in candidates
      break if results.length is 20
      # console.log 'match', symbol.text, score, locality, rowDifference
      key = @getSymbolKey(symbol.text)
      results.push(symbol) unless wordsSeen[key]
      wordsSeen[key] = true
    results

  symbolSortReverseIterator: (a, b) -> b.score - a.score

  getLocalityScore: (symbol, bufferPosition) ->
    if symbol.bufferRows?
      rowDifference = Number.MAX_VALUE
      rowDifference = Math.min(rowDifference, bufferRow - bufferPosition.row) for bufferRow in symbol.bufferRows
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

    minimumWordLength = atom.config.get('autocomplete-plus.minimumWordLength')
    symbolList = @getSymbolsFromEditor(@editor, minimumWordLength)

    # Do we want autocompletions from all open buffers?
    if atom.config.get('autocomplete-plus.includeCompletionsFromAllBuffers')
      for editor in atom.workspace.getTextEditors()
        # FIXME: downside is that some of these editors will not be tokenized :/
        symbolList = symbolList.concat @getSymbolsFromEditor(editor, minimumWordLength)

    @symbolList = symbolList

  updateSymbolListForRange: (editor, startBufferRow, endBufferRow) ->
    tokenizedLines = @getTokenizedLines(editor)[startBufferRow..endBufferRow]
    minimumWordLength = atom.config.get('autocomplete-plus.minimumWordLength')
    symbolList = @getSymbolsFromEditor(editor, minimumWordLength, tokenizedLines)
    @symbolList = @symbolList.concat(symbolList)

  getSymbolsFromEditor: (editor, minimumWordLength, tokenizedLines) ->
    tokenizedLines ?= @getTokenizedLines(editor)
    symbols = {}

    # Handle the case where a symbol is a variable in some cases and, say, a
    # class in others. We want all symbols of the same name to have the same type. e.g.
    #
    # ```coffee
    # SomeModule = require 'some-module' # This line parses SomeModule as a var
    # class MyClass extends SomeModule # This line parses SomeModule as a class
    # ```
    # `class` types are higher priority than `variables`
    cacheSymbol = (text, type, bufferRow, scopes) =>
      key = @getSymbolKey(text)
      cachedSymbol = symbols[key]
      if cachedSymbol?
        currentTypePriority = @config[type].priority
        cachedTypePriority = @config[cachedSymbol.type].priority
        cachedSymbol.type = type if currentTypePriority > cachedTypePriority
        cachedSymbol.bufferRows.push(bufferRow)
        cachedSymbol.scopes.push(scopes)
      else
        symbols[key] = {text, type, bufferRows: [bufferRow], scopes: [scopes], path: editor.getPath()}

    for {tokens}, bufferRow in tokenizedLines
      for token in tokens
        scopes = @cssSelectorFromScopes(token.scopes)
        for type, options of @config
          for selector in options.selectors
            if selector.matches(scopes) and matches = token.value.match(options.wordRegex)
              for matchText in matches
                if matchText.length >= minimumWordLength
                  cacheSymbol(matchText, type, bufferRow, scopes)
              break

    (symbol for key, symbol of symbols)

  # some words are reserved, like 'constructor' :/
  getSymbolKey: (symbolText) -> symbolText + '$$'

  getTokenizedLines: (editor) ->
    # Warning: displayBuffer and tokenizedBuffer are private APIs. Please do not
    # copy into your own package. If you do, be prepared to have it break
    # without warning.
    editor.displayBuffer.tokenizedBuffer.tokenizedLines

  cssSelectorFromScopes: (scopes) ->
    selector = ''
    selector += ' .' + scope for scope in scopes
    selector
