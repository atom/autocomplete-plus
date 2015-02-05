_ = require 'underscore-plus'
Suggestion = require './suggestion'
fuzzaldrin = require 'fuzzaldrin'
{TextEditor, CompositeDisposable}  = require 'atom'
{Selector} = require 'selector-kit'

module.exports =
class SymbolProvider
  wordRegex: /\b\w*[a-zA-Z_-]+\w*\b/g
  symbolList: null
  editor: null
  buffer: null

  selector: '*'

  config: null
  defaultConfig:
    class:
      selector: '.class.name, .inherited-class'
      priority: 3
    function:
      selector: '.function.name'
      priority: 2
    variable:
      selector: '.variable'
      priority: 1

  constructor: ->
    @id = 'autocomplete-plus-symbolprovider'
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

  # bufferChanged: (e) ->
    # console.log 'changed'

  ###
  Section: Suggesting Completions
  ###

  # Public:  Gets called when the document has been changed. Returns an array
  # with suggestions. If `exclusive` is set to true and this method returns
  # suggestions, the suggestions will be the only ones that are displayed.
  #
  # Returns an {Array} of Suggestion instances
  requestHandler: (options) =>
    return unless options?
    return unless options.editor?
    selection = options.editor.getLastSelection()
    prefix = options.prefix

    # No prefix? Don't autocomplete!
    return unless prefix.trim().length

    new Promise (resolve) =>
      _.defer =>
        suggestions = @findSuggestionsForWord(options)
        resolve(suggestions)

  # Private: Finds possible matches for the given string / prefix
  #
  # prefix - {String} The prefix
  #
  # Returns an {Array} of Suggestion instances
  findSuggestionsForWord: (options) =>
    return unless @symbolList?
    # Merge the scope specific words into the default word list
    symbolList = @symbolList.concat(@builtinCompletionsForCursorScope())

    words =
      if atom.config.get("autocomplete-plus.strictMatching")
        symbolList.filter((match) -> match.word?.indexOf(options.prefix) is 0)
      else
        @fuzzyFilter(symbolList, options)

    for word in words
      word.prefix = options.prefix
      word.label = word.type

    return words

  fuzzyFilter: (symbolList, {position, prefix}) ->
    # Probably inefficient to do a linear search
    candidates = []
    for symbol in symbolList
      score = fuzzaldrin.score(symbol.word, prefix)
      score *= @getLocalityScore(symbol, position) if symbol.path is @editor.getPath()
      candidates.push({symbol, score, locality, rowDifference}) if score > 0

    candidates.sort(@sortSymbolsReverseIterator)

    # Just get the first unique 20
    wordsSeen = {}
    results = []
    for {symbol, score, locality, rowDifference}, i in candidates
      break if results.length is 20
      # console.log 'match', symbol.word, score, locality, rowDifference
      key = @getSymbolKey(symbol.word)
      results.push(symbol) unless wordsSeen[key]
      wordsSeen[key] = true
    results

  sortSymbolsReverseIterator: (a, b) -> b.score - a.score

  getLocalityScore: (symbol, position) ->
    if symbol.bufferRows?
      rowDifference = Number.MAX_VALUE
      rowDifference = Math.min(rowDifference, bufferRow - position.row) for bufferRow in symbol.bufferRows
      locality = @computeLocalityModifier(rowDifference)
      locality
    else
      1

  computeLocalityModifier: (rowDifference) ->
    rowDifference = Math.abs(rowDifference)
    # Will be between 1 and ~2.75
    1 + Math.max(-Math.pow(.2 * rowDifference - 3, 3) / 25 + .5, 0)

  settingsForScopeDescriptor: (scopeDescriptor, keyPath) =>
    atom.config.getAll(keyPath, scope: scopeDescriptor)

  # Private: Finds autocompletions in the current syntax scope (e.g. css values)
  #
  # Returns an {Array} of strings
  builtinCompletionsForCursorScope: =>
    cursorScope = @editor.scopeDescriptorForBufferPosition(@editor.getCursorBufferPosition())
    completions = @settingsForScopeDescriptor(cursorScope, "editor.completions")
    scopedCompletions = []
    for properties in completions
      if suggestions = _.valueForKeyPath(properties, "editor.completions")
        for suggestion in suggestions
          scopedCompletions.push
            word: suggestion
            type: 'builtin'

    _.uniq scopedCompletions, (completion) -> completion.word

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

  getSymbolsFromEditor: (editor, minimumWordLength) ->
    # Warning: displayBuffer and tokenizedBuffer are private APIs. Please do not
    # copy into your own package. If you do, be prepared to have it break
    # without warning.
    tokenizedLines = editor.displayBuffer.tokenizedBuffer.tokenizedLines

    symbols = {}

    # Handle the case where a symbol is a variable in some cases and, say, a
    # class in others. We want all symbols of the same name to have the same type. e.g.
    #
    # ```coffee
    # SomeModule = require 'some-module' # This line parses SomeModule as a var
    # class MyClass extends SomeModule # This line parses SomeModule as a class
    # ```
    # `class` types are higher priority than `variables`
    cacheSymbol = (word, type, bufferRow, scopes) =>
      key = @getSymbolKey(word)
      cachedSymbol = symbols[key]
      if cachedSymbol?
        currentTypePriority = @config[type].priority
        cachedTypePriority = @config[cachedSymbol.type].priority
        cachedSymbol.type = type if currentTypePriority > cachedTypePriority
        cachedSymbol.bufferRows.push(bufferRow)
        cachedSymbol.scopes.push(scopes)
      else
        symbols[key] = {word, type, bufferRows: [bufferRow], scopes: [scopes], path: editor.getPath()}

    for {tokens}, bufferRow in tokenizedLines
      for token in tokens
        scopes = @cssSelectorFromScopes(token.scopes)
        for type, options of @config
          for selector in options.selectors
            if selector.matches(scopes) and matches = token.value.match(options.wordRegex)
              for word in matches
                if word.length >= minimumWordLength
                  cacheSymbol(word, type, bufferRow, scopes)
              break

    (symbol for key, symbol of symbols)

  # some words are reserved, like 'constructor' :/
  getSymbolKey: (word) -> word + '$$'

  cssSelectorFromScopes: (scopes) ->
    selector = ''
    selector += ' .' + scope for scope in scopes
    selector
