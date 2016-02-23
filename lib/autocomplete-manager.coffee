{Point, Range, CompositeDisposable, Disposable}  = require 'atom'
path = require 'path'
semver = require 'semver'
fuzzaldrin = require 'fuzzaldrin'
fuzzaldrinPlus = require 'fuzzaldrin-plus'

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
        letters = 'A-Za-z\\xAA\\xB5\\xBA\\xC0-\\xD6\\xD8-\\xF6\\xF8-\\u02C1\\u02C6-\\u02D1\\u02E0-\\u02E4\\u02EC\\u02EE\\u0370-\\u0374\\u0376\\u0377\\u037A-\\u037D\\u037F\\u0386\\u0388-\\u038A\\u038C\\u038E-\\u03A1\\u03A3-\\u03F5\\u03F7-\\u0481\\u048A-\\u052F\\u0531-\\u0556\\u0559\\u0561-\\u0587\\u05D0-\\u05EA\\u05F0-\\u05F2\\u0620-\\u064A\\u066E\\u066F\\u0671-\\u06D3\\u06D5\\u06E5\\u06E6\\u06EE\\u06EF\\u06FA-\\u06FC\\u06FF\\u0710\\u0712-\\u072F\\u074D-\\u07A5\\u07B1\\u07CA-\\u07EA\\u07F4\\u07F5\\u07FA\\u0800-\\u0815\\u081A\\u0824\\u0828\\u0840-\\u0858\\u08A0-\\u08B4\\u0904-\\u0939\\u093D\\u0950\\u0958-\\u0961\\u0971-\\u0980\\u0985-\\u098C\\u098F\\u0990\\u0993-\\u09A8\\u09AA-\\u09B0\\u09B2\\u09B6-\\u09B9\\u09BD\\u09CE\\u09DC\\u09DD\\u09DF-\\u09E1\\u09F0\\u09F1\\u0A05-\\u0A0A\\u0A0F\\u0A10\\u0A13-\\u0A28\\u0A2A-\\u0A30\\u0A32\\u0A33\\u0A35\\u0A36\\u0A38\\u0A39\\u0A59-\\u0A5C\\u0A5E\\u0A72-\\u0A74\\u0A85-\\u0A8D\\u0A8F-\\u0A91\\u0A93-\\u0AA8\\u0AAA-\\u0AB0\\u0AB2\\u0AB3\\u0AB5-\\u0AB9\\u0ABD\\u0AD0\\u0AE0\\u0AE1\\u0AF9\\u0B05-\\u0B0C\\u0B0F\\u0B10\\u0B13-\\u0B28\\u0B2A-\\u0B30\\u0B32\\u0B33\\u0B35-\\u0B39\\u0B3D\\u0B5C\\u0B5D\\u0B5F-\\u0B61\\u0B71\\u0B83\\u0B85-\\u0B8A\\u0B8E-\\u0B90\\u0B92-\\u0B95\\u0B99\\u0B9A\\u0B9C\\u0B9E\\u0B9F\\u0BA3\\u0BA4\\u0BA8-\\u0BAA\\u0BAE-\\u0BB9\\u0BD0\\u0C05-\\u0C0C\\u0C0E-\\u0C10\\u0C12-\\u0C28\\u0C2A-\\u0C39\\u0C3D\\u0C58-\\u0C5A\\u0C60\\u0C61\\u0C85-\\u0C8C\\u0C8E-\\u0C90\\u0C92-\\u0CA8\\u0CAA-\\u0CB3\\u0CB5-\\u0CB9\\u0CBD\\u0CDE\\u0CE0\\u0CE1\\u0CF1\\u0CF2\\u0D05-\\u0D0C\\u0D0E-\\u0D10\\u0D12-\\u0D3A\\u0D3D\\u0D4E\\u0D5F-\\u0D61\\u0D7A-\\u0D7F\\u0D85-\\u0D96\\u0D9A-\\u0DB1\\u0DB3-\\u0DBB\\u0DBD\\u0DC0-\\u0DC6\\u0E01-\\u0E30\\u0E32\\u0E33\\u0E40-\\u0E46\\u0E81\\u0E82\\u0E84\\u0E87\\u0E88\\u0E8A\\u0E8D\\u0E94-\\u0E97\\u0E99-\\u0E9F\\u0EA1-\\u0EA3\\u0EA5\\u0EA7\\u0EAA\\u0EAB\\u0EAD-\\u0EB0\\u0EB2\\u0EB3\\u0EBD\\u0EC0-\\u0EC4\\u0EC6\\u0EDC-\\u0EDF\\u0F00\\u0F40-\\u0F47\\u0F49-\\u0F6C\\u0F88-\\u0F8C\\u1000-\\u102A\\u103F\\u1050-\\u1055\\u105A-\\u105D\\u1061\\u1065\\u1066\\u106E-\\u1070\\u1075-\\u1081\\u108E\\u10A0-\\u10C5\\u10C7\\u10CD\\u10D0-\\u10FA\\u10FC-\\u1248\\u124A-\\u124D\\u1250-\\u1256\\u1258\\u125A-\\u125D\\u1260-\\u1288\\u128A-\\u128D\\u1290-\\u12B0\\u12B2-\\u12B5\\u12B8-\\u12BE\\u12C0\\u12C2-\\u12C5\\u12C8-\\u12D6\\u12D8-\\u1310\\u1312-\\u1315\\u1318-\\u135A\\u1380-\\u138F\\u13A0-\\u13F5\\u13F8-\\u13FD\\u1401-\\u166C\\u166F-\\u167F\\u1681-\\u169A\\u16A0-\\u16EA\\u16F1-\\u16F8\\u1700-\\u170C\\u170E-\\u1711\\u1720-\\u1731\\u1740-\\u1751\\u1760-\\u176C\\u176E-\\u1770\\u1780-\\u17B3\\u17D7\\u17DC\\u1820-\\u1877\\u1880-\\u18A8\\u18AA\\u18B0-\\u18F5\\u1900-\\u191E\\u1950-\\u196D\\u1970-\\u1974\\u1980-\\u19AB\\u19B0-\\u19C9\\u1A00-\\u1A16\\u1A20-\\u1A54\\u1AA7\\u1B05-\\u1B33\\u1B45-\\u1B4B\\u1B83-\\u1BA0\\u1BAE\\u1BAF\\u1BBA-\\u1BE5\\u1C00-\\u1C23\\u1C4D-\\u1C4F\\u1C5A-\\u1C7D\\u1CE9-\\u1CEC\\u1CEE-\\u1CF1\\u1CF5\\u1CF6\\u1D00-\\u1DBF\\u1E00-\\u1F15\\u1F18-\\u1F1D\\u1F20-\\u1F45\\u1F48-\\u1F4D\\u1F50-\\u1F57\\u1F59\\u1F5B\\u1F5D\\u1F5F-\\u1F7D\\u1F80-\\u1FB4\\u1FB6-\\u1FBC\\u1FBE\\u1FC2-\\u1FC4\\u1FC6-\\u1FCC\\u1FD0-\\u1FD3\\u1FD6-\\u1FDB\\u1FE0-\\u1FEC\\u1FF2-\\u1FF4\\u1FF6-\\u1FFC\\u2071\\u207F\\u2090-\\u209C\\u2102\\u2107\\u210A-\\u2113\\u2115\\u2119-\\u211D\\u2124\\u2126\\u2128\\u212A-\\u212D\\u212F-\\u2139\\u213C-\\u213F\\u2145-\\u2149\\u214E\\u2183\\u2184\\u2C00-\\u2C2E\\u2C30-\\u2C5E\\u2C60-\\u2CE4\\u2CEB-\\u2CEE\\u2CF2\\u2CF3\\u2D00-\\u2D25\\u2D27\\u2D2D\\u2D30-\\u2D67\\u2D6F\\u2D80-\\u2D96\\u2DA0-\\u2DA6\\u2DA8-\\u2DAE\\u2DB0-\\u2DB6\\u2DB8-\\u2DBE\\u2DC0-\\u2DC6\\u2DC8-\\u2DCE\\u2DD0-\\u2DD6\\u2DD8-\\u2DDE\\u2E2F\\u3005\\u3006\\u3031-\\u3035\\u303B\\u303C\\u3041-\\u3096\\u309D-\\u309F\\u30A1-\\u30FA\\u30FC-\\u30FF\\u3105-\\u312D\\u3131-\\u318E\\u31A0-\\u31BA\\u31F0-\\u31FF\\u3400-\\u4DB5\\u4E00-\\u9FD5\\uA000-\\uA48C\\uA4D0-\\uA4FD\\uA500-\\uA60C\\uA610-\\uA61F\\uA62A\\uA62B\\uA640-\\uA66E\\uA67F-\\uA69D\\uA6A0-\\uA6E5\\uA717-\\uA71F\\uA722-\\uA788\\uA78B-\\uA7AD\\uA7B0-\\uA7B7\\uA7F7-\\uA801\\uA803-\\uA805\\uA807-\\uA80A\\uA80C-\\uA822\\uA840-\\uA873\\uA882-\\uA8B3\\uA8F2-\\uA8F7\\uA8FB\\uA8FD\\uA90A-\\uA925\\uA930-\\uA946\\uA960-\\uA97C\\uA984-\\uA9B2\\uA9CF\\uA9E0-\\uA9E4\\uA9E6-\\uA9EF\\uA9FA-\\uA9FE\\uAA00-\\uAA28\\uAA40-\\uAA42\\uAA44-\\uAA4B\\uAA60-\\uAA76\\uAA7A\\uAA7E-\\uAAAF\\uAAB1\\uAAB5\\uAAB6\\uAAB9-\\uAABD\\uAAC0\\uAAC2\\uAADB-\\uAADD\\uAAE0-\\uAAEA\\uAAF2-\\uAAF4\\uAB01-\\uAB06\\uAB09-\\uAB0E\\uAB11-\\uAB16\\uAB20-\\uAB26\\uAB28-\\uAB2E\\uAB30-\\uAB5A\\uAB5C-\\uAB65\\uAB70-\\uABE2\\uAC00-\\uD7A3\\uD7B0-\\uD7C6\\uD7CB-\\uD7FB\\uF900-\\uFA6D\\uFA70-\\uFAD9\\uFB00-\\uFB06\\uFB13-\\uFB17\\uFB1D\\uFB1F-\\uFB28\\uFB2A-\\uFB36\\uFB38-\\uFB3C\\uFB3E\\uFB40\\uFB41\\uFB43\\uFB44\\uFB46-\\uFBB1\\uFBD3-\\uFD3D\\uFD50-\\uFD8F\\uFD92-\\uFDC7\\uFDF0-\\uFDFB\\uFE70-\\uFE74\\uFE76-\\uFEFC\\uFF21-\\uFF3A\\uFF41-\\uFF5A\\uFF66-\\uFFBE\\uFFC2-\\uFFC7\\uFFCA-\\uFFCF\\uFFD2-\\uFFD7\\uFFDA-\\uFFDC'
        @prefixRegex = RegExp "(['\"~`!@#\\$%^&*\\(\\)\\{\\}\\[\\]=\+,/\\?>])?(([#{letters}\\d_]+[#{letters}\\d_-]*)|([.:;[{(< ]+))$"
        @wordPrefixRegex = RegExp "^[#{letters}\\d_]+[#{letters}\\d_-]*$"
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

  updateCurrentEditor: (currentPaneItem) =>
    return if not currentPaneItem? or currentPaneItem is @editor

    @editorSubscriptions?.dispose()
    @editorSubscriptions = null

    # Stop tracking editor + buffer
    @editor = null
    @editorView = null
    @buffer = null
    @isCurrentFileBlackListedCache = null

    return unless @paneItemIsValid(currentPaneItem)

    # Track the new editor, editorView, and buffer
    @editor = currentPaneItem
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

  paneItemIsValid: (paneItem) ->
    # TODO: remove conditional when `isTextEditor` is shipped.
    if typeof atom.workspace.isTextEditor is "function"
      atom.workspace.isTextEditor(paneItem)
    else
      return false unless paneItem?
      # Should we disqualify TextEditors with the Grammar text.plain.null-grammar?
      paneItem.getText?

  handleEvents: =>
    # Track the current pane item, update current editor
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
    fileName = path.basename(@buffer.getPath())
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
