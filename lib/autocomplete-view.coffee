{Editor, $, Range}  = require "atom"
_ = require "underscore-plus"
path = require "path"
minimatch = require "minimatch"
SimpleSelectListView = require "./simple-select-list-view"
fuzzaldrin = require "fuzzaldrin"
Perf = require "./perf"
Utils = require "./utils"

module.exports =
class AutocompleteView extends SimpleSelectListView
  currentBuffer: null
  wordList: null
  wordRegex: /\b\w*[a-zA-Z_]\w*\b/g
  originalCursorPosition: null
  debug: false
  lastConfirmedWord: null

  ###
   * Makes sure we're listening to editor and buffer events, sets
   * the current buffer
   * @param  {EditorView} @editorView
   * @private
  ###
  initialize: (@editorView) ->
    super

    {@editor} = @editorView
    return if @currentFileBlacklisted()

    @addClass "autocomplete-plus"

    @handleEvents()
    @setCurrentBuffer @editor.getBuffer()

  ###
   * Checks whether the current file is blacklisted
   * @return {Boolean}
   * @private
  ###
  currentFileBlacklisted: ->
    blacklist = (atom.config.get("autocomplete-plus.fileBlacklist") or "")
      .split ","
      .map (s) -> s.trim()

    fileName = path.basename @editor.getBuffer().getPath()
    for blacklistGlob in blacklist
      if minimatch fileName, blacklistGlob
        return true

    return false

  ###
   * Handles editor events
   * @private
  ###
  handleEvents: ->
    # Make sure we don't scroll in the editor view when scrolling
    # in the list
    @list.on "mousewheel", (event) -> event.stopPropagation()

    # Is this the event for switching tabs? Dunno...
    @editor.on "title-changed-subscription-removed", @cancel

    # Close the overlay when the cursor moved without
    # changing any text
    @editor.on "cursor-moved", @cursorMoved

  ###
   * Finds autocompletions in the current syntax scope (e.g. css values)
   * @return {Array}
   * @private
  ###
  getCompletionsForCursorScope: ->
    cursorScope = @editor.scopesForBufferPosition @editor.getCursorBufferPosition()
    completions = atom.syntax.propertiesForScope cursorScope, "editor.completions"
    completions = completions.map (properties) -> _.valueForKeyPath properties, "editor.completions"
    return Utils.unique _.flatten(completions)

  ###
   * Generates the word list from the editor buffer(s)
   * @private
  ###
  buildWordList: ->
    # Abuse the Hash as a Set
    wordList = []

    # Do we want autocompletions from all open buffers?
    if atom.config.get "autocomplete-plus.includeCompletionsFromAllBuffers"
      buffers = atom.project.getBuffers()
    else
      buffers = [@currentBuffer]

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

  ###
   * Gets called when the user successfully confirms a suggestion
   * @private
  ###
  confirmed: (match) ->
    @editor.getSelection().clear()
    @cancel()

    return unless match

    @lastConfirmedWord = match.word
    @replaceTextWithMatch match
    position = @editor.getCursorBufferPosition()
    @editor.setCursorBufferPosition [position.row, position.column]

  ###
   * Focuses the editor again
   * @private
  ###
  cancel: =>
    super
    @editorView.focus()

  ###
   * Finds suggestions for the current prefix, sets the list items,
   * positions the overlay and shows it
   * @private
  ###
  runAutocompletion: =>
    selection = @editor.getSelection()
    prefix = @prefixOfSelection selection

    # Stop completion if the word was already confirmed
    return if prefix is @lastConfirmedWord

    # No prefix? Don't autocomplete!
    return unless prefix.length

    suggestions = @findMatchesForWord prefix

    # No suggestions? Don't autocomplete!
    return unless suggestions.length

    # Now we're ready - display the suggestions
    @setItems suggestions
    @editorView.appendToLinesView this
    @setPosition()

    @setActive()

  ###
   * Gets called when the content has been modified
   * @private
  ###
  contentsModified: =>
    if @active
      @detach()
      @list.empty()
      @editorView.focus()

    delay = parseInt(atom.config.get "autocomplete-plus.completionDelay")
    if @delayTimeout
      clearTimeout @delayTimeout

    @delayTimeout = setTimeout @runAutocompletion, delay

  ###
   * Gets called when the cursor has moved. Cancels the autocompletion if
   * the text has not been changed and the autocompletion is
   * @param  {[type]} data [description]
   * @return {[type]}      [description]
  ###
  cursorMoved: (data) =>
    @cancel() unless data.textChanged

  ###
   * Gets called when the user saves the document. Rebuilds the word
   * list and cancels the autocompletion
   * @private
  ###
  onSaved: =>
    @buildWordList()
    @cancel()

  ###
   * Gets called when the buffer's text has been changed. Checks if the user
   * has potentially finished a word and adds the new word to the word list.
   * Cancels the autocompletion if the user entered more than one character
   * with a single keystroke. (= pasting)
   * @param  {Event} e
   * @private
  ###
  onChanged: (e) =>
    if e.newText in ["\n", " "]
      newLine = e.newText is "\n"
      @addLastWordToList newLine

    if e.newText.length is 1
      @contentsModified()
    else
      @cancel()

  ###
   * Finds possible matches for the given string / prefix
   * @param  {String} prefix
   * @return {Array}
   * @private
  ###
  findMatchesForWord: (prefix) ->
    p = new Perf "Finding matches for '#{prefix}'", {@debug}
    p.start()

    # Merge the scope specific words into the default word list
    wordList = _.union @wordList, @getCompletionsForCursorScope()
    words = fuzzaldrin.filter wordList, prefix

    results = for word in words when word isnt prefix
      {prefix, word}

    p.stop()
    return results

  ###
   * Repositions the list view. Checks for boundaries and moves the view
   * above or below the cursor if needed.
   * @private
  ###
  setPosition: ->
    { left, top } = @editorView.pixelPositionForScreenPosition @editor.getCursorScreenPosition()
    cursorLeft = left
    cursorTop = top

    # The top position if we would put it below the current line
    belowPosition = cursorTop + @editorView.lineHeight

    # The top position of the lower edge if we would put it below the current line
    belowLowerPosition = belowPosition + @outerHeight()

    # The position if we would put it above the line
    abovePosition = cursorTop

    if belowLowerPosition > @editorView.outerHeight() + @editorView.scrollTop()
      # We can't put it below - put it above. Using CSS transforms to
      # move it 100% up so that the lower edge is above the current line
      @css left: cursorLeft, top: abovePosition
      @css "-webkit-transform", "translateY(-100%)"
    else
      # We can put it below, remove possible previous CSS transforms
      @css left: cursorLeft, top: belowPosition
      @css "-webkit-transform", ""

  ###
   * Replaces the current prefix with the given match
   * @param {Object} match
   * @private
  ###
  replaceTextWithMatch: (match) ->
    selection = @editor.getSelection()
    startPosition = selection.getBufferRange().start
    buffer = @editor.getBuffer()

    # Replace the prefix with the new word
    cursorPosition = @editor.getCursorBufferPosition()
    buffer.delete Range.fromPointWithDelta(cursorPosition, 0, -match.prefix.length)
    @editor.insertText match.word

    # Move the cursor behind the new word
    suffixLength = match.word.length - match.prefix.length
    @editor.setSelectedBufferRange [startPosition, [startPosition.row, startPosition.column + suffixLength]]

  ###
   * Finds and returns the content before the current cursor position
   * @return {String}
   * @private
  ###
  prefixOfSelection: (selection) ->
    selectionRange = selection.getBufferRange()
    lineRange = [[selectionRange.start.row, 0], [selectionRange.end.row, @editor.lineLengthForBufferRow(selectionRange.end.row)]]
    prefix = ""

    @currentBuffer.scanInRange @wordRegex, lineRange, ({match, range, stop}) ->
      stop() if range.start.isGreaterThan(selectionRange.end)

      if range.intersectsWith(selectionRange)
        prefixOffset = selectionRange.start.column - range.start.column
        prefix = match[0][0...prefixOffset] if range.start.isLessThan(selectionRange.start)

    return prefix

  ###
   * Finds the last typed word. If newLine is set to true, it looks
   * for the last word in the previous line.
   * @param {Boolean} newLine
   * @return {String}
   * @private
  ###
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

  ###
   * As soon as the list is in the DOM tree, it calculates the maximum width of
   * all list items and resizes the list so that all items fit
   * @param {Boolean} onDom
   *
  ###
  afterAttach: (onDom) ->
    return unless onDom

    widestCompletion = parseInt(@css("min-width")) or 0
    @list.find("span").each ->
      widestCompletion = Math.max widestCompletion, $(this).outerWidth()

    @list.width widestCompletion
    @width @list.outerWidth()

  ###
   * Updates the list's position when populating results
   * @private
  ###
  populateList: ->
    p = new Perf "Populating list", {@debug}
    p.start()

    super

    p.stop()
    @setPosition()

  ###
   * Sets the current buffer, starts listening to change events and delegates
   * them to #onChanged()
   * @param {TextBuffer}
   * @private
  ###
  setCurrentBuffer: (@currentBuffer) ->
    @buildWordList()
    @currentBuffer.on "saved", @onSaved
    @currentBuffer.on "changed", @onChanged

  ###
   * Adds the last typed word to the wordList
   * @param {Boolean} newLine
   * @private
  ###
  addLastWordToList: (newLine) ->
    lastWord = @lastTypedWord newLine
    return unless lastWord

    if @wordList.indexOf(lastWord) < 0
      @wordList.push lastWord

  ###
   * Why are we doing this again...?
   * Might be because of autosave:
   * http://git.io/iF32wA
   * @private
  ###
  getModel: -> null

  ###
   * Clean up, stop listening to events
   * @public
  ###
  dispose: ->
    @currentBuffer?.off "changed", @onChanged
    @currentBuffer?.off "saved", @onSaved
    @editor.off "contents-modified", @contentsModified
    @editor.off "title-changed-subscription-removed", @cancel
    @editor.off "cursor-moved", @cursorMoved
