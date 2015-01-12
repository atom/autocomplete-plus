{Range}  = require 'atom'
{Emitter, CompositeDisposable} = require 'event-kit'
_ = require 'underscore-plus'
path = require 'path'
minimatch = require 'minimatch'
FuzzyProvider = require './fuzzy-provider'
SuggestionList = require './suggestion-list'
SuggestionListElement = require './suggestion-list-element'

module.exports =
class AutocompleteManager
  editor: null
  editorView: null
  buffer: null
  suggestionList: null
  editorSubscription: null
  bufferSavedSubscription: null
  bufferChangedSubscription: null
  editorCursorMovedSubscription: null
  didChangeTabsSubscription: null

  constructor: ->
    @subscriptions = new CompositeDisposable
    @emitter = new Emitter

    # TODO: Track provider <-> grammar registrations
    @providers = []

    # Register Suggestion List Model and View
    @subscriptions.add(atom.views.addViewProvider(SuggestionList, (model) =>
      new SuggestionListElement().initialize(model)
    ))
    @suggestionList = new SuggestionList()

    @handleEvents()
    @handleCommands()

    # TODO: Use FuzzyProvider only as an option of last resort
    @registerProvider(new FuzzyProvider())

  updateCurrentEditor: (currentPaneItem) =>
    return unless currentPaneItem?
    return if currentPaneItem is @editor

    # Stop listening to buffer events
    @bufferSavedSubscription?.dispose()
    @bufferChangedSubscription?.dispose()

    # Stop listening to editor events
    @editorCursorMovedSubscription?.dispose()
    @didChangeTabsSubscription?.dispose()

    # Disqualify invalid pane items
    # TODO
    if false
      @editor = null
      @editorView = null
      @buffer = null

    # Track the new editor, editorView, and buffer
    @editor = currentPaneItem
    @editorView = atom.views.getView(@editor)
    @buffer = @editor.getBuffer()

    # Subscribe to buffer events:
    @bufferSavedSubscription = @buffer.onDidSave(@bufferSaved)
    @bufferChangedSubscription = @buffer.onDidChange(@bufferChanged)

    # Subscribe to editor events:
    # Close the overlay when the cursor moved without changing any text
    @editorCursorMovedSubscription = @editor.onDidChangeCursorPosition(@cursorMoved)
    # TODO: Is this the event for switching tabs?
    @didChangeTabsSubscription = @editor.onDidChangeTitle(@hideSuggestionList)

  # Private: Handles editor events
  handleEvents: ->
    # Track the current pane item, update current editor
    @subscriptions.add(atom.workspace.observeActivePaneItem(@updateCurrentEditor))

    # Handle events from suggestion list
    @subscriptions.add(@suggestionList.onDidConfirm(@confirm))
    @subscriptions.add(@suggestionList.onDidCancel(@hideSuggestionList))

  handleCommands: ->
    # Allow autocomplete to be triggered via keymap
    @subscriptions.add(atom.commands.add 'atom-text-editor',
      'autocomplete-plus:activate': @runAutocompletion
    )

  # Private: Finds suggestions for the current prefix, sets the list items,
  # positions the overlay and shows it
  runAutocompletion: =>
    @hideSuggestionList()
    return unless @editor?
    return unless @buffer?
    return if @currentFileBlacklisted()
    @originalCursorPosition = @editor.getCursorScreenPosition()
    return unless @originalCursorPosition?
    options =
      editor: @editor
      buffer: @buffer
      pos: @originalCursorPosition
      prefixOfSelection: @prefixOfSelection(@editor.getLastSelection())

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
    @suggestionList?.changeItems(suggestions)
    @showSuggestionList()


  # Private: Gets called when the user successfully confirms a suggestion
  #
  # match - An {Object} representing the confirmed suggestion
  confirm: (match) =>
    return unless @editorHasFocus()
    return unless match?.provider?
    return unless @editor?

    replace = match.provider.confirm(match)
    @editor.getSelections()?.forEach (selection) -> selection?.clear()

    @hideSuggestionList()

    return unless replace
    @replaceTextWithMatch(match)
    @editor.getCursors()?.forEach (cursor) ->
      position = cursor?.getBufferPosition()
      cursor.setBufferPosition([position.row, position.column]) if position?

  showSuggestionList: ->
    @suggestionList?.show(@editor)

  hideSuggestionList: ->
    # TODO: Should we *always* focus the editor? Probably not...
    @suggestionList?.hideAndFocusOn(@editorView)

  # Private: Replaces the current prefix with the given match.
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

  # Public: Finds and returns the content before the current cursor position
  #
  # selection - The {Selection} for the current cursor position
  #
  # Returns {String} with the prefix of the {Selection}
  prefixOfSelection: (selection) ->
    selectionRange = selection.getBufferRange()
    lineRange = [[selectionRange.start.row, 0], [selectionRange.end.row, @editor.lineTextForBufferRow(selectionRange.end.row).length]]
    prefix = ''
    wordRegex = /\b\w*[a-zA-Z_-]+\w*\b/g
    @editor.getBuffer().scanInRange wordRegex, lineRange, ({match, range, stop}) ->
      stop() if range.start.isGreaterThan(selectionRange.end)

      if range.intersectsWith(selectionRange)
        prefixOffset = selectionRange.start.column - range.start.column
        prefix = match[0][0...prefixOffset] if range.start.isLessThan(selectionRange.start)

    return prefix

  # Private: Checks whether the current file is blacklisted.
  #
  # Returns {Boolean} that defines whether the current file is blacklisted
  currentFileBlacklisted: ->
    blacklist = (atom.config.get('autocomplete-plus.fileBlacklist') or '')
      .split(',')
      .map((s) -> s.trim())

    fileName = path.basename(@editor.getBuffer().getPath())
    for blacklistGlob in blacklist
      return true if minimatch(fileName, blacklistGlob)

    return false

  # Private: Gets called when the content has been modified
  contentsModified: =>
    delay = parseInt(atom.config.get('autocomplete-plus.autoActivationDelay'))
    clearTimeout(@delayTimeout) if @delayTimeout
    @delayTimeout = setTimeout(@runAutocompletion, delay)

  # Private: Gets called when the cursor has moved. Cancels the autocompletion if
  # the text has not been changed.
  #
  # data - An {Object} containing information on why the cursor has been moved
  cursorMoved: (data) =>
    @hideSuggestionList() unless data.textChanged

  editorHasFocus: =>
    return false unless @editorView?
    editorView = @editorView
    editorView = editorView[0] if editorView.jquery
    return editorView.hasFocus()

  # Private: Gets called when the user saves the document. Cancels the
  # autocompletion.
  bufferSaved: =>
    return unless @editorHasFocus()
    @hideSuggestionList()

  # Private: Cancels the autocompletion if the user entered more than one
  # character with a single keystroke. (= pasting)
  #
  # e - The change {Event}
  bufferChanged: (e) =>
    return if @suggestionList.compositionInProgress
    return unless @editorHasFocus()
    if atom.config.get('autocomplete-plus.enableAutoActivation') and (e.newText.trim().length is 1 or e.oldText.trim().length is 1)
      @contentsModified()
    else
      @hideSuggestionList()

  #  |||              |||
  #  vvv PROVIDER API vvv

  # Public: Registers the given provider
  #
  # provider - The {Provider} to register
  registerProvider: (provider) ->
    unless _.findWhere(@providers, provider)?
      @providers.push(provider)
      @subscriptions.add(provider) if provider.dispose?

  # Public: Unregisters the given provider
  #
  # provider - The {Provider} to unregister
  unregisterProvider: (provider) ->
    return unless provider?
    _.remove(@providers, provider)
    @subscriptions.remove(provider)

  # ^^^ PROVIDER API ^^^
  # |||              |||

  # Public: Clean up, stop listening to events
  dispose: ->
    @editorSubscription?.dispose()
    @editorSubscription = null
    @bufferSavedSubscription?.dispose()
    @bufferSavedSubscription = null
    @bufferChangedSubscription?.dispose()
    @bufferChangedSubscription = null
    @editorCursorMovedSubscription?.dispose()
    @editorCursorMovedSubscription = null
    @didChangeTabsSubscription?.dispose()
    @didChangeTabsSubscription = null
    @suggestionList.destroy()
    @subscriptions.dispose()
    @emitter.emit('did-dispose')

  onDidDispose: (fn) ->
    @emitter.on('did-dispose', fn)
