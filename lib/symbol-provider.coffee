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

  config: null
  defaultConfig:
    class:
      selector: '.class.name, .inherited-class'
      priority: 3
    function:
      selector: '.function.name'
      priority: 2
    variable:
      selector: '.variable'
      priority: 1

  constructor: ->
    @id = 'autocomplete-plus-symbolprovider'
    @subscriptions = new CompositeDisposable
    @subscriptions.add(atom.workspace.observeActivePaneItem(@updateCurrentEditor))

  dispose: =>
    @editorSubscriptions?.dispose()
    @subscriptions.dispose()

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

    @buildConfig()
    @buildWordListOnNextTick()

  buildConfig: ->
    @config = {}

    allConfig = @settingsForScopeDescriptor(@editor.getRootScopeDescriptor(), 'editor.completionSymbols')
    allConfig.push @defaultConfig unless allConfig.length

    for config in allConfig
      for type, options of config
        @config[type] = _.clone(options)
        @config[type].selectors = Selector.create(options.selector) if options.selector?
        @config[type].selectors ?= []
        @config[type].priority ?= 1
        @config[type].wordRegex ?= @wordRegex

    return

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

    new Promise (resolve) =>
      _.defer =>
        suggestions = @findSuggestionsForWord(options)
        resolve(suggestions)

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
    atom.config.getAll(keyPath, scope: scopeDescriptor)

  # Private: Finds autocompletions in the current syntax scope (e.g. css values)
  #
  # Returns an {Array} of strings
  getCompletionsForCursorScope: =>
    cursorScope = @editor.scopeDescriptorForBufferPosition(@editor.getCursorBufferPosition())
    completions = @settingsForScopeDescriptor(cursorScope, "editor.completions")
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
    # Warning: displayBuffer and tokenizedBuffer are private APIs. Please do not
    # copy into your own package. If you do, be prepared to have it break
    # without warning.
    tokenizedLines = editor.displayBuffer.tokenizedBuffer.tokenizedLines

    symbolTypes = {}
    matchedSymbols = []

    # Handle the case where a symbol is a variable in some cases and, say, a
    # class in others. We want all symbols in the file to have the same type.
    # e.g. `class` types are higher priority than `variables`
    cacheSymbolType = (word, currentType) =>
      word = getWordKey(word)
      return symbolTypes[word] = currentType unless symbolTypes[word]?
      currentTypePriority = @config[currentType].priority
      cachedTypePriority = @config[symbolTypes[word]].priority
      symbolTypes[word] = currentType if currentTypePriority > cachedTypePriority

    getWordKey = (word) ->
       # some words are reserved, like 'constructor' :/
      word + '$$'

    normalizeTypesForAllSymbols = ->
      for symbol in matchedSymbols
        wordKey = getWordKey(symbol.word)
        symbol.type = symbolTypes[wordKey] if symbolTypes[wordKey]?
      return

    for {tokens}, bufferRow in tokenizedLines
      for token in tokens
        scopes = @cssSelectorFromScopes(token.scopes)
        for type, options of @config
          for selector in options.selectors
            if selector.matches(scopes) and matches = token.value.match(options.wordRegex)
              for word in matches
                if word.length >= minimumWordLength
                  matchedSymbols.push {type, word, bufferRow, scopes}
                  cacheSymbolType(word, type)
              break

    normalizeTypesForAllSymbols()
    matchedSymbols

  cssSelectorFromScopes: (scopes) ->
    selector = ''
    selector += ' .' + scope for scope in scopes
    selector
