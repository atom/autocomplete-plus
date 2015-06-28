# This provider is currently experimental.

_ = require 'underscore-plus'
fuzzaldrin = require 'fuzzaldrin'
{TextEditor, CompositeDisposable}  = require 'atom'
{Selector} = require 'selector-kit'
SymbolStore = require './symbol-store'

module.exports =
class SymbolProvider
  wordRegex: /\b\w*[a-zA-Z_-]+\w*\b/g
  beginningOfLineWordRegex: /^\w*[a-zA-Z_-]+\w*\b/g
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
    @watchedBuffers = {}
    @symbolStore = new SymbolStore(@wordRegex)
    @subscriptions = new CompositeDisposable
    @subscriptions.add(atom.config.observe('autocomplete-plus.minimumWordLength', (@minimumWordLength) => ))
    @subscriptions.add(atom.config.observe('autocomplete-plus.includeCompletionsFromAllBuffers', (@includeCompletionsFromAllBuffers) => ))
    @subscriptions.add(atom.workspace.observeActivePaneItem(@updateCurrentEditor))
    @subscriptions.add(atom.workspace.observeTextEditors(@watchEditor))

  dispose: =>
    @subscriptions.dispose()

  watchEditor: (editor) =>
    bufferPath = editor.getPath()
    editorSubscriptions = new CompositeDisposable
    editorSubscriptions.add editor.displayBuffer.onDidTokenize =>
      @buildWordListOnNextTick(editor)
    editorSubscriptions.add editor.onDidDestroy =>
      index = @getWatchedEditorIndex(editor)
      editors = @watchedBuffers[editor.getPath()]?.editors
      editors.splice(index, 1) if index > -1
      editorSubscriptions.dispose()

    if @watchedBuffers[bufferPath]?
      @watchedBuffers[bufferPath].editors.push(editor)
    else
      buffer = editor.getBuffer()
      bufferSubscriptions = new CompositeDisposable
      bufferSubscriptions.add buffer.onWillChange ({oldRange, newRange}) =>
        bufferPath = buffer.getPath()
        editor = @watchedBuffers[bufferPath].editors[0]
        @symbolStore.removeTokensInBufferRange(editor, oldRange)
        @symbolStore.adjustBufferRows(editor, oldRange, newRange)

      bufferSubscriptions.add buffer.onDidChange ({newRange}) =>
        bufferPath = buffer.getPath()
        editor = @watchedBuffers[bufferPath].editors[0]
        @symbolStore.addTokensInBufferRange(editor, newRange)

      bufferSubscriptions.add buffer.onDidChangePath =>
        return unless @watchedBuffers[bufferPath]?
        oldBufferPath = bufferPath
        bufferPath = buffer.getPath()
        @watchedBuffers[bufferPath] = @watchedBuffers[oldBufferPath]
        @symbolStore.updateForPathChange(oldBufferPath, bufferPath)
        delete @watchedBuffers[oldBufferPath]

      bufferSubscriptions.add buffer.onDidDestroy =>
        bufferPath = buffer.getPath()
        @symbolStore.clear(bufferPath)
        bufferSubscriptions.dispose()
        delete @watchedBuffers[bufferPath]

      @watchedBuffers[bufferPath] = editors: [editor]
      @buildWordListOnNextTick(editor)

  isWatchingEditor: (editor) ->
    @getWatchedEditorIndex(editor) > -1

  isWatchingBuffer: (buffer) ->
    @watchedBuffers[buffer.getPath()]?

  getWatchedEditorIndex: (editor) ->
    if editors = @watchedBuffers[editor.getPath()]?.editors
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
    @config.builtin.suggestions = _.uniq(@config.builtin.suggestions, @uniqueFilter) if @config.builtin?.suggestions?

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
    return paneItem instanceof TextEditor

  ###
  Section: Suggesting Completions
  ###

  getSuggestions: (options) =>
    prefix = options.prefix?.trim()
    return unless prefix?.length >= @minimumWordLength
    return unless @symbolStore.getLength()

    wordUnderCursor = @wordAtBufferPosition(options)
    @buildConfigIfScopeChanged(options)

    bufferPath = if @includeCompletionsFromAllBuffers then null else @editor.getPath()
    symbolList = @symbolStore.symbolsForConfig(@config, bufferPath, wordUnderCursor)

    words =
      if atom.config.get("autocomplete-plus.strictMatching")
        symbolList.filter((match) -> match.text?.indexOf(options.prefix) is 0)
      else
        @fuzzyFilter(symbolList, @editor.getPath(), options)

    for word in words
      word.replacementPrefix = options.prefix

    return words

  wordAtBufferPosition: ({editor, prefix, bufferPosition}) ->
    lineFromPosition = editor.getTextInRange([bufferPosition, [bufferPosition.row, Infinity]])
    suffix = lineFromPosition.match(@beginningOfLineWordRegex)?[0] or ''
    prefix + suffix

  fuzzyFilter: (symbolList, bufferPath, {bufferPosition, prefix}) ->
    # Probably inefficient to do a linear search
    candidates = []
    for symbol in symbolList
      text = (symbol.snippet or symbol.text)
      continue unless text and prefix[0].toLowerCase() is text[0].toLowerCase() # must match the first char!
      score = fuzzaldrin.score(text, prefix)
      score *= @getLocalityScore(bufferPosition, symbol.bufferRowsForBufferPath?(bufferPath))
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

  ###
  Section: Word List Building
  ###

  buildWordListOnNextTick: (editor) =>
    _.defer => @buildSymbolList(editor)

  buildSymbolList: (editor) =>
    return unless editor?.isAlive()
    @symbolStore.clear(editor.getPath())
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
