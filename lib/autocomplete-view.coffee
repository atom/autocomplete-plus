_ = require 'underscore-plus'
{$, $$, Range, SelectListView}  = require 'atom'

module.exports =
class AutocompleteView extends SelectListView
  currentBuffer: null
  wordList: null
  wordRegex: /\w+/g
  originalSelectionBufferRange: null
  originalCursorPosition: null
  aboveCursor: false

  initialize: (@editorView) ->
    super
    @addClass('autocomplete popover-list')
    {@editor} = @editorView
    @handleEvents()
    @setCurrentBuffer(@editor.getBuffer())

  getFilterKey: ->
    'word'

  viewForItem: ({word}) ->
    $$ ->
      @li =>
        @span word

  handleEvents: ->
    @list.on 'mousewheel', (event) -> event.stopPropagation()

    @editorView.on 'editor:path-changed', => @setCurrentBuffer(@editor.getBuffer())
    @editorView.command 'autocomplete:toggle', =>
      if @hasParent()
        @cancel()
      else
        @attach()
    @editorView.command 'autocomplete:next', => @selectNextItemView()
    @editorView.command 'autocomplete:previous', => @selectPreviousItemView()

    @filterEditorView.preempt 'textInput', ({originalEvent}) =>
      text = originalEvent.data
      unless text.match(@wordRegex)
        @confirmSelection()
        @editor.insertText(text)
        false

  setCurrentBuffer: (@currentBuffer) ->

  selectItemView: (item) ->
    super
    if match = @getSelectedItem()
      @replaceSelectedTextWithMatch(match)

  selectNextItemView: ->
    super
    false

  selectPreviousItemView: ->
    super
    false

  getCompletionsForCursorScope: ->
    cursorScope = @editor.scopesForBufferPosition(@editor.getCursorBufferPosition())
    completions = atom.syntax.propertiesForScope(cursorScope, 'editor.completions')
    completions = completions.map (properties) -> _.valueForKeyPath(properties, 'editor.completions')
    _.uniq(_.flatten(completions))

  buildWordList: ->
    wordHash = {}
    if atom.config.get('autocomplete.includeCompletionsFromAllBuffers')
      buffers = atom.project.getBuffers()
    else
      buffers = [@currentBuffer]
    matches = []
    matches.push(buffer.getText().match(@wordRegex)) for buffer in buffers
    wordHash[word] ?= true for word in _.flatten(matches)
    wordHash[word] ?= true for word in @getCompletionsForCursorScope()

    @wordList = Object.keys(wordHash).sort (word1, word2) ->
      word1.toLowerCase().localeCompare(word2.toLowerCase())

  confirmed: (match) ->
    @editor.getSelection().clear()
    @cancel()
    return unless match
    @replaceSelectedTextWithMatch match
    position = @editor.getCursorBufferPosition()
    @editor.setCursorBufferPosition([position.row, position.column + match.suffix.length])

  cancelled: ->
    super

    @editor.abortTransaction()
    @editor.setSelectedBufferRange(@originalSelectionBufferRange)
    @editorView.focus()

  attach: ->
    @editor.beginTransaction()

    @aboveCursor = false
    @originalSelectionBufferRange = @editor.getSelection().getBufferRange()
    @originalCursorPosition = @editor.getCursorScreenPosition()

    @buildWordList()
    matches = @findMatchesForCurrentSelection()
    @setItems(matches)

    if matches.length is 1
      @confirmSelection()
    else
      @editorView.appendToLinesView(this)
      @setPosition()
      @focusFilterEditor()

  setPosition: ->
    { left, top } = @editorView.pixelPositionForScreenPosition(@originalCursorPosition)
    height = @outerHeight()
    potentialTop = top + @editorView.lineHeight
    potentialBottom = potentialTop - @editorView.scrollTop() + height

    if @aboveCursor or potentialBottom > @editorView.outerHeight()
      @aboveCursor = true
      @css(left: left, top: top - height, bottom: 'inherit')
    else
      @css(left: left, top: potentialTop, bottom: 'inherit')

  findMatchesForCurrentSelection: ->
    selection = @editor.getSelection()
    {prefix, suffix} = @prefixAndSuffixOfSelection(selection)

    if (prefix.length + suffix.length) > 0
      regex = new RegExp("^#{prefix}.+#{suffix}$", "i")
      currentWord = prefix + @editor.getSelectedText() + suffix
      for word in @wordList when regex.test(word) and word != currentWord
        {prefix, suffix, word}
    else
      {word, prefix, suffix} for word in @wordList

  replaceSelectedTextWithMatch: (match) ->
    selection = @editor.getSelection()
    startPosition = selection.getBufferRange().start
    buffer = @editor.getBuffer()

    selection.deleteSelectedText()
    cursorPosition = @editor.getCursorBufferPosition()
    buffer.delete(Range.fromPointWithDelta(cursorPosition, 0, match.suffix.length))
    buffer.delete(Range.fromPointWithDelta(cursorPosition, 0, -match.prefix.length))
    @editor.insertText(match.word)

    infixLength = match.word.length - match.prefix.length - match.suffix.length
    @editor.setSelectedBufferRange([startPosition, [startPosition.row, startPosition.column + infixLength]])

  prefixAndSuffixOfSelection: (selection) ->
    selectionRange = selection.getBufferRange()
    lineRange = [[selectionRange.start.row, 0], [selectionRange.end.row, @editor.lineLengthForBufferRow(selectionRange.end.row)]]
    [prefix, suffix] = ["", ""]

    @currentBuffer.scanInRange @wordRegex, lineRange, ({match, range, stop}) ->
      stop() if range.start.isGreaterThan(selectionRange.end)

      if range.intersectsWith(selectionRange)
        prefixOffset = selectionRange.start.column - range.start.column
        suffixOffset = selectionRange.end.column - range.end.column

        prefix = match[0][0...prefixOffset] if range.start.isLessThan(selectionRange.start)
        suffix = match[0][suffixOffset..] if range.end.isGreaterThan(selectionRange.end)

    {prefix, suffix}

  afterAttach: (onDom) ->
    if onDom
      widestCompletion = parseInt(@css('min-width')) or 0
      @list.find('span').each ->
        widestCompletion = Math.max(widestCompletion, $(this).outerWidth())
      @list.width(widestCompletion)
      @width(@list.outerWidth())

  populateList: ->
    super

    @setPosition()
