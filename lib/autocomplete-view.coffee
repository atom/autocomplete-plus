{Editor, $, $$, Range}  = require "atom"
_ = require "underscore-plus"
path = require "path"
minimatch = require "minimatch"
SimpleSelectListView = require "./simple-select-list-view"
FuzzyProvider = require "./fuzzy-provider"
Perf = require "./perf"
Utils = require "./utils"

module.exports =
class AutocompleteView extends SimpleSelectListView
  currentBuffer: null
  debug: false

  # Private: Makes sure we're listening to editor and buffer events, sets
  # the current buffer
  #
  # editorView - {EditorView}
  initialize: (@editorView) ->
    {@editor} = @editorView

    super

    @addClass "autocomplete-plus"
    @providers = []

    return if @currentFileBlacklisted()

    @registerProvider new FuzzyProvider(@editorView)

    @handleEvents()
    @setCurrentBuffer @editor.getBuffer()

    @subscribeToCommand @editorView, "autocomplete-plus:activate", @runAutocompletion

    @on "autocomplete-plus:select-next", => @selectNextItemView()
    @on "autocomplete-plus:select-previous", => @selectPreviousItemView()
    @on "autocomplete-plus:cancel", => @cancel()

  # Private: Checks whether the current file is blacklisted
  #
  # Returns {Boolean} that defines whether the current file is blacklisted
  currentFileBlacklisted: ->
    blacklist = (atom.config.get("autocomplete-plus.fileBlacklist") or "")
      .split ","
      .map (s) -> s.trim()

    fileName = path.basename @editor.getBuffer().getPath()
    for blacklistGlob in blacklist
      if minimatch fileName, blacklistGlob
        return true

    return false

  # Private: Creates a view for the given item
  #
  # Returns a {jQuery} object that represents the item view
  viewForItem: ({word, label, renderLabelAsHtml, className}) ->
    item = $$ ->
      @li =>
        @span word, class: "word"
        if label?
          @span label, class: "label"

    if renderLabelAsHtml
      item.find(".label").html label

    if className?
      item.addClass className

    return item

  # Private: Escapes HTML from the given string
  #
  # string - The {String} to escape
  #
  # Returns the escaped {String}
  escapeHtml: (string) ->
    escapedString = string
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')

    return escapedString

  # Private: Handles editor events
  handleEvents: ->
    # Make sure we don't scroll in the editor view when scrolling
    # in the list
    @list.on "mousewheel", (event) -> event.stopPropagation()

    # Is this the event for switching tabs? Dunno...
    @editor.on "title-changed-subscription-removed", @cancel

    # Close the overlay when the cursor moved without
    # changing any text
    @editor.on "cursor-moved", @cursorMoved

    @hiddenInput.on 'compositionstart', =>
      @compositionInProgress = true
      null

    @hiddenInput.on 'compositionend', =>
      @compositionInProgress = false
      null

  # Public: Registers the given provider
  #
  # provider - The {Provider} to register
  registerProvider: (provider) ->
    @providers.push(provider) unless _.findWhere(@providers, provider)?

  # Public: Unregisters the given provider
  #
  # provider - The {Provider} to unregister
  unregisterProvider: (provider) ->
    _.remove @providers, provider

  # Private: Gets called when the user successfully confirms a suggestion
  #
  # match - An {Object} representing the confirmed suggestion
  confirmed: (match) ->
    replace = match.provider.confirm match

    @editor.getSelection().clear()
    @cancel()

    return unless match

    if replace
      @replaceTextWithMatch match
      position = @editor.getCursorBufferPosition()
      @editor.setCursorBufferPosition [position.row, position.column]

  # Private: Focuses the editor view again
  #
  # focus - {Boolean} should focus
  cancel: =>
    super
    unless @editorView.hasFocus()
      @editorView.focus()

  # Private: Finds suggestions for the current prefix, sets the list items,
  # positions the overlay and shows it
  runAutocompletion: =>
    return if @compositionInProgress

    # Iterate over all providers, ask them to build word lists
    suggestions = []
    for provider in @providers.slice().reverse()
      providerSuggestions = provider.buildSuggestions()
      continue unless providerSuggestions?.length

      if provider.exclusive
        suggestions = providerSuggestions
        break
      else
        suggestions = suggestions.concat providerSuggestions

    # No suggestions? Cancel autocompletion.
    return @cancel() unless suggestions.length

    # Now we're ready - display the suggestions
    @setItems suggestions
    @editorView.appendToLinesView this
    @setPosition()

    @setActive()

  # Private: Gets called when the content has been modified
  contentsModified: =>
    delay = parseInt(atom.config.get "autocomplete-plus.autoActivationDelay")
    if @delayTimeout
      clearTimeout @delayTimeout

    @delayTimeout = setTimeout @runAutocompletion, delay

  # Private: Gets called when the cursor has moved. Cancels the autocompletion if
  # the text has not been changed and the autocompletion is
  #
  # data - An {Object} containing information on why the cursor has been moved
  cursorMoved: (data) =>
    @cancel() unless data.textChanged

  # Private: Gets called when the user saves the document. Cancels the
  # autocompletion
  onSaved: =>
    @cancel()

  # Private: Cancels the autocompletion if the user entered more than one character
  # with a single keystroke. (= pasting)
  #
  # e - The change {Event}
  onChanged: (e) =>
    typedText = e.newText.trim()
    if typedText.length is 1 and atom.config.get "autocomplete-plus.enableAutoActivation"
      @contentsModified()
    else
      # Don't refocus since we probably still have focus
      @cancel()

  # Private: Repositions the list view. Checks for boundaries and moves the view
  # above or below the cursor if needed.
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

  # Private: Replaces the current prefix with the given match
  #
  # match - The match to replace the current prefix with
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

  # Private: As soon as the list is in the DOM tree, it calculates the maximum width of
  # all list items and resizes the list so that all items fit
  #
  # onDom - {Boolean} is the element in the DOM?
  afterAttach: (onDom) ->
    return unless onDom

    widestCompletion = parseInt(@css("min-width")) or 0
    @list.find("li").each ->
      wordWidth = $(this).find("span.word").outerWidth()
      labelWidth = $(this).find("span.label").outerWidth()

      totalWidth = wordWidth + labelWidth + 40
      widestCompletion = Math.max widestCompletion, totalWidth

    @list.width widestCompletion
    @width @list.outerWidth()

  # Private: Updates the list's position when populating results
  populateList: ->
    p = new Perf "Populating list", {@debug}
    p.start()

    super

    p.stop()
    @setPosition()

  # Private: Sets the current buffer, starts listening to change events and delegates
  # them to #onChanged()
  #
  # currentBuffer - The current {TextBuffer}
  setCurrentBuffer: (@currentBuffer) ->
    @currentBuffer.on "saved", @onSaved
    @currentBuffer.on "changed", @onChanged

  # Private: Why are we doing this again...?
  # Might be because of autosave:
  # http://git.io/iF32wA
  getModel: -> null

  # Public: Clean up, stop listening to events
  dispose: ->
    @currentBuffer?.off "changed", @onChanged
    @currentBuffer?.off "saved", @onSaved
    @editor.off "title-changed-subscription-removed", @cancel
    @editor.off "cursor-moved", @cursorMoved
    for provider in @providers when provider.dispose?
      provider.dispose()
