# This provider is currently experimental.

_ = require 'underscore-plus'
fuzzaldrin = require 'fuzzaldrin'
fuzzaldrinPlus = require 'fuzzaldrin-plus'
{CompositeDisposable}  = require 'atom'
{Selector} = require 'selector-kit'
SymbolStore = require './symbol-store'

# TODO: extract SymbolQuery object.

module.exports =
class SymbolProvider
  wordRegex: /\b\w*[a-zA-Z_-]+\w*\b/g
  beginningOfLineWordRegex: /^\w*[a-zA-Z_-]+\w*\b/g
  endOfLineWordRegex: /\b\w*[a-zA-Z_-]+\w*$/g
  symbolStore: null
  editor: null
  buffer: null
  changeUpdateDelay: 300

  selector: '*'
  inclusionPriority: 0
  suggestionPriority: 0

  watchedBuffers: null

  symbolQuery: null
  defaultSymbolSelectors:
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

  rebuildSymbolQueryForScopeDescriptor: (scopeDescriptor) ->
    @symbolQuery = {}
    legacyCompletions = @settingsForScopeDescriptor(scopeDescriptor, 'editor.completions')
    scopeDescriptorSymbolSelectors = @settingsForScopeDescriptor(scopeDescriptor, 'autocomplete.symbols')

    for {value} in legacyCompletions
      @addBuiltinSuggestionsToSymbolQuery(value) if Array.isArray(value) and value.length

    hasAddedSelectors = false
    # Iterate in reverse because more specific entries win over less specific ones.
    for {value} in scopeDescriptorSymbolSelectors by -1
      if not Array.isArray(value) and typeof value is 'object'
        @addSymbolSelectorsToQuery(value)
        hasAddedSelectors = true

    @addSymbolSelectorsToQuery(@defaultSymbolSelectors) unless hasAddedSelectors

  addBuiltinSuggestionsToSymbolQuery: (suggestions) ->
    suggestions = ({text: suggestion, type: 'builtin'} for suggestion in suggestions)
    @symbolQuery.builtin ?= {suggestions: []}
    @symbolQuery.builtin.suggestions = @symbolQuery.builtin.suggestions.concat(suggestions)

  addSymbolSelectorsToQuery: (config) ->
    for type, options of config
      @symbolQuery[type] ?= {}
      @symbolQuery[type].selector = Selector.create(options.selector) if options.selector?
      @symbolQuery[type].typePriority = options.typePriority ? 1

      suggestions = @sanitizeSuggestionsFromConfig(options.suggestions, type)
      @symbolQuery[type].suggestions = suggestions if suggestions? and suggestions.length
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
    # TODO: remove conditional when `isTextEditor` is shipped.
    if typeof atom.workspace.isTextEditor is "function"
      atom.workspace.isTextEditor(paneItem)
    else
      return false unless paneItem?
      # Should we disqualify TextEditors with the Grammar text.plain.null-grammar?
      paneItem.getText?

  ###
  Section: Suggesting Completions
  ###

  getSuggestions: ({prefix, scopeDescriptor, editor, bufferPosition}) =>
    prefix = prefix?.trim() ? ""
    return if prefix.length is 0 or prefix.length < @minimumWordLength
    return if @symbolStore.isEmpty()

    unless @scopeDescriptorsEqual(@previousSuggestionsScopeDescriptor, scopeDescriptor)
      @rebuildSymbolQueryForScopeDescriptor(scopeDescriptor)
      @previousSuggestionsScopeDescriptor = scopeDescriptor

    numberOfWordsMatchingPrefix = 1
    wordUnderCursor = @wordAtBufferPosition(editor, bufferPosition)
    for cursor in editor.getCursors()
      continue if cursor is editor.getLastCursor()
      word = @wordAtBufferPosition(editor, cursor.getBufferPosition())
      numberOfWordsMatchingPrefix += 1 if word is wordUnderCursor

    buffer = if @includeCompletionsFromAllBuffers then null else @editor.getBuffer()
    symbolList = @symbolStore.symbolsForConfig(@symbolQuery, buffer, wordUnderCursor, numberOfWordsMatchingPrefix)

    words =
      if atom.config.get("autocomplete-plus.strictMatching")
        symbolList.filter((match) -> match.text?.indexOf(prefix) is 0)
      else
        @fuzzyFilter(symbolList, @editor.getBuffer(), bufferPosition, prefix)

    word.replacementPrefix = prefix for word in words
    return words

  wordAtBufferPosition: (editor, bufferPosition) ->
    lineToPosition = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
    prefix = lineToPosition.match(@endOfLineWordRegex)?[0] or ''
    lineFromPosition = editor.getTextInRange([bufferPosition, [bufferPosition.row, Infinity]])
    suffix = lineFromPosition.match(@beginningOfLineWordRegex)?[0] or ''
    prefix + suffix

  fuzzyFilter: (symbolList, buffer, bufferPosition, prefix) ->
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
