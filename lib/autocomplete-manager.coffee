{Point, Range, CompositeDisposable, Disposable}  = require 'atom'
path = require 'path'
semver = require 'semver'
fuzzaldrin = require 'fuzzaldrin'
fuzzaldrinPlus = require 'fuzzaldrin-plus'

ProviderManager = require './provider-manager'
SuggestionList = require './suggestion-list'
SuggestionListElement = require './suggestion-list-element'
{UnicodeLetters} = require './unicode-helpers'

# Deferred requires
minimatch = null
grim = null

module.exports =
class AutocompleteManager
  autosaveEnabled: false
  backspaceTriggersAutocomplete: true
  autoConfirmSingleSuggestionEnabled: true
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
  prefixRegex: null
  wordPrefixRegex: null

  constructor: ->
    @subscriptions = new CompositeDisposable
    @providerManager = new ProviderManager
    @suggestionList = new SuggestionList

    @subscriptions.add(atom.config.observe('autocomplete-plus.enableExtendedUnicodeSupport', (enableExtendedUnicodeSupport) =>
      if enableExtendedUnicodeSupport
        @prefixRegex = new RegExp("(['\"~`!@#\\$%^&*\\(\\)\\{\\}\\[\\]=\+,/\\?>])?(([#{UnicodeLetters}\\d_]+[#{UnicodeLetters}\\d_-]*)|([.:;[{(< ]+))$")
        @wordPrefixRegex = new RegExp("^[#{UnicodeLetters}\\d_]+[#{UnicodeLetters}\\d_-]*$")
      else
        @prefixRegex = /(\b|['"~`!@#\$%^&*\(\)\{\}\[\]=\+,/\?>])((\w+[\w-]*)|([.:;[{(< ]+))$/
        @wordPrefixRegex = /^\w+[\w-]*$/
    ))
    @subscriptions.add(@providerManager)
    @subscriptions.add atom.views.addViewProvider SuggestionList, (model) ->
      new SuggestionListElement().initialize(model)

    @handleEvents()
    @handleCommands()
    @subscriptions.add(@suggestionList) # We're adding this last so it is disposed after events
    @ready = true

  setSnippetsManager: (@snippetsManager) ->

  updateCurrentEditor: (currentEditor) =>
    return if not currentEditor? or currentEditor is @editor

    @editorSubscriptions?.dispose()
    @editorSubscriptions = null

    # Stop tracking editor + buffer
    @editor = null
    @editorView = null
    @buffer = null
    @isCurrentFileBlackListedCache = null

    return unless @editorIsValid(currentEditor)

    # Track the new editor, editorView, and buffer
    @editor = currentEditor
    @editorView = atom.views.getView(@editor)
    @buffer = @editor.getBuffer()

    @editorSubscriptions = new CompositeDisposable

    # Subscribe to buffer events:
    @editorSubscriptions.add(@buffer.onDidSave(@bufferSaved))
    if typeof @buffer.onDidChangeText is "function"
      @editorSubscriptions.add(@buffer.onDidChange(@toggleActivationForBufferChange))
      @editorSubscriptions.add(@buffer.onDidChangeText(@showOrHideSuggestionListForBufferChanges))
    else
      # TODO: Remove this after `TextBuffer.prototype.onDidChangeText` lands on Atom stable.
      @editorSubscriptions.add(@buffer.onDidChange(@showOrHideSuggestionListForBufferChange))

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
    @editorSubscriptions.add @editor.onDidChangePath =>
      @isCurrentFileBlackListedCache = null

  editorIsValid: (editor) ->
    # TODO: remove conditional when `isTextEditor` is shipped.
    if typeof atom.workspace.isTextEditor is "function"
      atom.workspace.isTextEditor(editor)
    else
      return false unless editor?
      # Should we disqualify TextEditors with the Grammar text.plain.null-grammar?
      editor.getText?

  handleEvents: =>
    # Observe `TextEditors` in the `TextEditorRegistry` and listen for focus,
    # or observe active `Pane` items respectively.
    # TODO: remove conditional when `TextEditorRegistry` is shipped.
    if atom.textEditors?
      @subscriptions.add(atom.textEditors.observe (editor) =>
        view = atom.views.getView(editor)
        if view is document.activeElement
          @updateCurrentEditor(editor)
        view.addEventListener 'focus', (element) =>
          @updateCurrentEditor(editor))
    else
      @subscriptions.add(atom.workspace.observeActivePaneItem(@updateCurrentEditor))

    # Watch config values
    @subscriptions.add(atom.config.observe('autosave.enabled', (value) => @autosaveEnabled = value))
    @subscriptions.add(atom.config.observe('autocomplete-plus.backspaceTriggersAutocomplete', (value) => @backspaceTriggersAutocomplete = value))
    @subscriptions.add(atom.config.observe('autocomplete-plus.enableAutoActivation', (value) => @autoActivationEnabled = value))
    @subscriptions.add(atom.config.observe('autocomplete-plus.enableAutoConfirmSingleSuggestion', (value) => @autoConfirmSingleSuggestionEnabled = value))
    @subscriptions.add(atom.config.observe('autocomplete-plus.consumeSuffix', (value) => @consumeSuffix = value))
    @subscriptions.add(atom.config.observe('autocomplete-plus.useAlternateScoring', (value) => @useAlternateScoring = value ))
    @subscriptions.add atom.config.observe 'autocomplete-plus.fileBlacklist', (value) =>
      @fileBlacklist = value?.map((s) -> s.trim())
      @isCurrentFileBlackListedCache = null
    @subscriptions.add atom.config.observe 'autocomplete-plus.suppressActivationForEditorClasses', (value) =>
      @suppressForClasses = []
      for selector in value
        classes = (className.trim() for className in selector.trim().split('.') when className.trim())
        @suppressForClasses.push(classes) if classes.length
      return

    # Handle events from suggestion list
    @subscriptions.add(@suggestionList.onDidConfirm(@confirm))
    @subscriptions.add(@suggestionList.onDidCancel(@hideSuggestionList))

  handleCommands: =>
    @subscriptions.add atom.commands.add 'atom-text-editor',
      'autocomplete-plus:activate': (event) =>
        @shouldDisplaySuggestions = true
        @findSuggestions(event.detail?.activatedManually ? true)

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

    @getSuggestionsFromProviders({@editor, bufferPosition, scopeDescriptor, prefix, activatedManually})

  getSuggestionsFromProviders: (options) =>
    providers = @providerManager.applicableProviders(options.editor, options.scopeDescriptor)

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
        upgradedOptions =
          editor: options.editor
          prefix: options.prefix
          bufferPosition: options.bufferPosition
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
              type: suggestion.type
            newSuggestion.rightLabelHTML = suggestion.label if not newSuggestion.rightLabelHTML? and suggestion.renderLabelAsHtml
            newSuggestion.rightLabel = suggestion.label if not newSuggestion.rightLabel? and not suggestion.renderLabelAsHtml
            newSuggestion

        hasEmpty = false # Optimization: only create another array when there are empty items
        for suggestion in providerSuggestions
          hasEmpty = true unless suggestion.snippet or suggestion.text
          suggestion.replacementPrefix ?= @getDefaultReplacementPrefix(options.prefix)
          suggestion.provider = provider

        providerSuggestions = (suggestion for suggestion in providerSuggestions when (suggestion.snippet or suggestion.text)) if hasEmpty
        providerSuggestions = @filterSuggestions(providerSuggestions, options) if provider.filterSuggestions
        providerSuggestions

    return unless providerPromises?.length
    @currentSuggestionsPromise = suggestionsPromise = Promise.all(providerPromises)
      .then(@mergeSuggestionsFromProviders)
      .then (suggestions) =>
        return unless @currentSuggestionsPromise is suggestionsPromise
        if options.activatedManually and @shouldDisplaySuggestions and @autoConfirmSingleSuggestionEnabled and suggestions.length is 1
          # When there is one suggestion in manual mode, just confirm it
          @confirm(suggestions[0])
        else
          @displaySuggestions(suggestions, options)

  filterSuggestions: (suggestions, {prefix}) ->
    results = []
    fuzzaldrinProvider = if @useAlternateScoring then fuzzaldrinPlus else fuzzaldrin
    for suggestion, i in suggestions
      # sortScore mostly preserves in the original sorting. The function is
      # chosen such that suggestions with a very high match score can break out.
      suggestion.sortScore = Math.max(-i / 10 + 3, 0) + 1
      suggestion.score = null

      text = (suggestion.snippet or suggestion.text)
      suggestionPrefix = suggestion.replacementPrefix ? prefix
      prefixIsEmpty = not suggestionPrefix or suggestionPrefix is ' '
      firstCharIsMatch = not prefixIsEmpty and suggestionPrefix[0].toLowerCase() is text[0].toLowerCase()

      if prefixIsEmpty
        results.push(suggestion)
      if firstCharIsMatch and (score = fuzzaldrinProvider.score(text, suggestionPrefix)) > 0
        suggestion.score = score * suggestion.sortScore
        results.push(suggestion)

    results.sort(@reverseSortOnScoreComparator)
    results

  reverseSortOnScoreComparator: (a, b) ->
    (b.score ? b.sortScore) - (a.score ? a.sortScore)

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
        See https://github.com/atom/autocomplete-plus/wiki/Provider-API
      """
    if suggestion.prefix?
      hasDeprecations = true
      grim ?= require 'grim'
      grim.deprecate """
        Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
        returns suggestions with a `prefix` attribute.
        The `prefix` attribute is now `replacementPrefix` and is optional.
        See https://github.com/atom/autocomplete-plus/wiki/Provider-API
      """
    if suggestion.label?
      hasDeprecations = true
      grim ?= require 'grim'
      grim.deprecate """
        Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
        returns suggestions with a `label` attribute.
        The `label` attribute is now `rightLabel` or `rightLabelHTML`.
        See https://github.com/atom/autocomplete-plus/wiki/Provider-API
      """
    if suggestion.onWillConfirm?
      hasDeprecations = true
      grim ?= require 'grim'
      grim.deprecate """
        Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
        returns suggestions with a `onWillConfirm` callback.
        The `onWillConfirm` callback is no longer supported.
        See https://github.com/atom/autocomplete-plus/wiki/Provider-API
      """
    if suggestion.onDidConfirm?
      hasDeprecations = true
      grim ?= require 'grim'
      grim.deprecate """
        Autocomplete provider '#{provider.constructor.name}(#{provider.id})'
        returns suggestions with a `onDidConfirm` callback.
        The `onDidConfirm` callback is now a `onDidInsertSuggestion` callback on the provider itself.
        See https://github.com/atom/autocomplete-plus/wiki/Provider-API
      """
    hasDeprecations

  displaySuggestions: (suggestions, options) =>
    suggestions = @getUniqueSuggestions(suggestions)

    if @shouldDisplaySuggestions and suggestions.length
      @showSuggestionList(suggestions, options)
    else
      @hideSuggestionList()

  getUniqueSuggestions: (suggestions) ->
    seen = {}
    result = []
    for suggestion in suggestions
      val = suggestion.text + suggestion.snippet
      unless seen[val]
        result.push(suggestion)
        seen[val] = true
    result

  getPrefix: (editor, bufferPosition) ->
    line = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
    @prefixRegex.exec(line)?[2] or ''

  getDefaultReplacementPrefix: (prefix) ->
    if @wordPrefixRegex.test(prefix)
      prefix
    else
      ''

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

  showSuggestionList: (suggestions, options) ->
    return if @disposed
    @suggestionList.changeItems(suggestions)
    @suggestionList.show(@editor, options)

  hideSuggestionList: =>
    return if @disposed
    @suggestionList.changeItems(null)
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
          suffix = if @consumeSuffix then @getSuffix(@editor, endPosition, suggestion) else ''
          cursor.moveRight(suffix.length) if suffix.length
          cursor.selection.selectLeft(suggestion.replacementPrefix.length + suffix.length)

          if suggestion.snippet? and @snippetsManager?
            @snippetsManager.insertSnippet(suggestion.snippet, @editor, cursor)
          else
            cursor.selection.insertText(suggestion.text ? suggestion.snippet, {
              autoIndentNewline: @editor.shouldAutoIndent(),
              autoDecreaseIndent: @editor.shouldAutoIndent(),
            })
      return

  getSuffix: (editor, bufferPosition, suggestion) ->
    # This just chews through the suggestion and tries to match the suggestion
    # substring with the lineText starting at the cursor. There is probably a
    # more efficient way to do this.
    suffix = (suggestion.snippet ? suggestion.text)
    endPosition = [bufferPosition.row, bufferPosition.column + suffix.length]
    endOfLineText = editor.getTextInBufferRange([bufferPosition, endPosition])
    nonWordCharacters = new Set(atom.config.get('editor.nonWordCharacters').split(''))
    while suffix
      break if endOfLineText.startsWith(suffix) and not nonWordCharacters.has(suffix[0])
      suffix = suffix.slice(1)
    suffix

  # Private: Checks whether the current file is blacklisted.
  #
  # Returns {Boolean} that defines whether the current file is blacklisted
  isCurrentFileBlackListed: =>
    # minimatch is slow. Not necessary to do this computation on every request for suggestions
    return @isCurrentFileBlackListedCache if @isCurrentFileBlackListedCache?

    if not @fileBlacklist? or @fileBlacklist.length is 0
      @isCurrentFileBlackListedCache = false
      return @isCurrentFileBlackListedCache

    minimatch ?= require('minimatch')
    fullpath = @buffer.getPath()
    if not fullpath
      return false
    fileName = path.basename(fullpath)
    for blacklistGlob in @fileBlacklist
      if minimatch(fileName, blacklistGlob)
        @isCurrentFileBlackListedCache = true
        return @isCurrentFileBlackListedCache

    @isCurrentFileBlackListedCache = false

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
    @requestHideSuggestionList() unless textChanged or @shouldActivate

  # Private: Gets called when the user saves the document. Cancels the
  # autocompletion.
  bufferSaved: =>
    @hideSuggestionList() unless @autosaveEnabled

  toggleActivationForBufferChange: ({newText, newRange, oldText, oldRange}) =>
    return if @disposed
    return if @shouldActivate
    return @hideSuggestionList() if @compositionInProgress

    if @autoActivationEnabled or @suggestionList.isActive()
      # Activate on space, a non-whitespace character, or a bracket-matcher pair.
      if newText.length > 0
        @shouldActivate = (newText is ' ' or newText.trim().length is 1 or newText in @bracketMatcherPairs)

      # Suggestion list must be either active or backspaceTriggersAutocomplete must be true for activation to occur.
      # Activate on removal of a space, a non-whitespace character, or a bracket-matcher pair.
      else if oldText.length > 0
        @shouldActivate =
          (@backspaceTriggersAutocomplete or @suggestionList.isActive()) and
          (oldText is ' ' or oldText.trim().length is 1 or oldText in @bracketMatcherPairs)

      @shouldActivate = false if @shouldActivate and @shouldSuppressActivationForEditorClasses()

  showOrHideSuggestionListForBufferChanges: ({changes}) =>
    lastCursorPosition = @editor.getLastCursor().getBufferPosition()
    changeOccurredNearLastCursor = changes.some ({start, newExtent}) ->
      newRange = new Range(start, start.traverse(newExtent))
      newRange.containsPoint(lastCursorPosition)

    if @shouldActivate and changeOccurredNearLastCursor
      @cancelHideSuggestionListRequest()
      @requestNewSuggestions()
    else
      @cancelNewSuggestionsRequest()
      @hideSuggestionList()

    @shouldActivate = false

  showOrHideSuggestionListForBufferChange: ({newText, newRange, oldText, oldRange}) =>
    return if @disposed
    return @hideSuggestionList() if @compositionInProgress
    shouldActivate = false
    cursorPositions = @editor.getCursorBufferPositions()

    if @autoActivationEnabled or @suggestionList.isActive()

      # Activate on space, a non-whitespace character, or a bracket-matcher pair.
      if newText.length > 0
        shouldActivate =
          (cursorPositions.some (position) -> newRange.containsPoint(position)) and
          (newText is ' ' or newText.trim().length is 1 or newText in @bracketMatcherPairs)

      # Suggestion list must be either active or backspaceTriggersAutocomplete must be true for activation to occur.
      # Activate on removal of a space, a non-whitespace character, or a bracket-matcher pair.
      else if oldText.length > 0
        shouldActivate =
          (@backspaceTriggersAutocomplete or @suggestionList.isActive()) and
          (cursorPositions.some (position) -> newRange.containsPoint(position)) and
          (oldText is ' ' or oldText.trim().length is 1 or oldText in @bracketMatcherPairs)

      shouldActivate = false if shouldActivate and @shouldSuppressActivationForEditorClasses()

    if shouldActivate
      @cancelHideSuggestionListRequest()
      @requestNewSuggestions()
    else
      @cancelNewSuggestionsRequest()
      @hideSuggestionList()

  shouldSuppressActivationForEditorClasses: ->
    for classNames in @suppressForClasses
      containsCount = 0
      for className in classNames
        containsCount += 1 if @editorView.classList.contains(className)
      return true if containsCount is classNames.length
    false

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
