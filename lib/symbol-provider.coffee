_ = require 'underscore-plus'
Suggestion = require './suggestion'
fuzzaldrin = require 'fuzzaldrin'
{TextEditor, CompositeDisposable}  = require 'atom'
{Selector} = require 'selector-kit'

module.exports =
class SymbolProvider
  wordRegex: /\b\w*[a-zA-Z_-]+\w*\b/g
  wordList: null
  editor: null
  buffer: null

  selector: '*'

  completionSymbolSelectors: null
  defaultCompletionSymbolSelectors:
    class: '.class.name'
    function: '.function'
    variable: '.variable'

  constructor: ->
    @id = 'autocomplete-plus-symbolprovider'
    @subscriptions = new CompositeDisposable
    @subscriptions.add(atom.workspace.observeActivePaneItem(@updateCurrentEditor))
    @buildSelectors()
    @buildWordListOnNextTick()

  # Public: Clean up, stop listening to events
  dispose: =>
    @editorSubscriptions?.dispose()
    @subscriptions.dispose()

  buildSelectors: ->
    @completionSymbolSelectors = {}

    # TODO: read from atom.config and default to ... the defaults
    completionSelectors = @defaultCompletionSymbolSelectors

    for type, selector of completionSelectors
      [@completionSymbolSelectors[type]] = Selector.create(selector)

    return

  updateCurrentEditor: (currentPaneItem) =>
    return unless currentPaneItem?
    return if currentPaneItem is @editor

    @editorSubscriptions?.dispose()
    @editorSubscriptions = new CompositeDisposable

    @editor = null
    @buffer = null

    return unless @paneItemIsValid(currentPaneItem)

    @editor = currentPaneItem
    @buffer = @editor.getBuffer()

    @editorSubscriptions.add @editor.displayBuffer.onDidTokenize(@buildWordListOnNextTick)
    @editorSubscriptions.add @buffer.onDidSave(@buildWordListOnNextTick)
    @editorSubscriptions.add @buffer.onDidChange(@bufferChanged)
    @buildWordListOnNextTick()

  paneItemIsValid: (paneItem) =>
    return false unless paneItem?
    # Should we disqualify TextEditors with the Grammar text.plain.null-grammar?
    return paneItem instanceof TextEditor

  bufferChanged: (e) =>
    # console.log 'changed'

  ###
  Section: Suggesting Completions
  ###

  # Public:  Gets called when the document has been changed. Returns an array
  # with suggestions. If `exclusive` is set to true and this method returns
  # suggestions, the suggestions will be the only ones that are displayed.
  #
  # Returns an {Array} of Suggestion instances
  requestHandler: (options) =>
    return unless options?
    return unless options.editor?
    selection = options.editor.getLastSelection()
    prefix = options.prefix

    # No prefix? Don't autocomplete!
    return unless prefix.trim().length

    suggestions = @findSuggestionsForWord(prefix)

    # No suggestions? Don't autocomplete!
    return unless suggestions.length

    # Now we're ready - display the suggestions
    return suggestions

  # Private: Finds possible matches for the given string / prefix
  #
  # prefix - {String} The prefix
  #
  # Returns an {Array} of Suggestion instances
  findSuggestionsForWord: (prefix) =>
    return unless @wordList?
    # Merge the scope specific words into the default word list
    wordList = @wordList.concat(@getCompletionsForCursorScope())

    words =
      if atom.config.get("autocomplete-plus.strictMatching")
        wordList.filter((match) -> match.word?.indexOf(prefix) is 0)
      else
        fuzzaldrin.filter(wordList, prefix, key: 'word')

    for word in words
      word.prefix = prefix
      word.label = word.type

    return words

  settingsForScopeDescriptor: (scopeDescriptor, keyPath) =>
    entries = atom.config.getAll(null, scope: scopeDescriptor)
    value for {value} in entries when _.valueForKeyPath(value, keyPath)?

  # Private: Finds autocompletions in the current syntax scope (e.g. css values)
  #
  # Returns an {Array} of strings
  getCompletionsForCursorScope: =>
    cursorScope = @editor.scopeDescriptorForBufferPosition(@editor.getCursorBufferPosition())
    completions = @settingsForScopeDescriptor(cursorScope.getScopesArray(), "editor.completions")
    scopedCompletions = []
    for properties in completions
      if suggestions = _.valueForKeyPath(properties, "editor.completions")
        for suggestion in suggestions
          scopedCompletions.push
            word: suggestion
            type: 'builtin'

    _.uniq scopedCompletions, (completion) -> completion.word

  ###
  Section: Word List Building
  ###

  buildWordListOnNextTick: =>
    _.defer => @buildWordList()

  buildWordList: =>
    return unless @editor?

    minimumWordLength = atom.config.get('autocomplete-plus.minimumWordLength')
    wordList = @getSymbolsFromEditor(@editor, minimumWordLength)

    # Do we want autocompletions from all open buffers?
    if atom.config.get('autocomplete-plus.includeCompletionsFromAllBuffers')
      for editor in atom.workspace.getEditors()
        # FIXME: downside is that some of these editors will not be tokenized :/
        wordList = wordList.concat @getSymbolsFromEditor(editor, minimumWordLength)

    @wordList = wordList

  getSymbolsFromEditor: (editor, minimumWordLength) ->
    tokenizedLines = editor.displayBuffer.tokenizedBuffer.tokenizedLines
    matchedTokens = []
    for {tokens}, bufferRow in tokenizedLines
      for token in tokens
        scopes = @cssSelectorFromScopes(token.scopes)
        for type, selector of @completionSymbolSelectors
          if selector.matches(scopes) and matches = token.value.match(@wordRegex)
            for word in matches
              matchedTokens.push {type, word, bufferRow} if word >= minimumWordLength

    matchedTokens

  cssSelectorFromScopes: (scopes) ->
    selector = ''
    selector += ' .' + scope for scope in scopes
    selector
