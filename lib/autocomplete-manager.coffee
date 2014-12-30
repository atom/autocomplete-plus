{Range}  = require 'atom'
{Emitter, CompositeDisposable} = require 'event-kit'
_ = require 'underscore-plus'
path = require 'path'
minimatch = require 'minimatch'
FuzzyProvider = require './fuzzy-provider'

module.exports =
class AutocompleteManager
  currentBuffer: null
  debug: false

  # Private: Makes sure we're listening to editor and buffer events, sets
  # the current buffer
  #
  # editor - {TextEditor}
  constructor: (@editor) ->
    @editorView = atom.views.getView(@editor)
    @compositeDisposable = new CompositeDisposable
    @emitter = new Emitter

    @providers = []

    return if @currentFileBlacklisted()

    @registerProvider new FuzzyProvider(@editor)

    @handleEvents()
    @setCurrentBuffer @editor.getBuffer()

    @compositeDisposable.add atom.workspace.observeActivePaneItem(@updateCurrentEditor)

    @compositeDisposable.add atom.commands.add 'atom-text-editor',
      "autocomplete-plus:activate": @runAutocompletion

    @compositeDisposable.add atom.commands.add 'autocomplete-suggestion-list',
      "autocomplete-plus:confirm": @confirmSelection,
      "autocomplete-plus:select-next": @selectNext,
      "autocomplete-plus:select-previous": @selectPrevious,
      "autocomplete-plus:cancel": @cancel

  addKeyboardInteraction: ->
    @removeKeyboardInteraction()
    keys =
      "escape": "autocomplete-plus:cancel"

    completionKey = atom.config.get("autocomplete-plus.confirmCompletion") || ''
    navigationKey = atom.config.get("autocomplete-plus.navigateCompletions") || ''


    keys['tab'] = "autocomplete-plus:confirm" if completionKey.indexOf('tab') > -1
    keys['enter'] = "autocomplete-plus:confirm" if completionKey.indexOf('enter') > -1

    if @items?.length > 1 and navigationKey == "up,down"
      keys['up'] =  "autocomplete-plus:select-previous"
      keys['down'] = "autocomplete-plus:select-next"
    else
      keys["ctrl-n"] = "autocomplete-plus:select-next"
      keys["ctrl-p"] = "autocomplete-plus:select-previous"

    @keymaps = atom.keymaps.add(
      'AutocompleteManager',
      'atom-text-editor:not(.mini) .autocomplete-plus': keys
    )

    @compositeDisposable.add @keymaps

  removeKeyboardInteraction: ->
    @keymaps?.dispose()
    @compositeDisposable.remove(@keymaps)

  updateCurrentEditor: (currentPaneItem) =>
    @cancel() unless currentPaneItem == @editor

  confirmSelection: =>
    @emitter.emit 'do-confirm-selection'

  onDoConfirmSelection: (cb) ->
    @emitter.on 'do-confirm-selection', cb

  selectNext: =>
    @emitter.emit 'do-select-next'

  onDoSelectNext: (cb) ->
    @emitter.on 'do-select-next', cb

  selectPrevious: =>
    @emitter.emit 'do-select-previous'

  onDoSelectPrevious: (cb) ->
    @emitter.on 'do-select-previous', cb

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


  # Private: Handles editor events
  handleEvents: ->
    # Close the overlay when the cursor moved without
    # changing any text
    @compositeDisposable.add @editor.onDidChangeCursorPosition(@cursorMoved)

    # Is this the event for switching tabs? Dunno...
    @compositeDisposable.add @editor.onDidChangeTitle(@cancel)

  # Public: Registers the given provider
  #
  # provider - The {Provider} to register
  registerProvider: (provider) ->
    unless _.findWhere(@providers, provider)?
      @providers.push(provider)
      @compositeDisposable.add provider if provider.dispose?

  # Public: Unregisters the given provider
  #
  # provider - The {Provider} to unregister
  unregisterProvider: (provider) ->
    _.remove(@providers, provider)
    @compositeDisposable.remove(provider)

  # Private: Gets called when the user successfully confirms a suggestion
  #
  # match - An {Object} representing the confirmed suggestion
  confirm: (match) ->
    return unless @editorHasFocus()
    return unless match?.provider?
    return unless @editor?

    replace = match.provider.confirm(match)
    @editor.getSelections()?.forEach (selection) -> selection?.clear()

    @cancel()

    return unless replace
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
    @removeKeyboardInteraction()
    @editorView.focus()
    @active = false

  # Private: Finds suggestions for the current prefix, sets the list items,
  # positions the overlay and shows it
  runAutocompletion: =>
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
    return unless suggestions.length

    unless @overlayDecoration?
      marker = @editor.getLastCursor()?.getMarker()
      @overlayDecoration = @editor?.decorateMarker(marker, { type: 'overlay', item: this })

    # Now we're ready - display the suggestions
    @changeItems suggestions

    @setActive()

  changeItems: (items) ->
    @items = items
    @emitter.emit 'did-change-items', items

  onDidChangeItems: (cb) ->
    @emitter.on 'did-change-items', cb

  # Private: Focuses the hidden input, starts listening to keyboard events
  setActive: ->
    @addKeyboardInteraction()
    @active = true

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
  editorSaved: =>
    return unless @editorHasFocus()
    @cancel()

  # Private: Cancels the autocompletion if the user entered more than one character
  # with a single keystroke. (= pasting)
  #
  # e - The change {Event}
  editorChanged: (e) =>
    return if @compositionInProgress
    return unless @editorHasFocus()
    if atom.config.get("autocomplete-plus.enableAutoActivation") and ( e.newText.trim().length is 1 or e.oldText.trim().length is 1 )
      @contentsModified()
    else
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

  # Private: Sets the current buffer, starts listening to change events and delegates
  # them to #onChanged()
  #
  # currentBuffer - The current {TextBuffer}
  setCurrentBuffer: (@currentBuffer) ->
    @compositeDisposable.add @currentBuffer.onDidSave(@editorSaved)
    @compositeDisposable.add @currentBuffer.onDidChange(@editorChanged)

  # Public: Clean up, stop listening to events
  dispose: ->
    @compositeDisposable.dispose()
    @emitter.emit 'did-dispose'

  onDidDispose: (cb) ->
    @emitter.on 'did-dispose', cb
