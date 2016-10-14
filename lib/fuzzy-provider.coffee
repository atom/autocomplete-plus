fuzzaldrin = require 'fuzzaldrin'
{CompositeDisposable}  = require 'atom'
RefCountedTokenList = require './ref-counted-token-list'
{UnicodeLetters} = require './unicode-helpers'

module.exports =
class FuzzyProvider
  deferBuildWordListInterval: 300
  updateBuildWordListTimeout: null
  updateCurrentEditorTimeout: null
  wordRegex: null
  tokenList: new RefCountedTokenList()
  currentEditorSubscriptions: null
  editor: null
  buffer: null

  scopeSelector: '*'
  inclusionPriority: 0
  suggestionPriority: 0

  constructor: ->
    @subscriptions = new CompositeDisposable
    @subscriptions.add(atom.config.observe('autocomplete-plus.enableExtendedUnicodeSupport', (enableExtendedUnicodeSupport) =>
      if enableExtendedUnicodeSupport
        @wordRegex = new RegExp("[#{UnicodeLetters}\\d_]+[#{UnicodeLetters}\\d_-]*", 'g')
      else
        @wordRegex = /\b\w+[\w-]*\b/g
    ))
    @debouncedBuildWordList()
    @subscriptions.add(atom.workspace.observeActivePaneItem(@debouncedUpdateCurrentEditor))
    builtinProviderBlacklist = atom.config.get('autocomplete-plus.builtinProviderBlacklist')
    @disableForScopeSelector = builtinProviderBlacklist if builtinProviderBlacklist? and builtinProviderBlacklist.length

  debouncedUpdateCurrentEditor: (currentPaneItem) =>
    clearTimeout(@updateBuildWordListTimeout)
    clearTimeout(@updateCurrentEditorTimeout)
    @updateCurrentEditorTimeout = setTimeout =>
      @updateCurrentEditor(currentPaneItem)
    , @deferBuildWordListInterval

  updateCurrentEditor: (currentPaneItem) =>
    return unless currentPaneItem?
    return if currentPaneItem is @editor

    # Stop listening to buffer events
    @currentEditorSubscriptions?.dispose()

    @editor = null
    @buffer = null

    return unless @paneItemIsValid(currentPaneItem)

    # Track the new editor, editorView, and buffer
    @editor = currentPaneItem
    @buffer = @editor.getBuffer()

    # Subscribe to buffer events:
    @currentEditorSubscriptions = new CompositeDisposable
    unless @editor.largeFileMode
      @currentEditorSubscriptions.add @buffer.onDidSave(@bufferSaved)
      @currentEditorSubscriptions.add @buffer.onWillChange(@bufferWillChange)
      @currentEditorSubscriptions.add @buffer.onDidChange(@bufferDidChange)
      @buildWordList()

  paneItemIsValid: (paneItem) ->
    # TODO: remove conditional when `isTextEditor` is shipped.
    if typeof atom.workspace.isTextEditor is "function"
      atom.workspace.isTextEditor(paneItem)
    else
      return false unless paneItem?
      # Should we disqualify TextEditors with the Grammar text.plain.null-grammar?
      paneItem.getText?

  # Public:  Gets called when the document has been changed. Returns an array
  # with suggestions. If `exclusive` is set to true and this method returns
  # suggestions, the suggestions will be the only ones that are displayed.
  #
  # Returns an {Array} of Suggestion instances
  getSuggestions: ({editor, prefix, scopeDescriptor}) =>
    return unless editor?

    # No prefix? Don't autocomplete!
    return unless prefix.trim().length

    suggestions = @findSuggestionsForWord(prefix, scopeDescriptor)

    # No suggestions? Don't autocomplete!
    return unless suggestions?.length

    # Now we're ready - display the suggestions
    return suggestions

  # Private: Gets called when the user saves the document. Rebuilds the word
  # list.
  bufferSaved: =>
    @buildWordList()

  bufferWillChange: ({oldRange}) =>
    oldLines = @editor.getTextInBufferRange([[oldRange.start.row, 0], [oldRange.end.row, Infinity]])
    @removeWordsForText(oldLines)

  bufferDidChange: ({newRange}) =>
    newLines = @editor.getTextInBufferRange([[newRange.start.row, 0], [newRange.end.row, Infinity]])
    @addWordsForText(newLines)

  debouncedBuildWordList: ->
    clearTimeout(@updateBuildWordListTimeout)
    @updateBuildWordListTimeout = setTimeout =>
      @buildWordList()
    , @deferBuildWordListInterval

  buildWordList: =>
    return unless @editor?

    @tokenList.clear()

    if atom.config.get('autocomplete-plus.includeCompletionsFromAllBuffers')
      editors = atom.workspace.getTextEditors()
    else
      editors = [@editor]

    for editor in editors
      @addWordsForText(editor.getText())

  addWordsForText: (text) ->
    minimumWordLength = atom.config.get('autocomplete-plus.minimumWordLength')
    matches = text.match(@wordRegex)
    return unless matches?
    for match in matches
      if (minimumWordLength and match.length >= minimumWordLength) or not minimumWordLength
        @tokenList.addToken(match)

  removeWordsForText: (text) ->
    matches = text.match(@wordRegex)
    return unless matches?
    for match in matches
      @tokenList.removeToken(match)

  # Private: Finds possible matches for the given string / prefix
  #
  # prefix - {String} The prefix
  #
  # Returns an {Array} of Suggestion instances
  findSuggestionsForWord: (prefix, scopeDescriptor) =>
    return unless @tokenList.getLength() and @editor?

    # Merge the scope specific words into the default word list
    tokens = @tokenList.getTokens()
    tokens = tokens.concat(@getCompletionsForCursorScope(scopeDescriptor))

    words =
      if atom.config.get('autocomplete-plus.strictMatching')
        tokens.filter((word) -> word?.indexOf(prefix) is 0)
      else
        fuzzaldrin.filter(tokens, prefix)

    results = []

    # dont show matches that are the same as the prefix
    for word in words when word isnt prefix
      # must match the first char!
      continue unless word and prefix and prefix[0].toLowerCase() is word[0].toLowerCase()
      results.push {text: word, replacementPrefix: prefix}
    results

  settingsForScopeDescriptor: (scopeDescriptor, keyPath) ->
    atom.config.getAll(keyPath, scope: scopeDescriptor)

  # Private: Finds autocompletions in the current syntax scope (e.g. css values)
  #
  # Returns an {Array} of strings
  getCompletionsForCursorScope: (scopeDescriptor) ->
    completions = @settingsForScopeDescriptor(scopeDescriptor, 'editor.completions')
    seen = {}
    resultCompletions = []
    for {value} in completions
      if Array.isArray(value)
        for completion in value
          unless seen[completion]
            resultCompletions.push(completion)
            seen[completion] = true
    resultCompletions

  # Public: Clean up, stop listening to events
  dispose: =>
    clearTimeout(@updateBuildWordListTimeout)
    clearTimeout(@updateCurrentEditorTimeout)
    @currentEditorSubscriptions?.dispose()
    @subscriptions.dispose()
