_ = require 'underscore-plus'
fuzzaldrin = require 'fuzzaldrin'
{TextEditor, CompositeDisposable}  = require 'atom'

module.exports =
class FuzzyProvider
  wordRegex: /\b\w*[a-zA-Z_-]+\w*\b/g
  wordList: null
  editor: null
  buffer: null

  selector: '*'
  inclusionPriority: 0
  id: 'autocomplete-plus-fuzzyprovider'

  constructor: ->
    @subscriptions = new CompositeDisposable
    @subscriptions.add(atom.workspace.observeActivePaneItem(@updateCurrentEditor))
    @buildWordList()
    builtinProviderBlacklist = atom.config.get('autocomplete-plus.builtinProviderBlacklist')
    @disableForSelector = builtinProviderBlacklist if builtinProviderBlacklist? and builtinProviderBlacklist.length

  updateCurrentEditor: (currentPaneItem) =>
    return unless currentPaneItem?
    return if currentPaneItem is @editor

    # Stop listening to buffer events
    @bufferSavedSubscription?.dispose()
    @bufferChangedSubscription?.dispose()

    @editor = null
    @buffer = null

    return unless @paneItemIsValid(currentPaneItem)

    # Track the new editor, editorView, and buffer
    @editor = currentPaneItem
    @buffer = @editor.getBuffer()

    # Subscribe to buffer events:
    @bufferSavedSubscription = @buffer.onDidSave(@bufferSaved)
    @bufferChangedSubscription = @buffer.onDidChange(@bufferChanged)
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
    return unless prefix.length

    suggestions = @findSuggestionsForWord(prefix)

    # No suggestions? Don't autocomplete!
    return unless suggestions.length

    # Now we're ready - display the suggestions
    return suggestions

  # Private: Gets called when the user saves the document. Rebuilds the word
  # list.
  bufferSaved: =>
    @buildWordList()

  # Private: Gets called when the buffer's text has been changed. Checks if the
  # user has potentially finished a word and adds the new word to the word list.
  #
  # e - The change {Event}
  bufferChanged: (e) =>
    wordChars = 'ąàáäâãåæăćęèéëêìíïîłńòóöôõøśșțùúüûñçżź' +
      'abcdefghijklmnopqrstuvwxyz1234567890'
    if wordChars.indexOf(e.newText.toLowerCase()) is -1
      newline = e.newText is '\n'
      @addLastWordToList(e.newRange.start.row, e.newRange.start.column, newline)

  # Private: Adds the last typed word to the wordList
  #
  # newLine - {Boolean} Has a new line been typed?
  addLastWordToList: (row, column, newline) =>
    lastWord = @lastTypedWord(row, column, newline)
    return unless lastWord

    if @wordList.indexOf(lastWord) < 0
      @wordList.push(lastWord)

  # Private: Finds the last typed word. If newLine is set to true, it looks
  # for the last word in the previous line.
  #
  # newLine - {Boolean} Has a new line been typed?
  #
  # Returns {String} the last typed word
  lastTypedWord: (row, column, newline) =>
    # The user pressed enter, check everything until the end
    if newline
      maxColumn = column - 1 unless column = 0
    else
      maxColumn = column

    lineRange = [[row, 0], [row, column]]

    lastWord = null
    @buffer.scanInRange(@wordRegex, lineRange, ({match, range, stop}) -> lastWord = match[0])

    return lastWord

  # Private: Generates the word list from the editor buffer(s)
  buildWordList: =>
    return unless @editor?

    # Abuse the Hash as a Set
    wordList = []

    # Do we want autocompletions from all open buffers?
    if atom.config.get('autocomplete-plus.includeCompletionsFromAllBuffers')
      editors = atom.workspace.getEditors()
    else
      editors = [@editor]

    # Collect words from all buffers using the regular expression
    matches = []
    matches.push(editor.getText().match(@wordRegex)) for editor in editors

    # Flatten the matches, make it an unique array
    wordList = _.uniq(_.flatten(matches))

    # Filter words by length
    minimumWordLength = atom.config.get('autocomplete-plus.minimumWordLength')
    if minimumWordLength
      wordList = wordList.filter((word) -> word?.length >= minimumWordLength)

    @wordList = wordList

  # Private: Finds possible matches for the given string / prefix
  #
  # prefix - {String} The prefix
  #
  # Returns an {Array} of Suggestion instances
  findSuggestionsForWord: (prefix) =>
    return unless @wordList?
    # Merge the scope specific words into the default word list
    wordList = @wordList.concat(@getCompletionsForCursorScope())

    words =
      if atom.config.get('autocomplete-plus.strictMatching')
        wordList.filter((word) -> word?.indexOf(prefix) is 0)
      else
        fuzzaldrin.filter(wordList, prefix)

    results = for word in words when word isnt prefix
      {text: word, replacementPrefix: prefix}

    return results

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
    @bufferSavedSubscription?.dispose()
    @bufferChangedSubscription?.dispose()
    @subscriptions.dispose()
