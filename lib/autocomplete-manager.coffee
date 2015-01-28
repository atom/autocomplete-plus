{Range, TextEditor}  = require 'atom'
{CompositeDisposable, Disposable, Emitter} = require 'event-kit'
_ = require 'underscore-plus'
minimatch = require 'minimatch'
path = require 'path'
ProviderManager = require './provider-manager'
SuggestionList = require './suggestion-list'
SuggestionListElement = require './suggestion-list-element'

module.exports =
class AutocompleteManager
  editor: null
  editorView: null
  buffer: null
  providerManager: null
  subscriptions: null
  suggestionList: null
  editorSubscriptions: null

  constructor: ->
    @subscriptions = new CompositeDisposable
    @providerManager = new ProviderManager()
    @subscriptions.add(@providerManager)
    @emitter = new Emitter

    # Register Suggestion List Model and View
    @subscriptions.add(atom.views.addViewProvider(SuggestionList, (model) =>
      new SuggestionListElement().initialize(model)
    ))
    @suggestionList = new SuggestionList()

    @handleEvents()
    @handleCommands()

  updateCurrentEditor: (currentPaneItem) =>
    return unless currentPaneItem?
    return if currentPaneItem is @editor

    @editorSubscriptions?.dispose()
    @editorSubscriptions = null

    # Stop tracking editor + buffer
    @editor = null
    @editorView = null
    @buffer = null

    return unless @paneItemIsValid(currentPaneItem)

    # Track the new editor, editorView, and buffer
    @editor = currentPaneItem
    @editorView = atom.views.getView(@editor)
    @buffer = @editor.getBuffer()

    @editorSubscriptions = new CompositeDisposable

    # Subscribe to buffer events:
    @editorSubscriptions.add(@buffer.onDidSave(@bufferSaved))
    @editorSubscriptions.add(@buffer.onDidChange(@bufferChanged))

    # Subscribe to editor events:
    # Close the overlay when the cursor moved without changing any text
    @editorSubscriptions.add(@editor.onDidChangeCursorPosition(@cursorMoved))

  paneItemIsValid: (paneItem) =>
    return false unless paneItem?
    # Should we disqualify TextEditors with the Grammar text.plain.null-grammar?
    return paneItem instanceof TextEditor

  # Private: Handles editor events
  handleEvents: =>
    # Track the current pane item, update current editor
    @subscriptions.add(atom.workspace.observeActivePaneItem(@updateCurrentEditor))

    # Handle events from suggestion list
    @subscriptions.add(@suggestionList.onDidConfirm(@confirm))
    @subscriptions.add(@suggestionList.onDidCancel(@hideSuggestionList))

  handleCommands: =>
    # Allow autocomplete to be triggered via keymap
    @subscriptions.add(atom.commands.add 'atom-text-editor',
      'autocomplete-plus:activate': @runAutocompletion
    )

  # Private: Finds suggestions for the current prefix, sets the list items,
  # positions the overlay and shows it
  runAutocompletion: =>
    @hideSuggestionList()
    return unless @providerManager?
    return unless @editor?
    return unless @buffer?
    return if @isCurrentFileBlackListed()
    cursor = @editor.getLastCursor()
    return unless cursor?
    cursorPosition = cursor.getBufferPosition()
    currentScope = cursor.getScopeDescriptor()
    return unless currentScope?
    currentScopeChain = currentScope.getScopeChain()
    return unless currentScopeChain?

    options =
      editor: @editor
      buffer: @buffer
      cursor: cursor
      position: cursorPosition
      scope: currentScope
      scopeChain: currentScopeChain
      prefix: @prefixForCursor(cursor)

    @scatterRequest(options)

  scatterRequest: (options) =>
    providers = @providerManager.providersForScopeChain(options.scopeChain)
    return unless providers? and providers.length
    providers = providers.map (provider) ->
      providerSuggestions = provider?.requestHandler(options)
    return unless providers? and providers.length
    @currentSuggestionsPromise = suggestionsPromise = Promise.all(providers)
      .then _.partial(@gatherSuggestions, providers)
      .then (suggestions) => @showSuggestions(suggestions, suggestionsPromise, options)

  showSuggestions: (suggestions, suggestionsPromise, options) =>
    unless suggestions.length
      @emitter.emit 'did-autocomplete', {options, suggestions}
      return
    suggestions = _.uniq(suggestions, (s) -> s.word)
    # Show the suggestion list if we have not already requested more suggestions
    @showSuggestionList(suggestions) if @currentSuggestionsPromise == suggestionsPromise
    @emitter.emit 'did-autocomplete', {options, suggestions}

  # Private: gather suggestions based on providers
  #
  # providers - An array of providers to check against provided suggestions
  # providerSuggestions - array of arrays of suggestions provided by all called providers
  gatherSuggestions: (providers, providerSuggestions) ->
    providerSuggestions.reduce (suggestions, providerSuggestions, index) ->
      provider = providers[index]

      return suggestions unless providerSuggestions?.length
      suggestions = suggestions.concat(providerSuggestions)
      suggestions
    ,[]

  prefixForCursor: (cursor) =>
    return '' unless @buffer? and cursor?
    start = cursor.getBeginningOfCurrentWordBufferPosition()
    end = cursor.getBufferPosition()
    return '' unless start? and end?
    @buffer.getTextInRange(new Range(start, end))

  # Private: Gets called when the user successfully confirms a suggestion
  #
  # match - An {Object} representing the confirmed suggestion
  confirm: (match) =>
    return unless @editor?

    match.onWillConfirm() if match.onWillConfirm?

    @editor.getSelections()?.forEach (selection) -> selection?.clear()
    @hideSuggestionList()

    @replaceTextWithMatch(match)

    if match.isSnippet? and match.isSnippet
      setTimeout(=>
          atom.commands.dispatch(atom.views.getView(@editor), 'snippets:expand')
        , 1)

    match.onDidConfirm() if match.onDidConfirm?

  showSuggestionList: (suggestions) ->
    @suggestionList.changeItems(suggestions)
    @suggestionList.show(@editor)

  hideSuggestionList: =>
    # TODO: Should we *always* focus the editor? Probably not...
    @suggestionList?.hideAndFocusOn(@editorView)

  # Private: Replaces the current prefix with the given match.
  #
  # match - The match to replace the current prefix with
  replaceTextWithMatch: (match) =>
    return unless @editor?
    newSelectedBufferRanges = []

    buffer = @editor.getBuffer()
    return unless buffer?

    selections = @editor.getSelections()
    return unless selections?
    @editor.transact =>
      @editor.selectLeft(match.prefix.length)
      @editor.delete()
      @editor.insertText(match.word)

  # Private: Checks whether the current file is blacklisted.
  #
  # Returns {Boolean} that defines whether the current file is blacklisted
  isCurrentFileBlackListed: =>
    blacklist = atom.config.get('autocomplete-plus.fileBlacklist')?.map((s) -> s.trim())
    return false unless blacklist? and blacklist.length
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

  # Private: Gets called when the user saves the document. Cancels the
  # autocompletion.
  bufferSaved: =>
    @hideSuggestionList()

  # Private: Cancels the autocompletion if the user entered more than one
  # character with a single keystroke. (= pasting)
  #
  # e - The change {Event}
  bufferChanged: (e) =>
    return if @suggestionList.compositionInProgress
    if atom.config.get('autocomplete-plus.enableAutoActivation') and (e.newText.trim().length is 1 or e.oldText.trim().length is 1)
      @contentsModified()
    else
      @hideSuggestionList()

  onDidAutocomplete: (callback) ->
    @emitter.on 'did-autocomplete', callback

  # Public: Clean up, stop listening to events
  dispose: ->
    @editorSubscriptions?.dispose()
    @editorSubscriptions = null
    @suggestionList?.destroy()
    @suggestionList = null
    @subscriptions?.dispose()
    @subscriptions = null
    @providerManager = null
    @emitter?.emit('did-dispose')
    @emitter?.dispose()
    @emitter = null
