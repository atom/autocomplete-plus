# This provider is currently experimental.

_ = require 'underscore-plus'
{TextBuffer, Range, CompositeDisposable}  = require 'atom'
{Selector} = require 'selector-kit'
{UnicodeLetters} = require './unicode-helpers'
SymbolStore = require './symbol-store'

# TODO: remove this when `onDidStopChanging(changes)` ships on stable.
bufferSupportsStopChanging = -> typeof TextBuffer::onDidChangeText is "function"

module.exports =
class SymbolProvider
  wordRegex: null
  beginningOfLineWordRegex: null
  endOfLineWordRegex: null
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
    @subscriptions = new CompositeDisposable
    @subscriptions.add(atom.config.observe('autocomplete-plus.enableExtendedUnicodeSupport', (enableExtendedUnicodeSupport) =>
      if enableExtendedUnicodeSupport
        @wordRegex = new RegExp("[#{UnicodeLetters}\\d_]*[#{UnicodeLetters}}_-]+[#{UnicodeLetters}}\\d_]*(?=[^#{UnicodeLetters}\\d_]|$)", 'g')
        @beginningOfLineWordRegex = new RegExp("^[#{UnicodeLetters}\\d_]*[#{UnicodeLetters}_-]+[#{UnicodeLetters}\\d_]*(?=[^#{UnicodeLetters}\\d_]|$)", 'g')
        @endOfLineWordRegex = new RegExp("[#{UnicodeLetters}\\d_]*[#{UnicodeLetters}_-]+[#{UnicodeLetters}\\d_]*$", 'g')
      else
        @wordRegex = /\b\w*[a-zA-Z_-]+\w*\b/g
        @beginningOfLineWordRegex = /^\w*[a-zA-Z_-]+\w*\b/g
        @endOfLineWordRegex = /\b\w*[a-zA-Z_-]+\w*$/g

      @symbolStore = new SymbolStore(@wordRegex)
    ))
    @watchedBuffers = new WeakMap

    @subscriptions.add(atom.config.observe('autocomplete-plus.minimumWordLength', (@minimumWordLength) => ))
    @subscriptions.add(atom.config.observe('autocomplete-plus.includeCompletionsFromAllBuffers', (@includeCompletionsFromAllBuffers) => ))
    @subscriptions.add(atom.config.observe('autocomplete-plus.useAlternateScoring', (useAlternateScoring) => @symbolStore.setUseAlternateScoring(useAlternateScoring)))
    @subscriptions.add(atom.config.observe('autocomplete-plus.useLocalityBonus', (useLocalityBonus) => @symbolStore.setUseLocalityBonus(useLocalityBonus)))
    @subscriptions.add(atom.config.observe('autocomplete-plus.strictMatching', (useStrictMatching) => @symbolStore.setUseStrictMatching(useStrictMatching)))
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
      if bufferSupportsStopChanging()
        bufferSubscriptions.add buffer.onDidStopChanging ({changes}) =>
          editors = @watchedBuffers.get(buffer)
          if editors and editors.length and editor = editors[0]
            for {start, oldExtent, newExtent} in changes
              @symbolStore.recomputeSymbolsForEditorInBufferRange(editor, start, oldExtent, newExtent)
      else
        bufferSubscriptions.add buffer.onDidChange ({oldRange, newRange}) =>
          editors = @watchedBuffers.get(buffer)
          if editors and editors.length and editor = editors[0]
            start = oldRange.start
            oldExtent = oldRange.getExtent()
            newExtent = newRange.getExtent()
            @symbolStore.recomputeSymbolsForEditorInBufferRange(editor, start, oldExtent, newExtent)

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

  getSuggestions: (options) =>
    prefix = options.prefix?.trim()
    return unless prefix?.length and prefix?.length >= @minimumWordLength

    @buildConfigIfScopeChanged(options)

    {editor, prefix, bufferPosition} = options
    numberOfWordsMatchingPrefix = 1
    wordUnderCursor = @wordAtBufferPosition(editor, bufferPosition)
    for cursor in editor.getCursors()
      continue if cursor is editor.getLastCursor()
      word = @wordAtBufferPosition(editor, cursor.getBufferPosition())
      numberOfWordsMatchingPrefix += 1 if word is wordUnderCursor

    buffers = if @includeCompletionsFromAllBuffers then null else [@editor.getBuffer()]
    symbolList = @symbolStore.symbolsForConfig(
      @config, buffers,
      prefix, wordUnderCursor,
      bufferPosition.row,
      numberOfWordsMatchingPrefix
    )

    symbolList.sort (a, b) -> (b.score * b.localityScore) - (a.score * a.localityScore)
    symbolList.slice(0, 20).map (a) -> a.symbol

  wordAtBufferPosition: (editor, bufferPosition) ->
    lineToPosition = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
    prefix = lineToPosition.match(@endOfLineWordRegex)?[0] or ''
    lineFromPosition = editor.getTextInRange([bufferPosition, [bufferPosition.row, Infinity]])
    suffix = lineFromPosition.match(@beginningOfLineWordRegex)?[0] or ''
    prefix + suffix

  settingsForScopeDescriptor: (scopeDescriptor, keyPath) ->
    atom.config.getAll(keyPath, scope: scopeDescriptor)

  ###
  Section: Word List Building
  ###

  buildWordListOnNextTick: (editor) =>
    _.defer =>
      return unless editor?.isAlive()
      start = {row: 0, column: 0}
      oldExtent = {row: 0, column: 0}
      newExtent = editor.getBuffer().getRange().getExtent()
      @symbolStore.recomputeSymbolsForEditorInBufferRange(editor, start, oldExtent, newExtent)

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
