{Editor, Range}  = require 'atom'
{CompositeDisposable} = require 'event-kit'
{$, $$} = require 'space-pen'
_ = require 'underscore-plus'
path = require 'path'
minimatch = require 'minimatch'
SimpleSelectListView = require './simple-select-list-view'
FuzzyProvider = require './fuzzy-provider'
Utils = require './utils'

module.exports =
class AutocompleteView extends SimpleSelectListView
  currentBuffer: null
  debug: false
  originalCursorPosition: null

  # Private: Makes sure we're listening to editor and buffer events, sets
  # the current buffer
  #
  # editor - {TextEditor}
  initialize: (@editor) ->
    @editorView = atom.views.getView(@editor)
    @compositeDisposable = new CompositeDisposable

    super

    @addClass "autocomplete-plus"
    @providers = []

    return if @currentFileBlacklisted()

    @registerProvider new FuzzyProvider(@editor)

    @handleEvents()
    @setCurrentBuffer @editor.getBuffer()

    @compositeDisposable.add atom.commands.add 'atom-text-editor',
      "autocomplete-plus:activate": @runAutocompletion

    # Core events for keyboard handling
    @compositeDisposable.add atom.commands.add '.autocomplete-plus',
      "autocomplete-plus:confirm": @confirmSelection,
      "autocomplete-plus:select-next": @selectNextItemView,
      "autocomplete-plus:select-previous": @selectPreviousItemView,
      "autocomplete-plus:cancel": @cancel

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
    # Close the overlay when the cursor moved without
    # changing any text
    @compositeDisposable.add @editor.onDidChangeCursorPosition(@cursorMoved)

    # Is this the event for switching tabs? Dunno...
    @compositeDisposable.add @editor.onDidChangeTitle(@cancel)

    # Make sure we don't scroll in the editor view when scrolling
    # in the list
    @list.on "mousewheel", (event) -> event.stopPropagation()

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
    unless _.findWhere(@providers, provider)?
      @providers.push(provider)
      @compositeDisposable.add(provider) if provider.dispose?

  # Public: Unregisters the given provider
  #
  # provider - The {Provider} to unregister
  unregisterProvider: (provider) ->
    _.remove(@providers, provider)
    @compositeDisposable.remove(provider)

  # Private: Gets called when the user successfully confirms a suggestion
  #
  # match - An {Object} representing the confirmed suggestion
  confirmed: (match) ->
    return unless match?.provider?
    return unless @editor?
    replace = match.provider.confirm(match)
    return unless replace
    @editor.getSelections()?.forEach (selection) -> selection?.clear()

    @cancel()

    @replaceTextWithMatch(match)
    @editor.getCursors()?.forEach (cursor) ->
      position = cursor?.getBufferPosition()
      cursor.setBufferPosition([position.row, position.column]) if position?

  # Private: Focuses the editor view again
  #
  # focus - {Boolean} should focus
  cancel: =>
    return unless @active
    @overlayDecoration?.destroy()
    @overlayDecoration = undefined
    super
    unless @editorView.hasFocus()
      @editorView.focus()

  # Private: Finds suggestions for the current prefix, sets the list items,
  # positions the overlay and shows it
  runAutocompletion: =>
    return if @compositionInProgress
    @cancel()
    @originalSelectionBufferRanges = @editor.getSelections().map (selection) -> selection.getBufferRange()
    @originalCursorPosition = @editor.getCursorScreenPosition()
    return unless @originalCursorPosition?
    buffer = @editor?.getBuffer()
    return unless buffer?
    options =
      path: buffer.getPath()
      text: buffer.getText()
      pos: @originalCursorPosition

    # Iterate over all providers, ask them to build suggestion(s)
    suggestions = []
    for provider in @providers?.slice()?.reverse()
      providerSuggestions = provider?.buildSuggestions(options)
      continue unless providerSuggestions?.length

      if provider.exclusive
        suggestions = providerSuggestions
        break
      else
        suggestions = suggestions.concat(providerSuggestions)

    # No suggestions? Cancel autocompletion.
    return @cancel() unless suggestions?.length

    # Now we're ready - display the suggestions
    @setItems(suggestions)
    unless @overlayDecoration?
      cursor = @editor.getLastCursor()
      position = cursor?.getBeginningOfCurrentWordBufferPosition()
      marker = @editor.markBufferPosition(position)
      @overlayDecoration = @editor?.decorateMarker(marker, { type: 'overlay', item: this })

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

  editorHasFocus: =>
    editorView = @editorView
    editorView = editorView[0] if editorView.jquery
    return editorView.hasFocus()

  # Private: Gets called when the user saves the document. Cancels the
  # autocompletion
  onSaved: =>
    return unless @editorHasFocus()
    @cancel()

  # Private: Cancels the autocompletion if the user entered more than one character
  # with a single keystroke. (= pasting)
  #
  # e - The change {Event}
  onChanged: (e) =>
    return unless @editorHasFocus()
    if atom.config.get("autocomplete-plus.enableAutoActivation") and ( e.newText.trim().length is 1 or e.oldText.trim().length is 1 )
      @contentsModified()
    else
      # Don't refocus since we probably still have focus
      @cancel()

  # Private: Replaces the current prefix with the given match
  #
  # match - The match to replace the current prefix with
  replaceTextWithMatch: (match) ->
    return unless @editor?
    newSelectedBufferRanges = []

    buffer = @editor.getBuffer()
    return unless buffer?

    selections = @editor.getSelections()
    return unless selections?

    selections.forEach (selection, i) =>
      if selection?
        startPosition = selection.getBufferRange()?.start
        selection.deleteSelectedText()
        cursorPosition = @editor.getCursors()?[i]?.getBufferPosition()
        buffer.delete(Range.fromPointWithDelta(cursorPosition, 0, -match.prefix.length))
        infixLength = match.word.length - match.prefix.length
        newSelectedBufferRanges.push([startPosition, [startPosition.row, startPosition.column + infixLength]])

    @editor.insertText(match.word)
    @editor.setSelectedBufferRanges(newSelectedBufferRanges)

  # Private: As soon as the list is in the DOM tree, it calculates the maximum width of
  # all list items and resizes the list so that all items fit
  #
  # onDom - {Boolean} is the element in the DOM?
  afterAttach: (onDom) ->
    return unless onDom

    widestCompletion = parseInt(@css("min-width")) or 0
    @list.querySelector("li").each ->
      wordWidth = $(this).querySelector("span.word").outerWidth()
      labelWidth = $(this).querySelector("span.label").outerWidth()

      totalWidth = wordWidth + labelWidth + 40
      widestCompletion = Math.max widestCompletion, totalWidth

    @list.width widestCompletion
    @width @list.outerWidth()

  # Private: Updates the list's position when populating results
  populateList: ->
    super

  # Private: Sets the current buffer, starts listening to change events and delegates
  # them to #onChanged()
  #
  # currentBuffer - The current {TextBuffer}
  setCurrentBuffer: (@currentBuffer) ->
    @compositeDisposable.add @currentBuffer.onDidSave(@onSaved)
    @compositeDisposable.add @currentBuffer.onDidChange(@onChanged)

  # Private: Why are we doing this again...?
  # Might be because of autosave:
  # http://git.io/iF32wA
  getModel: -> null

  # Public: Clean up, stop listening to events
  dispose: ->
    @compositeDisposable.dispose()
