{Range}  = require 'atom'
{CompositeDisposable, Disposable, Emitter} = require 'event-kit'
_ = require 'underscore-plus'
FuzzyProvider = require './fuzzy-provider'
minimatch = require 'minimatch'
path = require 'path'
SuggestionList = require './suggestion-list'
SuggestionListElement = require './suggestion-list-element'
Suggestion = require './suggestion'
Provider = require './provider'

module.exports =
class AutocompleteManager
  editor: null
  editorView: null
  buffer: null
  suggestionList: null
  editorSubscriptions: null

  constructor: ->
    @subscriptions = new CompositeDisposable
    @emitter = new Emitter

    @scopes = {}
    @provideApi()

    # Register Suggestion List Model and View
    @subscriptions.add(atom.views.addViewProvider(SuggestionList, (model) =>
      new SuggestionListElement().initialize(model)
    ))
    @suggestionList = new SuggestionList()

    @handleEvents()
    @handleCommands()
    @fuzzyProvider = new FuzzyProvider()

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
    # TODO: Disqualify invalid pane items
    # ...
    return true

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
    return if @isCurrentFileBlackListed()
    @originalCursorPosition = @editor.getCursorScreenPosition()
    return unless @originalCursorPosition?
    currentScopes = @editor.scopeDescriptorForBufferPosition(@originalCursorPosition)?.scopes
    return unless currentScopes?

    options =
      editor: @editor
      buffer: @buffer
      position: @originalCursorPosition
      scopes: currentScopes
      prefixOfSelection: @prefixOfSelection(@editor.getLastSelection())

    # Iterate over all providers, ask them to build suggestion(s)
    suggestions = []
    for provider in @providersForScopes(options.scopes)
      providerSuggestions = provider?.buildSuggestionsShim(options)
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

  providersForScopes: (scopes) =>
    return [] unless scopes?
    return [] unless @scopes
    providers = []
    for scope in scopes
      if @scopes[scope]?
        providers = _.union(providers, @scopes[scope])
    providers.push(@fuzzyProvider) unless _.size(providers) > 0
    providers

  # Private: Gets called when the user successfully confirms a suggestion
  #
  # match - An {Object} representing the confirmed suggestion
  confirm: (match) =>
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
  isCurrentFileBlackListed: ->
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

  #  |||              |||
  #  vvv PROVIDER API vvv

  registerProviderForGrammars: (provider, grammars) =>
    return unless provider?
    return unless grammars? and _.size(grammars) > 0
    grammars = _.filter(grammars, (grammar) -> grammar?.scopeName?)
    scopes = _.pluck(grammars, 'scopeName')
    return @registerProviderForScopes(provider, scopes)

  registerProviderForScopes: (provider, scopes) =>
    return unless provider?
    return unless scopes? and _.size(scopes) > 0
    for scope in scopes
      existing = _.findWhere(_.keys(@scopes), scope)
      if existing? and @scopes[scope]?
        @scopes[scope].push(provider)
        @scopes[scope] = _.uniq(@scopes[scope])
      else
        @scopes[scope] = [provider]

    if provider.dispose?
      @subscriptions.add(provider) unless _.contains(@subscriptions, provider)

    new Disposable =>
      @unregisterProviderForScopes(provider, scopes)

  registerProviderForEditor: (provider, editor) =>
    return unless provider?
    return unless editor?
    grammar = editor?.getGrammar()
    return unless grammar?
    return if grammar.scopeName is 'text.plain.null-grammar'
    return @registerProviderForGrammars(provider, [grammar])

  unregisterProviderForGrammars: (provider, grammars) =>
    return unless provider?
    return unless grammars? and _.size(grammars) > 0
    grammars = _.filter(grammars, (grammar) -> grammar?.scopeName?)
    scopes = _.pluck(grammars, 'scopeName')
    return @unregisterProviderForScopes(provider, scopes)

  unregisterProviderForScopes: (provider, scopes) =>
    return unless provider?
    return unless scopes? and _.size(scopes) > 0

    for scope in scopes
      existing = _.findWhere(_.keys(@scopes), scope)
      if existing?
        @scopes[scope] = _.filter(@scopes[scope], (p) -> p isnt provider)
        delete @scopes[scope] unless _.size(@scopes[scope]) > 0

    @subscriptions.remove(provider) unless @providerIsRegistered(provider)

  providerIsRegistered: (provider, scopes) =>
    # TODO: Actually determine if the provider is registered
    return true

  unregisterProviderForEditor: (provider, editor) =>
    return unless provider?
    return unless editor?
    grammar = editor?.getGrammar()
    return unless grammar?
    return @unregisterProviderForGrammars(provider, [grammar])

  unregisterProvider: (provider) =>
    return unless provider?
    return @unregisterProviderForScopes(provider, _.keys(@scopes))
    @subscriptions.remove(provider) if provider.dispose?

  provideApi: =>
    atom.services.provide 'autocomplete.provider-api', "1.0.0", { @registerProviderForEditor, @unregisterProviderForEditor, @unregisterProvider, Provider, Suggestion }
    atom.services.provide 'autocomplete.provider-api', '2.0.0', { @registerProviderForGrammars, @registerProviderForScopes, @unregisterProviderForGrammars, @unregisterProviderForScopes, @unregisterProvider }

  # ^^^ PROVIDER API ^^^
  # |||              |||

  # Public: Clean up, stop listening to events
  dispose: ->
    @editorSubscriptions?.dispose()
    @editorSubscriptions = null
    @suggestionList.destroy()
    @subscriptions.dispose()
    @emitter.emit('did-dispose')

  onDidDispose: (fn) ->
    @emitter.on('did-dispose', fn)
