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
    @symbolStore = new SymbolStore(@wordRegex)
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

    @buildWordListOnNextTick()

  buildConfigIfScopeChanged: ({editor, scopeDescriptor}) ->
    unless @scopeDescriptorsEqual(@configScopeDescriptor, scopeDescriptor)
      @buildConfig(scopeDescriptor)
      @configScopeDescriptor = scopeDescriptor

  buildConfig: (scopeDescriptor) ->
    @config = {}

    allConfig = @settingsForScopeDescriptor(scopeDescriptor, 'editor.completionConfig')
    allConfig.push {value: @defaultConfig} unless allConfig.length

    for {value} in allConfig
      for type, options of value
        @config[type] ?= {}
        @config[type].selectors = Selector.create(options.selector) if options.selector?
        @config[type].typePriority = options.typePriority ? 1
        @config[type].wordRegex = @wordRegex

        suggestions = @sanitizeSuggestionsFromConfig(options.suggestions, type)
        @config[type].suggestions = suggestions if suggestions? and suggestions.length

    if builtinSuggestions = @legacyCompletionsForScopeDescriptor(scopeDescriptor)
      @config.builtin = {suggestions: builtinSuggestions}

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

  legacyCompletionsForScopeDescriptor: (scopeDescriptor) ->
    completions = @settingsForScopeDescriptor(scopeDescriptor, "editor.completions")
    scopedCompletions = null
    for {value} in completions
      for suggestion in value when value?
        scopedCompletions ?= []
        scopedCompletions.push
          text: suggestion
          type: 'builtin'
    scopedCompletions = _.uniq(scopedCompletions, @uniqueFilter) if scopedCompletions?
    scopedCompletions

  uniqueFilter: (completion) -> completion.text

  paneItemIsValid: (paneItem) ->
    return false unless paneItem?
    # Should we disqualify TextEditors with the Grammar text.plain.null-grammar?
    return paneItem instanceof TextEditor

  # Notes on change updates:
  #
  # * Reading of the tokens must happen synchonously in the event handlers as
  #   thats the only time the buffer will have the tokens matching the change events.
  # * The slow part is the token scope selector matching to bucket tokens by type.
  bufferWillChange: ({oldRange}) =>
    @symbolStore.removeTokensInBufferRange(@editor, oldRange)

  bufferDidChange: ({newRange}) =>
    @symbolStore.addTokensInBufferRange(@editor, newRange)

  ###
  Section: Suggesting Completions
  ###

  getSuggestions: (options) =>
    # No prefix? Don't autocomplete!
    return unless options.prefix.trim().length
    @findSuggestionsForWord(options)

  findSuggestionsForWord: (options) =>
    return unless @symbolStore.getLength()
    wordUnderCursor = @wordAtBufferPosition(options)
    @buildConfigIfScopeChanged(options)
    symbolList = @symbolStore.symbolsForConfig(@config)

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

  fuzzyFilter: (symbolList, editorPath, {bufferPosition, prefix}) ->
    # Probably inefficient to do a linear search
    candidates = []
    for symbol in symbolList
      continue unless prefix[0].toLowerCase() is symbol.text[0].toLowerCase() # must match the first char!
      score = fuzzaldrin.score(symbol.text, prefix)
      score *= @getLocalityScore(bufferPosition, symbol.bufferRowsForEditorPath?(editorPath))
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

  buildWordListOnNextTick: =>
    _.defer => @buildSymbolList()

  buildSymbolList: =>
    return unless @editor?

    @symbolStore.clear()

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
        @symbolStore.addToken(token, editorPath, bufferRow, minimumWordLength)
    return

  getTokenizedLines: (editor) ->
    # Warning: displayBuffer and tokenizedBuffer are private APIs. Please do not
    # copy into your own package. If you do, be prepared to have it break
    # without warning.
    editor.displayBuffer.tokenizedBuffer.tokenizedLines

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
