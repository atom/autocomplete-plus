{Range, TextEditor, CompositeDisposable, Disposable}  = require 'atom'
_ = require 'underscore-plus'
path = require 'path'
ProviderManager = require './provider-manager'
SuggestionList = require './suggestion-list'
SuggestionListElement = require './suggestion-list-element'
semver = require 'semver'

# Deferred requires
minimatch = null

module.exports =
class AutocompleteManager
  autosaveEnabled: false
  backspaceTriggersAutocomplete: true
  buffer: null
  compositionInProgress: false
  disposed: false
  editor: null
  editorSubscriptions: null
  editorView: null
  providerManager: null
  ready: false
  subscriptions: null
  suggestionDelay: 50
  suggestionList: null
  shouldDisplaySuggestions: false

  constructor: ->
    @subscriptions = new CompositeDisposable
    @providerManager = new ProviderManager
    @suggestionList = new SuggestionList

    @subscriptions.add(@providerManager)
    @subscriptions.add atom.views.addViewProvider SuggestionList, (model) ->
      new SuggestionListElement().initialize(model)

    @handleEvents()
    @handleCommands()
    @subscriptions.add(@suggestionList) # We're adding this last so it is disposed after events
    @ready = true

  setSnippetsManager: (@snippetsManager) ->

  updateCurrentEditor: (currentPaneItem) =>
    return if not currentPaneItem? or currentPaneItem is @editor

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

    # Watch IME Events To Allow IME To Function Without The Suggestion List Showing
    compositionStart = => @compositionInProgress = true
    compositionEnd = => @compositionInProgress = false

    @editorView.addEventListener('compositionstart', compositionStart)
    @editorView.addEventListener('compositionend', compositionEnd)
    @editorSubscriptions.add new Disposable ->
      @editorView?.removeEventListener('compositionstart', compositionStart)
      @editorView?.removeEventListener('compositionend', compositionEnd)

    # Subscribe to editor events:
    # Close the overlay when the cursor moved without changing any text
    @editorSubscriptions.add(@editor.onDidChangeCursorPosition(@cursorMoved))

  paneItemIsValid: (paneItem) ->
    return false unless paneItem?
    # Should we disqualify TextEditors with the Grammar text.plain.null-grammar?
    return paneItem instanceof TextEditor

  handleEvents: =>
    # Track the current pane item, update current editor
    @subscriptions.add(atom.workspace.observeActivePaneItem(@updateCurrentEditor))

    # Watch config values
    @subscriptions.add(atom.config.observe('autosave.enabled', (value) => @autosaveEnabled = value))
    @subscriptions.add(atom.config.observe('autocomplete-plus.backspaceTriggersAutocomplete', (value) => @backspaceTriggersAutocomplete = value))

    # Handle events from suggestion list
    @subscriptions.add(@suggestionList.onDidConfirm(@confirm))
    @subscriptions.add(@suggestionList.onDidCancel(@hideSuggestionList))

  handleCommands: =>
    @subscriptions.add atom.commands.add 'atom-text-editor',
      'autocomplete-plus:activate': =>
        @shouldDisplaySuggestions = true
        @findSuggestions()

  # Private: Finds suggestions for the current prefix, sets the list items,
  # positions the overlay and shows it
  findSuggestions: =>
    return if @disposed
    return unless @providerManager? and @editor? and @buffer?
    return if @isCurrentFileBlackListed()
    cursor = @editor.getLastCursor()
    return unless cursor?

    position = cursor.getBufferPosition()
    scopeDescriptor = cursor.getScopeDescriptor()
    prefix = @prefixForCursor(cursor)

    @getSuggestionsFromProviders({@editor, position, scopeDescriptor, prefix})

  getSuggestionsFromProviders: (options) =>
    providers = @providerManager.providersForScopeDescriptor(options.scopeDescriptor)

    providerPromises = []
    providers.forEach (provider) =>
      apiVersion = @providerManager.apiVersionForProvider(provider)
      apiIs20 = semver.satisfies(apiVersion, '>=2.0.0')

      # TODO API: remove upgrading when 1.0 support is removed
      upgradedOptions = options
      unless apiIs20
        upgradedOptions = _.extend {}, options,
          scope: options.scopeDescriptor
          scopeChain: options.scopeDescriptor.getScopeChain()
          buffer: options.editor.getBuffer()
          cursor: options.editor.getLastCursor()

      providerPromises.push Promise.resolve(provider.requestHandler(upgradedOptions)).then (providerSuggestions) ->
        # TODO API: remove upgrading when 1.0 support is removed
        unless apiIs20
          providerSuggestions = providerSuggestions.map (suggestion) ->
            newSuggestion =
              text: suggestion.word
              snippet: suggestion.snippet
              replacementPrefix: suggestion.prefix
              className: suggestion.className
            newSuggestion.rightLabelHTML = suggestion.label if suggestion.renderLabelAsHtml
            newSuggestion.rightLabel = suggestion.label unless suggestion.renderLabelAsHtml
            newSuggestion

        providerSuggestions

    return unless providerPromises?.length
    @currentSuggestionsPromise = suggestionsPromise = Promise.all(providerPromises)
      .then(@mergeSuggestionsFromProviders)
      .then (suggestions) =>
        if @currentSuggestionsPromise is suggestionsPromise
          @displaySuggestions(suggestions, options)

  # providerSuggestions - array of arrays of suggestions provided by all called providers
  mergeSuggestionsFromProviders: (providerSuggestions) ->
    providerSuggestions.reduce (suggestions, providerSuggestions) ->
      suggestions = suggestions.concat(providerSuggestions) if providerSuggestions?.length
      suggestions
    , []

  displaySuggestions: (suggestions, options) =>
    suggestions = _.uniq(suggestions, (s) -> s.text)
    if @shouldDisplaySuggestions and suggestions.length
      @showSuggestionList(suggestions)
    else
      @hideSuggestionList()

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
    return unless @editor? and match? and not @disposed

    match.onWillConfirm?()

    @editor.getSelections()?.forEach((selection) -> selection?.clear())
    @hideSuggestionList()

    @replaceTextWithMatch(match)

    # FIXME: move this to the snippet provider's onDidInsertSuggestion() method
    # when the API has been updated.
    if match.isSnippet
      setTimeout =>
        atom.commands.dispatch(atom.views.getView(@editor), 'snippets:expand')
      , 1

    match.onDidConfirm?()

  showSuggestionList: (suggestions) ->
    return if @disposed
    @suggestionList.changeItems(suggestions)
    @suggestionList.show(@editor)

  hideSuggestionList: =>
    return if @disposed
    @suggestionList.hide()
    @shouldDisplaySuggestions = false

  requestHideSuggestionList: (command) ->
    @hideTimeout = setTimeout(@hideSuggestionList, 0)
    @shouldDisplaySuggestions = false

  cancelHideSuggestionListRequest: ->
    clearTimeout(@hideTimeout)

  # Private: Replaces the current prefix with the given match.
  #
  # match - The match to replace the current prefix with
  replaceTextWithMatch: (match) =>
    return unless @editor?
    newSelectedBufferRanges = []

    selections = @editor.getSelections()
    return unless selections?
    @editor.transact =>
      if match.replacementPrefix?.length > 0
        @editor.selectLeft(match.replacementPrefix.length)
        @editor.delete()

      if match.snippet? and @snippetsManager?
        @snippetsManager.insertSnippet(match.snippet, @editor)
      else
        @editor.insertText(match.text ? match.snippet)

  # Private: Checks whether the current file is blacklisted.
  #
  # Returns {Boolean} that defines whether the current file is blacklisted
  isCurrentFileBlackListed: =>
    blacklist = atom.config.get('autocomplete-plus.fileBlacklist')?.map((s) -> s.trim())
    return false unless blacklist?.length > 0

    minimatch ?= require('minimatch')
    fileName = path.basename(@buffer.getPath())
    for blacklistGlob in blacklist
      return true if minimatch(fileName, blacklistGlob)

    return false

  # Private: Gets called when the content has been modified
  requestNewSuggestions: =>
    delay = atom.config.get('autocomplete-plus.autoActivationDelay')
    clearTimeout(@delayTimeout)
    delay = @suggestionDelay if @suggestionList.isActive()
    @delayTimeout = setTimeout(@findSuggestions, delay)
    @shouldDisplaySuggestions = true

  cancelNewSuggestionsRequest: ->
    clearTimeout(@delayTimeout)
    @shouldDisplaySuggestions = false

  # Private: Gets called when the cursor has moved. Cancels the autocompletion if
  # the text has not been changed.
  #
  # data - An {Object} containing information on why the cursor has been moved
  cursorMoved: ({textChanged}) =>
    # The delay is a workaround for the backspace case. The way atom implements
    # backspace is to select left 1 char, then delete. This results in a
    # cursorMoved event with textChanged == false. So we delay, and if the
    # bufferChanged handler decides to show suggestions, it will cancel the
    # hideSuggestionList request. If there is no bufferChanged event,
    # suggestionList will be hidden.
    @requestHideSuggestionList() unless textChanged

  # Private: Gets called when the user saves the document. Cancels the
  # autocompletion.
  bufferSaved: =>
    @hideSuggestionList() unless @autosaveEnabled

  # Private: Cancels the autocompletion if the user entered more than one
  # character with a single keystroke. (= pasting)
  #
  # event - The change {Event}
  bufferChanged: ({newText, oldText}) =>
    return if @disposed
    return @hideSuggestionList() if @compositionInProgress
    autoActivationEnabled = atom.config.get('autocomplete-plus.enableAutoActivation')
    wouldAutoActivate = newText.trim().length is 1 or ((@backspaceTriggersAutocomplete or @suggestionList.isActive()) and oldText.trim().length is 1)

    if autoActivationEnabled and wouldAutoActivate
      @cancelHideSuggestionListRequest()
      @requestNewSuggestions()
    else
      @cancelNewSuggestionsRequest()
      @hideSuggestionList()

  # Public: Clean up, stop listening to events
  dispose: =>
    @hideSuggestionList()
    @disposed = true
    @ready = false
    @editorSubscriptions?.dispose()
    @editorSubscriptions = null
    @subscriptions?.dispose()
    @subscriptions = null
    @suggestionList = null
    @providerManager = null
