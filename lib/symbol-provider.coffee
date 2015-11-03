# This provider is currently experimental.

_ = require 'underscore-plus'
fuzzaldrin = require 'fuzzaldrin'
fuzzaldrinPlus = require 'fuzzaldrin-plus'
{CompositeDisposable}  = require 'atom'
{Selector} = require 'selector-kit'
SymbolStore = require './symbol-store'

module.exports =
class SymbolProvider
  wordRegex: /\b\w*[äöüßÄÖÜa-zA-Z_-]+\w*\b/g
  beginningOfLineWordRegex: /^\w*[äöüßÄÖÜa-zA-Z_-]+\w*\b/g
  endOfLineWordRegex: /\b\w*[äöüßÄÖÜa-zA-Z_-]+\w*$/g
  symbolStore: null
  editor: null
  buffer: null
  changeUpdateDelay: 300

  selector: '*'
  inclusionPriority: 0
  suggestionPriority: 0

  watchedBuffers: null

  config: null
  defaultConfig:
    class:
      selector: '.class.name, .inherited-class, .instance.type'
      typePriority: 4
    function:
      selector: '.function.name'
      typePriority: 3
    variable:
      selector: '.variable'
      typePriority: 2
    '':
      selector: '.source'
      typePriority: 1

  constructor: ->
    @watchedBuffers = new WeakMap
    @symbolStore = new SymbolStore(@wordRegex)
    @subscriptions = new CompositeDisposable
    @subscriptions.add(atom.config.observe('autocomplete-plus.minimumWordLength', (@minimumWordLength) => ))
    @subscriptions.add(atom.config.observe('autocomplete-plus.includeCompletionsFromAllBuffers', (@includeCompletionsFromAllBuffers) => ))
    @subscriptions.add(atom.config.observe('autocomplete-plus.useAlternateScoring', (@useAlternateScoring) => ))
    @subscriptions.add(atom.config.observe('autocomplete-plus.useLocalityBonus', (@useLocalityBonus) => ))
    @subscriptions.add(atom.workspace.observeActivePaneItem(@updateCurrentEditor))
    @subscriptions.add(atom.workspace.observeTextEditors(@watchEditor))

  dispose: =>
    @subscriptions.dispose()

  watchEditor: (editor) =>
    buffer = editor.getBuffer()
    editorSubscriptions = new CompositeDisposable
    editorSubscriptions.add editor.displayBuffer.onDidTokenize =>
      @buildWordListOnNextTick(editor)
    editorSubscriptions.add editor.onDidDestroy =>
      index = @getWatchedEditorIndex(editor)
      editors = @watchedBuffers.get(editor.getBuffer())
      editors.splice(index, 1) if index > -1
      editorSubscriptions.dispose()

    if bufferEditors = @watchedBuffers.get(buffer)
      bufferEditors.push(editor)
    else
      bufferSubscriptions = new CompositeDisposable
      bufferSubscriptions.add buffer.onWillChange ({oldRange, newRange}) =>
        editors = @watchedBuffers.get(buffer)
        if editors and editors.length and editor = editors[0]
          @symbolStore.removeTokensInBufferRange(editor, oldRange)
          @symbolStore.adjustBufferRows(editor, oldRange, newRange)

      bufferSubscriptions.add buffer.onDidChange ({newRange}) =>
        editors = @watchedBuffers.get(buffer)
        if editors and editors.length and editor = editors[0]
          @symbolStore.addTokensInBufferRange(editor, newRange)

      bufferSubscriptions.add buffer.onDidDestroy =>
        @symbolStore.clear(buffer)
        bufferSubscriptions.dispose()
        @watchedBuffers.delete(buffer)

      @watchedBuffers.set(buffer, [editor])
      @buildWordListOnNextTick(editor)

  isWatchingEditor: (editor) ->
    @getWatchedEditorIndex(editor) > -1

  isWatchingBuffer: (buffer) ->
    @watchedBuffers.get(buffer)?

  getWatchedEditorIndex: (editor) ->
    if editors = @watchedBuffers.get(editor.getBuffer())
      editors.indexOf(editor)
    else
      -1

  updateCurrentEditor: (currentPaneItem) =>
    return unless currentPaneItem?
    return if currentPaneItem is @editor
    @editor = null
    @editor = currentPaneItem if @paneItemIsValid(currentPaneItem)

  buildConfigIfScopeChanged: ({editor, scopeDescriptor}) ->
    unless @scopeDescriptorsEqual(@configScopeDescriptor, scopeDescriptor)
      @buildConfig(scopeDescriptor)
      @configScopeDescriptor = scopeDescriptor

  buildConfig: (scopeDescriptor) ->
    @config = {}
    legacyCompletions = @settingsForScopeDescriptor(scopeDescriptor, 'editor.completions')
    allConfigEntries = @settingsForScopeDescriptor(scopeDescriptor, 'autocomplete.symbols')

    # Config entries are reverse sorted in order of specificity. We want most
    # specific to win; this simplifies the loop.
    allConfigEntries.reverse()

    for {value} in legacyCompletions
      @addLegacyConfigEntry(value) if Array.isArray(value) and value.length

    addedConfigEntry = false
    for {value} in allConfigEntries
      if not Array.isArray(value) and typeof value is 'object'
        @addConfigEntry(value)
        addedConfigEntry = true

    @addConfigEntry(@defaultConfig) unless addedConfigEntry

  addLegacyConfigEntry: (suggestions) ->
    suggestions = ({text: suggestion, type: 'builtin'} for suggestion in suggestions)
    @config.builtin ?= {suggestions: []}
    @config.builtin.suggestions = @config.builtin.suggestions.concat(suggestions)

  addConfigEntry: (config) ->
    for type, options of config
      @config[type] ?= {}
      @config[type].selectors = Selector.create(options.selector) if options.selector?
      @config[type].typePriority = options.typePriority ? 1
      @config[type].wordRegex = @wordRegex

      suggestions = @sanitizeSuggestionsFromConfig(options.suggestions, type)
      @config[type].suggestions = suggestions if suggestions? and suggestions.length
    return

  sanitizeSuggestionsFromConfig: (suggestions, type) ->
    if suggestions? and Array.isArray(suggestions)
      sanitizedSuggestions = []
      for suggestion in suggestions
        if typeof suggestion is 'string'
          sanitizedSuggestions.push({text: suggestion, type})
        else if typeof suggestions[0] is 'object' and (suggestion.text? or suggestion.snippet?)
          suggestion = _.clone(suggestion)
          suggestion.type ?= type
          sanitizedSuggestions.push(suggestion)
      sanitizedSuggestions
    else
      null

  uniqueFilter: (completion) -> completion.text

  paneItemIsValid: (paneItem) ->
    return false unless paneItem?
    # Should we disqualify TextEditors with the Grammar text.plain.null-grammar?
    return paneItem.getText?

  ###
  Section: Suggesting Completions
  ###

  getSuggestions: (options) =>
    prefix = options.prefix?.trim()
    return unless prefix?.length and prefix?.length >= @minimumWordLength
    return unless @symbolStore.getLength()

    @buildConfigIfScopeChanged(options)

    {editor, prefix, bufferPosition} = options
    numberOfWordsMatchingPrefix = 1
    wordUnderCursor = @wordAtBufferPosition(editor, bufferPosition)
    for cursor in editor.getCursors()
      continue if cursor is editor.getLastCursor()
      word = @wordAtBufferPosition(editor, cursor.getBufferPosition())
      numberOfWordsMatchingPrefix += 1 if word is wordUnderCursor

    buffer = if @includeCompletionsFromAllBuffers then null else @editor.getBuffer()
    symbolList = @symbolStore.symbolsForConfig(@config, buffer, wordUnderCursor, numberOfWordsMatchingPrefix)

    words =
      if atom.config.get("autocomplete-plus.strictMatching")
        symbolList.filter((match) -> match.text?.indexOf(options.prefix) is 0)
      else
        @fuzzyFilter(symbolList, @editor.getBuffer(), options)

    for word in words
      word.replacementPrefix = options.prefix

    return words

  wordAtBufferPosition: (editor, bufferPosition) ->
    lineToPosition = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
    prefix = lineToPosition.match(@endOfLineWordRegex)?[0] or ''
    lineFromPosition = editor.getTextInRange([bufferPosition, [bufferPosition.row, Infinity]])
    suffix = lineFromPosition.match(@beginningOfLineWordRegex)?[0] or ''
    prefix + suffix

  fuzzyFilter: (symbolList, buffer, {bufferPosition, prefix}) ->
    # Probably inefficient to do a linear search
    candidates = []

    if @useAlternateScoring
      fuzzaldrinProvider = fuzzaldrinPlus
      # This allows to pre-compute and re-use some quantities derived from prefix such as
      # Uppercase, lowercase and a version of prefix without optional characters.
      prefixCache = fuzzaldrinPlus.prepQuery(prefix)
    else
      fuzzaldrinProvider = fuzzaldrin
      prefixCache = null

    for symbol in symbolList
      text = (symbol.snippet or symbol.text)
      continue unless text and prefix[0].toLowerCase() is text[0].toLowerCase() # must match the first char!
      score = fuzzaldrinProvider.score(text, prefix, prefixCache)
      if @useLocalityBonus then score *= @getLocalityScore(bufferPosition, symbol.bufferRowsForBuffer?(buffer))
      candidates.push({symbol, score}) if score > 0

    candidates.sort(@symbolSortReverseIterator)

    results = []
    for {symbol, score}, index in candidates
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
    if @useAlternateScoring
      # Between 1 and 1 + strength. (here between 1.0 and 2.0)
      # Avoid a pow and a branching max.
      # 25 is the number of row where the bonus is 3/4 faded away.
      # strength is the factor in front of fade*fade. Here it is 1.0
      fade = 25.0 / (25.0 + rowDifference)
      1.0 + fade * fade
    else
      # Will be between 1 and ~2.75
      1 + Math.max(-Math.pow(.2 * rowDifference - 3, 3) / 25 + .5, 0)

  settingsForScopeDescriptor: (scopeDescriptor, keyPath) ->
    atom.config.getAll(keyPath, scope: scopeDescriptor)

  ###
  Section: Word List Building
  ###

  buildWordListOnNextTick: (editor) =>
    _.defer => @buildSymbolList(editor)

  buildSymbolList: (editor) =>
    return unless editor?.isAlive()
    @symbolStore.clear(editor.getBuffer())
    @symbolStore.addTokensInBufferRange(editor, editor.getBuffer().getRange())

  # FIXME: this should go in the core ScopeDescriptor class
  scopeDescriptorsEqual: (a, b) ->
    return true if a is b
    return false unless a? and b?

    arrayA = a.getScopesArray()
    arrayB = b.getScopesArray()

    return false if arrayA.length isnt arrayB.length

    for scope, i in arrayA
      return false if scope isnt arrayB[i]
    true
