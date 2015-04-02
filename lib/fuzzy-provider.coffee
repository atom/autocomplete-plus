_ = require 'underscore-plus'
fuzzaldrin = require 'fuzzaldrin'
{TextEditor, CompositeDisposable}  = require 'atom'
RefCountedTokenList = require './ref-counted-token-list'

module.exports =
class FuzzyProvider
  deferBuildWordListInterval: 300
  updateBuildWordListTimeout: null
  updateCurrentEditorTimeout: null
  wordRegex: /\b\w+[\w-]*\b/g
  tokenList: new RefCountedTokenList()
  currentEditorSubscriptions: null
  editor: null
  buffer: null

  selector: '*'
  inclusionPriority: 0
  suggestionPriority: 0
  id: 'autocomplete-plus-fuzzyprovider'

  constructor: ->
    @debouncedBuildWordList()
    @subscriptions = new CompositeDisposable
    @subscriptions.add(atom.workspace.observeActivePaneItem(@debouncedUpdateCurrentEditor))
    builtinProviderBlacklist = atom.config.get('autocomplete-plus.builtinProviderBlacklist')
    @disableForSelector = builtinProviderBlacklist if builtinProviderBlacklist? and builtinProviderBlacklist.length

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
    @currentEditorSubscriptions.add @buffer.onDidSave(@bufferSaved)
    @currentEditorSubscriptions.add @buffer.onWillChange(@bufferWillChange)
    @currentEditorSubscriptions.add @buffer.onDidChange(@bufferDidChange)
    @buildWordList()

  paneItemIsValid: (paneItem) ->
    return false unless paneItem?
    # Should we disqualify TextEditors with the Grammar text.plain.null-grammar?
    return paneItem instanceof TextEditor

  # Public:  Gets called when the document has been changed. Returns an array
  # with suggestions. If `exclusive` is set to true and this method returns
  # suggestions, the suggestions will be the only ones that are displayed.
  #
  # Returns an {Array} of Suggestion instances
  getSuggestions: ({editor, prefix}) =>
    return unless editor?

    # No prefix? Don't autocomplete!
    return unless prefix.trim().length

    suggestions = @findSuggestionsForWord(prefix)

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
      editors = atom.workspace.getEditors()
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
  findSuggestionsForWord: (prefix) =>
    return unless @tokenList.getLength() and @editor?

    # Merge the scope specific words into the default word list
    tokens = @tokenList.getTokens()
    tokens = tokens.concat(@getCompletionsForCursorScope())

    words =
      if atom.config.get('autocomplete-plus.strictMatching')
        tokens.filter((word) -> word?.indexOf(prefix) is 0)
      else
        fuzzaldrin.filter(tokens, prefix)

    results = []

    # dont show matches that are the same as the prefix
    for word in words when word isnt prefix
      # must match the first char!
      continue unless prefix[0].toLowerCase() is word[0].toLowerCase()

      results.push {text: word, replacementPrefix: prefix}

    results

  settingsForScopeDescriptor: (scopeDescriptor, keyPath) ->
    return [] unless atom?.config? and scopeDescriptor? and keyPath?
    entries = atom.config.getAll(null, {scope: scopeDescriptor})
    value for {value} in entries when _.valueForKeyPath(value, keyPath)?

  # Private: Finds autocompletions in the current syntax scope (e.g. css values)
  #
  # Returns an {Array} of strings
  getCompletionsForCursorScope: =>
    cursorScope = @editor.scopeDescriptorForBufferPosition(@editor.getCursorBufferPosition())
    completions = @settingsForScopeDescriptor(cursorScope?.getScopesArray(), 'editor.completions')
    completions = completions.map((properties) -> _.valueForKeyPath(properties, 'editor.completions'))
    return _.uniq(_.flatten(completions))

  # Public: Clean up, stop listening to events
  dispose: =>
    clearTimeout(@updateBuildWordListTimeout)
    clearTimeout(@updateCurrentEditorTimeout)
    @currentEditorSubscriptions?.dispose()
    @subscriptions.dispose()
