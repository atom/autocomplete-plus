{Editor, $, Range, Point, SelectListView}  = require "atom"
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
  aboveCursor: false
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

    @addClass "autocomplete popover-list"

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
    @list.on 'mousewheel', (event) -> event.stopPropagation()

    # Listen to `contents-modified` event when live completion is disabled
    unless atom.config.get('autocomplete-plus.liveCompletion')
      @editor.on 'contents-modified', @contentsModified

    # Is this the event for switching tabs? Dunno...
    @editor.on 'title-changed-subscription-removed', @cancel

    # Close the overlay when the cursor moved without
    # changing any text
    @editor.on 'cursor-moved', @cursorMoved

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

    wordList = _.flatten matches
    wordList = Utils.unique wordList
    @wordList = wordList

    p.stop()

  ###
   * Handles confirmation (the user pressed enter)
  ###
  confirmed: (match) ->
    @editor.getSelection().clear()
    @cancel()

    return unless match

    @lastConfirmedWord = match.word
    @replaceTextWithMatch match
    position = @editor.getCursorBufferPosition()
    @editor.setCursorBufferPosition([position.row, position.column])

  ###
   * Activates
  ###
  setActive: ->
    super
    @active = true

  ###
   * Clears the list, sets back the cursor, focuses the editor and
   * detaches the list DOM element
  ###
  cancel: =>
    @active = false

    @list.empty()

    @editorView.focus()

    @detach()

  contentsModified: =>
    if @active
      @detach()
      @list.empty()
      @editorView.focus()

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

  cursorMoved: (data) =>
    if not data.textChanged and @active
      @cancel()

  onSaved: =>
    @buildWordList()
    @cancel()

  onChanged: (e) =>
    if e.newText in ["\n", " "]
      @addLastWordToList e.newText is "\n"

    if e.newText.length is 1
      @contentsModified()
    else
      @cancel()

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

  setPosition: ->
    { left, top } = @editorView.pixelPositionForScreenPosition(@editor.getCursorScreenPosition())
    height = @outerHeight()
    potentialTop = top + @editorView.lineHeight
    potentialBottom = potentialTop - @editorView.scrollTop() + height

    if @aboveCursor or potentialBottom > @editorView.outerHeight()
      @aboveCursor = true
      @css(left: left, top: top - height, bottom: 'inherit')
    else
      @css(left: left, top: potentialTop, bottom: 'inherit')

  ###
   * Replaces the current prefix with the given match
  ###
  replaceTextWithMatch: (match) ->
    selection = @editor.getSelection()
    startPosition = selection.getBufferRange().start
    buffer = @editor.getBuffer()

    selection.deleteSelectedText()
    cursorPosition = @editor.getCursorBufferPosition()
    buffer.delete(Range.fromPointWithDelta(cursorPosition, 0, -match.prefix.length))
    @editor.insertText(match.word)

    infixLength = match.word.length - match.prefix.length
    @editor.setSelectedBufferRange([startPosition, [startPosition.row, startPosition.column + infixLength]])

  ###
   * Finds and returns the content before the current cursor position
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
   * As soon as the list is in the DOM tree, it calculates the
   * maximum width of all list items and resizes the list so that
   * all items fit
   *
   * @todo: Fix this. Doesn't work well yet.
  ###
  afterAttach: (onDom) ->
    if onDom
      widestCompletion = parseInt(@css('min-width')) or 0
      @list.find('span').each ->
        widestCompletion = Math.max(widestCompletion, $(this).outerWidth())

      @list.width widestCompletion
      @width @list.outerWidth()

  ###
   * Updates the list's position when populating results
  ###
  populateList: ->
    p = new Perf "Populating list", {@debug}
    p.start()

    super

    p.stop()

    @setPosition()

  ###
   * Sets the current buffer
  ###
  setCurrentBuffer: (@currentBuffer) ->
    @buildWordList()
    @currentBuffer.on "saved", @onSaved

    if atom.config.get('autocomplete-plus.liveCompletion')
      @currentBuffer.on "changed", @onChanged

  ###
   * Adds the last typed word to the wordList
  ###
  addLastWordToList: (newLine) ->
    lastWord = @lastTypedWord newLine
    return unless lastWord

    if @wordList.indexOf(lastWord) < 0
      @wordList.push lastWord

  ###
   * Defines which key we would like to use for filtering
  ###
  getFilterKey: -> 'word'

  getModel: -> null

  dispose: ->
    @editor.off "contents-modified", @contentsModified
    @currentBuffer?.off "changed", @onChanged
    @currentBuffer?.off "saved", @onSaved
    @editor.off "contents-modified", @contentsModified
    @editor.off "title-changed-subscription-removed", @cancel
    @editor.off "cursor-moved", @cursorMoved
