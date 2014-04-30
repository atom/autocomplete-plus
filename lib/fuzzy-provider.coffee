_ = require "underscore-plus"
Suggestion = require "./suggestion"
Utils = require "./utils"
fuzzaldrin = require "fuzzaldrin"
Provider = require "./provider"
Perf = require "./perf"

module.exports =
class FuzzyProvider extends Provider
  wordList: null
  debug: false

  initialize: ->
    @buildWordList()

    @currentBuffer = @editor.getBuffer()
    @currentBuffer.on "saved", @onSaved
    @currentBuffer.on "changed", @onChanged

  # Public:  Gets called when the document has been changed. Returns an array
  # with suggestions. If `exclusive` is set to true and this method returns
  # suggestions, the suggestions will be the only ones that are displayed.
  #
  # Returns an {Array} of Suggestion instances
  buildSuggestions: ->
    selection = @editor.getSelection()
    prefix = @prefixOfSelection selection

    # No prefix? Don't autocomplete!
    return unless prefix.length

    suggestions = @findSuggestionsForWord prefix

    # No suggestions? Don't autocomplete!
    return unless suggestions.length

    # Now we're ready - display the suggestions
    return suggestions

  # Public: Gets called when a suggestion has been confirmed by the user. Return
  # true to replace the word with the suggestion. Return false if you want to
  # handle the behavior yourself.
  #
  # item - The confirmed {Suggestion}
  #
  # Returns a {Boolean} that specifies whether autocomplete+ should replace
  # the word with the suggestion.
  confirm: (item) ->
    return true

  # Private: Gets called when the user saves the document. Rebuilds the word
  # list.
  onSaved: =>
    @buildWordList()

  # Private: Gets called when the buffer's text has been changed. Checks if the
  # user has potentially finished a word and adds the new word to the word list.
  #
  # e - The change {Event}
  onChanged: (e) =>
    if e.newText in ["\n", " "]
      newLine = e.newText is "\n"
      @addLastWordToList newLine

  # Private: Adds the last typed word to the wordList
  #
  # newLine - {Boolean} Has a new line been typed?
  addLastWordToList: (newLine) ->
    lastWord = @lastTypedWord newLine
    return unless lastWord

    if @wordList.indexOf(lastWord) < 0
      @wordList.push lastWord

  # Private: Finds the last typed word. If newLine is set to true, it looks
  # for the last word in the previous line.
  #
  # newLine - {Boolean} Has a new line been typed?
  #
  # Returns {String} the last typed word
  lastTypedWord: (newLine) ->
    selectionRange = @editor.getSelection().getBufferRange()
    {row} = selectionRange.start

    # The user pressed enter, check previous line
    if newLine
      row--

    # The user pressed enter, check everything until the end
    if newLine
      maxColumn = @editor.lineLengthForBufferRow row
    else
      maxColumn = selectionRange.start.column

    lineRange = [[row, 0], [row, maxColumn]]

    lastWord = null
    @currentBuffer.scanInRange @wordRegex, lineRange, ({match, range, stop}) ->
      lastWord = match[0]

    return lastWord

  # Private: Generates the word list from the editor buffer(s)
  buildWordList: ->
    # Abuse the Hash as a Set
    wordList = []

    # Do we want autocompletions from all open buffers?
    if atom.config.get "autocomplete-plus.includeCompletionsFromAllBuffers"
      buffers = atom.project.getBuffers()
    else
      buffers = [@editor.getBuffer()]

    # Check how long the word list building took
    p = new Perf "Building word list", {@debug}
    p.start()

    # Collect words from all buffers using the regular expression
    matches = []
    matches.push(buffer.getText().match(@wordRegex)) for buffer in buffers

    # Flatten the matches, make it an unique array
    wordList = _.flatten matches
    wordList = Utils.unique wordList
    @wordList = wordList

    p.stop()

  # Private: Finds possible matches for the given string / prefix
  #
  # prefix - {String} The prefix
  #
  # Returns an {Array} of Suggestion instances
  findSuggestionsForWord: (prefix) ->
    p = new Perf "Finding matches for '#{prefix}'", {@debug}
    p.start()

    # Merge the scope specific words into the default word list
    wordList = @wordList.concat @getCompletionsForCursorScope()
    words = fuzzaldrin.filter wordList, prefix

    results = for word in words when word isnt prefix
      new Suggestion this, word: word, prefix: prefix

    p.stop()
    return results

  # Private: Finds autocompletions in the current syntax scope (e.g. css values)
  #
  # Returns an {Array} of strings
  getCompletionsForCursorScope: ->
    cursorScope = @editor.scopesForBufferPosition @editor.getCursorBufferPosition()
    completions = atom.syntax.propertiesForScope cursorScope, "editor.completions"
    completions = completions.map (properties) -> _.valueForKeyPath properties, "editor.completions"
    return Utils.unique _.flatten(completions)

  # Public: Clean up, stop listening to events
  dispose: ->
    @currentBuffer?.off "changed", @onChanged
    @currentBuffer?.off "saved", @onSaved
