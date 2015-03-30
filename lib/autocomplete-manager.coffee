{Range, TextEditor, CompositeDisposable, Disposable}  = require 'atom'
_ = require 'underscore-plus'
path = require 'path'
semver = require 'semver'

ProviderManager = require './provider-manager'
SuggestionList = require './suggestion-list'
SuggestionListElement = require './suggestion-list-element'

# Deferred requires
minimatch = null
grim = null

module.exports =
class AutocompleteManager
  autosaveEnabled: false
  backspaceTriggersAutocomplete: true
  bracketMatcherPairs: ['()', '[]', '{}', '""', "''", '``', "“”", '‘’', "«»", "‹›"]
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
  suppressForClasses: []
  shouldDisplaySuggestions: false
  manualActivationStrictPrefixes: null
  prefixRegex:/\b((\w+[\w-]*)|([.:;[{(< ]+))$/g

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
    @subscriptions.add(atom.config.observe('autocomplete-plus.enableAutoActivation', (value) => @autoActivationEnabled = value))
    @subscriptions.add atom.config.observe 'autocomplete-plus.suppressActivationForEditorClasses', (value) =>
      @suppressForClasses = _.chain(value).map((classNames) -> classNames?.trim().split('.').map((className) -> className?.trim())).compact().value()

    # Handle events from suggestion list
    @subscriptions.add(@suggestionList.onDidConfirm(@confirm))
    @subscriptions.add(@suggestionList.onDidCancel(@hideSuggestionList))

  handleCommands: =>
    @subscriptions.add atom.commands.add 'atom-text-editor',
      'autocomplete-plus:activate': =>
        @shouldDisplaySuggestions = true
        @findSuggestions(true)

  # Private: Finds suggestions for the current prefix, sets the list items,
  # positions the overlay and shows it
  findSuggestions: (activatedManually) =>
    return if @disposed
    return unless @providerManager? and @editor? and @buffer?
    return if @isCurrentFileBlackListed()
    cursor = @editor.getLastCursor()
    return unless cursor?

    bufferPosition = cursor.getBufferPosition()
    scopeDescriptor = cursor.getScopeDescriptor()
    prefix = @getPrefix(@editor, bufferPosition)

    @getSuggestionsFromProviders({@editor, bufferPosition, scopeDescriptor, prefix}, activatedManually)

  getSuggestionsFromProviders: (options, activatedManually) =>
    providers = @providerManager.providersForScopeDescriptor(options.scopeDescriptor)

    providerPromises = []
    providers.forEach (provider) =>
      apiVersion = @providerManager.apiVersionForProvider(provider)
      apiIs20 = semver.satisfies(apiVersion, '>=2.0.0')

      # TODO API: remove upgrading when 1.0 support is removed
      if apiIs20
        getSuggestions = provider.getSuggestions.bind(provider)
        upgradedOptions = options
      else
        getSuggestions = provider.requestHandler.bind(provider)
        upgradedOptions = _.extend {}, options,
          position: options.bufferPosition
          scope: options.scopeDescriptor
          scopeChain: options.scopeDescriptor.getScopeChain()
          buffer: options.editor.getBuffer()
          cursor: options.editor.getLastCursor()

      providerPromises.push Promise.resolve(getSuggestions(upgradedOptions)).then (providerSuggestions) =>
        return unless providerSuggestions?

        # TODO API: remove upgrading when 1.0 support is removed
        hasDeprecations = false
        if apiIs20 and providerSuggestions.length
          hasDeprecations = @deprecateForSuggestion(provider, providerSuggestions[0])

        if hasDeprecations or not apiIs20
          providerSuggestions = providerSuggestions.map (suggestion) ->
            newSuggestion =
              text: suggestion.text ? suggestion.word
              snippet: suggestion.snippet
              replacementPrefix: suggestion.replacementPrefix ? suggestion.prefix
              className: suggestion.className
            newSuggestion.rightLabelHTML = suggestion.label if not newSuggestion.rightLabelHTML? and suggestion.renderLabelAsHtml
            newSuggestion.rightLabel = suggestion.label if not newSuggestion.rightLabel? and not suggestion.renderLabelAsHtml
            newSuggestion

        # FIXME: Cycling through the suggestions again is not ideal :/
        for suggestion in providerSuggestions
          suggestion.replacementPrefix ?= options.prefix
          suggestion.provider = provider
          @addManualActivationStrictPrefix(provider, suggestion.replacementPrefix) if activatedManually

        providerSuggestions

    return unless providerPromises?.length
    @currentSuggestionsPromise = suggestionsPromise = Promise.all(providerPromises)
      .then(@mergeSuggestionsFromProviders)
      .then (suggestions) =>
        return unless @currentSuggestionsPromise is suggestionsPromise
        suggestions = @filterForManualActivationStrictPrefix(suggestions)
        if activatedManually and @shouldDisplaySuggestions and suggestions.length is 1
          # When there is one suggestion in manual mode, just confirm it
          @confirm(suggestions[0])
        else
          @displaySuggestions(suggestions, options)

  # providerSuggestions - array of arrays of suggestions provided by all called providers
  mergeSuggestionsFromProviders: (providerSuggestions) ->
    providerSuggestions.reduce (suggestions, providerSuggestions) ->
      suggestions = suggestions.concat(providerSuggestions) if providerSuggestions?.length
      suggestions
    , []

  deprecateForSuggestion: (provider, suggestion) ->
    hasDeprecations = false
    if suggestion.word?
      hasDeprecations = true
      grim ?= require 'grim'
      grim.deprecate """
        Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
        returns suggestions with a `word` attribute.
        The `word` attribute is now `text`.
        See https://github.com/atom-community/autocomplete-plus/wiki/Provider-API
      """
    if suggestion.prefix?
      hasDeprecations = true
      grim ?= require 'grim'
      grim.deprecate """
        Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
        returns suggestions with a `prefix` attribute.
        The `prefix` attribute is now `replacementPrefix` and is optional.
        See https://github.com/atom-community/autocomplete-plus/wiki/Provider-API
      """
    if suggestion.label?
      hasDeprecations = true
      grim ?= require 'grim'
      grim.deprecate """
        Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
        returns suggestions with a `label` attribute.
        The `label` attribute is now `rightLabel` or `rightLabelHTML`.
        See https://github.com/atom-community/autocomplete-plus/wiki/Provider-API
      """
    if suggestion.onWillConfirm?
      hasDeprecations = true
      grim ?= require 'grim'
      grim.deprecate """
        Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
        returns suggestions with a `onWillConfirm` callback.
        The `onWillConfirm` callback is no longer supported.
        See https://github.com/atom-community/autocomplete-plus/wiki/Provider-API
      """
    if suggestion.onDidConfirm?
      hasDeprecations = true
      grim ?= require 'grim'
      grim.deprecate """
        Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
        returns suggestions with a `onDidConfirm` callback.
        The `onDidConfirm` callback is now a `onDidInsertSuggestion` callback on the provider itself.
        See https://github.com/atom-community/autocomplete-plus/wiki/Provider-API
      """
    hasDeprecations

  displaySuggestions: (suggestions, options) =>
    suggestions = _.uniq(suggestions, (s) -> s.text + s.snippet)
    if @shouldDisplaySuggestions and suggestions.length
      @showSuggestionList(suggestions)
    else
      @hideSuggestionList()

  getPrefix: (editor, bufferPosition) ->
    line = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
    line.match(@prefixRegex)?[0] or ''

  # Private: Gets called when the user successfully confirms a suggestion
  #
  # match - An {Object} representing the confirmed suggestion
  confirm: (suggestion) =>
    return unless @editor? and suggestion? and not @disposed

    apiVersion = @providerManager.apiVersionForProvider(suggestion.provider)
    apiIs20 = semver.satisfies(apiVersion, '>=2.0.0')
    triggerPosition = @editor.getLastCursor().getBufferPosition()

    # TODO API: Remove as this is no longer used
    suggestion.onWillConfirm?()

    @editor.getSelections()?.forEach((selection) -> selection?.clear())
    @hideSuggestionList()

    @replaceTextWithMatch(suggestion)

    # TODO API: Remove when we remove the 1.0 API
    if apiIs20
      suggestion.provider.onDidInsertSuggestion?({@editor, suggestion, triggerPosition})
    else
      suggestion.onDidConfirm?()

  showSuggestionList: (suggestions) ->
    return if @disposed
    @suggestionList.changeItems(suggestions)
    @suggestionList.show(@editor)

  hideSuggestionList: =>
    return if @disposed
    @clearManualActivationStrictPrefixes()
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
  replaceTextWithMatch: (suggestion) =>
    return unless @editor?
    newSelectedBufferRanges = []

    cursors = @editor.getCursors()
    return unless cursors?

    @editor.transact =>
      for cursor in cursors
        endPosition = cursor.getBufferPosition()
        beginningPosition = [endPosition.row, endPosition.column - suggestion.replacementPrefix.length]

        if @editor.getTextInBufferRange([beginningPosition, endPosition]) is suggestion.replacementPrefix
          suffix = @getSuffix(@editor, endPosition, suggestion)
          cursor.moveRight(suffix.length) if suffix.length
          cursor.selection.selectLeft(suggestion.replacementPrefix.length + suffix.length)

          if suggestion.snippet? and @snippetsManager?
            @snippetsManager.insertSnippet(suggestion.snippet, @editor, cursor)
          else
            cursor.selection.insertText(suggestion.text ? suggestion.snippet)
      return

  getSuffix: (editor, bufferPosition, suggestion) ->
    # This just chews through the suggestion and tries to match the suggestion
    # substring with the lineText starting at the cursor. There is probably a
    # more efficient way to do this.
    suffix = (suggestion.snippet ? suggestion.text)
    endPosition = [bufferPosition.row, bufferPosition.column + suffix.length]
    endOfLineText = editor.getTextInBufferRange([bufferPosition, endPosition])
    while suffix
      return suffix if endOfLineText.startsWith(suffix)
      suffix = suffix.slice(1)
    ''

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
    shouldActivate = false

    if @autoActivationEnabled or @suggestionList.isActive()
      if newText?.length
        # Activate on space, a non-whitespace character, or a bracket-matcher pair
        shouldActivate = newText is ' ' or newText.trim().length is 1 or newText in @bracketMatcherPairs
      else if oldText?.length and (@backspaceTriggersAutocomplete or @suggestionList.isActive())
        # Suggestion list must be either active or backspaceTriggersAutocomplete must be true for activation to occur
        # Activate on removal of a space, a non-whitespace character, or a bracket-matcher pair
        shouldActivate = oldText is ' ' or oldText.trim().length is 1 or oldText in @bracketMatcherPairs

      # Suppress activation if the editorView has classes that match the suppression list
      if shouldActivate
        for classNames in @suppressForClasses
          shouldActivate = false if _.intersection(@editorView.classList, classNames)?.length is classNames.length

    if shouldActivate
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

  clearManualActivationStrictPrefixes: ->
    @manualActivationStrictPrefixes = null

  addManualActivationStrictPrefix: (provider, prefix) ->
    return if @manualActivationStrictPrefixes?.has(provider) or not prefix?
    @manualActivationStrictPrefixes ?= new WeakMap
    @manualActivationStrictPrefixes.set(provider, prefix.toLowerCase())

  filterForManualActivationStrictPrefix: (suggestions) ->
    return suggestions unless @manualActivationStrictPrefixes?

    results = []
    for suggestion in suggestions
      lowercaseText = (suggestion.snippet ? suggestion.text).toLowerCase()
      if lowercaseText[0] is suggestion.replacementPrefix.toLowerCase()[0]
        strictPrefix = @manualActivationStrictPrefixes.get(suggestion.provider)
        results.push(suggestion) if strictPrefix? and lowercaseText.startsWith(strictPrefix)
      else
        results.push(suggestion)
    results
