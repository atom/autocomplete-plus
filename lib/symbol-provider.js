'use babel'

import _ from 'underscore-plus'
import { CompositeDisposable } from 'atom'
import { Selector } from 'selector-kit'
import { UnicodeLetters } from './unicode-helpers'
import SymbolStore from './symbol-store'

export default class SymbolProvider {
  constructor () {
    this.defaults()
    this.subscriptions = new CompositeDisposable()
    this.subscriptions.add(atom.config.observe('autocomplete-plus.enableExtendedUnicodeSupport', enableExtendedUnicodeSupport => {
      if (enableExtendedUnicodeSupport) {
        this.wordRegex = new RegExp(`[${UnicodeLetters}\\d_]*[${UnicodeLetters}}_-]+[${UnicodeLetters}}\\d_]*(?=[^${UnicodeLetters}\\d_]|$)`, 'g')
        this.beginningOfLineWordRegex = new RegExp(`^[${UnicodeLetters}\\d_]*[${UnicodeLetters}_-]+[${UnicodeLetters}\\d_]*(?=[^${UnicodeLetters}\\d_]|$)`, 'g')
        this.endOfLineWordRegex = new RegExp(`[${UnicodeLetters}\\d_]*[${UnicodeLetters}_-]+[${UnicodeLetters}\\d_]*$`, 'g')
      } else {
        this.wordRegex = /\b\w*[a-zA-Z_-]+\w*\b/g
        this.beginningOfLineWordRegex = /^\w*[a-zA-Z_-]+\w*\b/g
        this.endOfLineWordRegex = /\b\w*[a-zA-Z_-]+\w*$/g
      }

      this.symbolStore = new SymbolStore(this.wordRegex)
      return this.symbolStore
    }))
    this.watchedBuffers = new WeakMap()

    this.subscriptions.add(atom.config.observe('autocomplete-plus.minimumWordLength', (minimumWordLength) => {
      this.minimumWordLength = minimumWordLength
    }))
    this.subscriptions.add(atom.config.observe('autocomplete-plus.includeCompletionsFromAllBuffers', (includeCompletionsFromAllBuffers) => {
      this.includeCompletionsFromAllBuffers = includeCompletionsFromAllBuffers
    }))
    this.subscriptions.add(atom.config.observe('autocomplete-plus.useAlternateScoring', (useAlternateScoring) => {
      this.symbolStore.setUseAlternateScoring(useAlternateScoring)
    }))
    this.subscriptions.add(atom.config.observe('autocomplete-plus.useLocalityBonus', (useLocalityBonus) => {
      this.symbolStore.setUseLocalityBonus(useLocalityBonus)
    }))
    this.subscriptions.add(atom.config.observe('autocomplete-plus.strictMatching', (useStrictMatching) => {
      this.symbolStore.setUseStrictMatching(useStrictMatching)
    }))
    this.subscriptions.add(atom.workspace.observeActivePaneItem((e) => { this.updateCurrentEditor(e) }))
    this.subscriptions.add(atom.workspace.observeTextEditors((e) => { this.watchEditor(e) }))
  }

  defaults () {
    this.wordRegex = null
    this.beginningOfLineWordRegex = null
    this.endOfLineWordRegex = null
    this.symbolStore = null
    this.editor = null
    this.buffer = null
    this.changeUpdateDelay = 300

    this.labels = ['workspace-center', 'default', 'symbol-provider']
    this.scopeSelector = '*'
    this.inclusionPriority = 0
    this.suggestionPriority = 0

    this.watchedBuffers = null

    this.config = null
    this.defaultConfig = {
      class: {
        selector: '.class.name, .inherited-class, .instance.type',
        typePriority: 4
      },
      function: {
        selector: '.function.name',
        typePriority: 3
      },
      variable: {
        selector: '.variable',
        typePriority: 2
      },
      '': {
        selector: '.source',
        typePriority: 1
      }
    }
  }

  dispose () {
    return this.subscriptions.dispose()
  }

  watchEditor (editor) {
    let bufferEditors
    const buffer = editor.getBuffer()
    const editorSubscriptions = new CompositeDisposable()
    editorSubscriptions.add(editor.onDidTokenize(() => {
      return this.buildWordListOnNextTick(editor)
    }))
    editorSubscriptions.add(editor.onDidDestroy(() => {
      const index = this.getWatchedEditorIndex(editor)
      const editors = this.watchedBuffers.get(editor.getBuffer())
      if (index > -1) { editors.splice(index, 1) }
      return editorSubscriptions.dispose()
    }))

    bufferEditors = this.watchedBuffers.get(buffer)
    if (bufferEditors) {
      bufferEditors.push(editor)
    } else {
      const bufferSubscriptions = new CompositeDisposable()
      bufferSubscriptions.add(buffer.onDidStopChanging(({changes}) => {
        let editors = this.watchedBuffers.get(buffer)
        if (!editors) {
          editors = []
        }
        if (editors && editors.length > 0 && editors[0] && !editors[0].largeFileMode) {
          for (const {start, oldExtent, newExtent} of changes) {
            this.symbolStore.recomputeSymbolsForEditorInBufferRange(editors[0], start, oldExtent, newExtent)
          }
        }
      }))
      bufferSubscriptions.add(buffer.onDidDestroy(() => {
        this.symbolStore.clear(buffer)
        bufferSubscriptions.dispose()
        return this.watchedBuffers.delete(buffer)
      }))

      this.watchedBuffers.set(buffer, [editor])
      this.buildWordListOnNextTick(editor)
    }
  }

  isWatchingEditor (editor) {
    return this.getWatchedEditorIndex(editor) > -1
  }

  isWatchingBuffer (buffer) {
    return (this.watchedBuffers.get(buffer) != null)
  }

  getWatchedEditorIndex (editor) {
    const editors = this.watchedBuffers.get(editor.getBuffer())
    if (editors) {
      return editors.indexOf(editor)
    } else {
      return -1
    }
  }

  updateCurrentEditor (currentPaneItem) {
    if (currentPaneItem == null) { return }
    if (currentPaneItem === this.editor) { return }
    this.editor = null
    if (this.paneItemIsValid(currentPaneItem)) {
      this.editor = currentPaneItem
      return this.editor
    }
  }

  buildConfigIfScopeChanged ({editor, scopeDescriptor}) {
    if (!this.scopeDescriptorsEqual(this.configScopeDescriptor, scopeDescriptor)) {
      this.buildConfig(scopeDescriptor)
      this.configScopeDescriptor = scopeDescriptor
      return this.configScopeDescriptor
    }
  }

  buildConfig (scopeDescriptor) {
    this.config = {}
    const legacyCompletions = this.settingsForScopeDescriptor(scopeDescriptor, 'editor.completions')
    const allConfigEntries = this.settingsForScopeDescriptor(scopeDescriptor, 'autocomplete.symbols')

    // Config entries are reverse sorted in order of specificity. We want most
    // specific to win; this simplifies the loop.
    allConfigEntries.reverse()

    for (let i = 0; i < legacyCompletions.length; i++) {
      const { value } = legacyCompletions[i]
      if (Array.isArray(value) && value.length) {
        this.addLegacyConfigEntry(value)
      }
    }

    let addedConfigEntry = false
    for (let j = 0; j < allConfigEntries.length; j++) {
      const { value } = allConfigEntries[j]
      if (!Array.isArray(value) && typeof value === 'object') {
        this.addConfigEntry(value)
        addedConfigEntry = true
      }
    }

    if (!addedConfigEntry) { return this.addConfigEntry(this.defaultConfig) }
  }

  addLegacyConfigEntry (suggestions) {
    suggestions = (suggestions.map((suggestion) => ({text: suggestion, type: 'builtin'})))
    if (this.config.builtin == null) {
      this.config.builtin = {suggestions: []}
    }
    this.config.builtin.suggestions = this.config.builtin.suggestions.concat(suggestions)
    return this.config.builtin.suggestions
  }

  addConfigEntry (config) {
    for (const type in config) {
      const options = config[type]
      if (this.config[type] == null) { this.config[type] = {} }
      if (options.selector != null) { this.config[type].selectors = Selector.create(options.selector) }
      this.config[type].typePriority = options.typePriority != null ? options.typePriority : 1
      this.config[type].wordRegex = this.wordRegex

      const suggestions = this.sanitizeSuggestionsFromConfig(options.suggestions, type)
      if ((suggestions != null) && suggestions.length) { this.config[type].suggestions = suggestions }
    }
  }

  sanitizeSuggestionsFromConfig (suggestions, type) {
    if ((suggestions != null) && Array.isArray(suggestions)) {
      const sanitizedSuggestions = []
      for (let i = 0; i < suggestions.length; i++) {
        let suggestion = suggestions[i]
        if (typeof suggestion === 'string') {
          sanitizedSuggestions.push({text: suggestion, type})
        } else if (typeof suggestions[0] === 'object' && ((suggestion.text != null) || (suggestion.snippet != null))) {
          suggestion = _.clone(suggestion)
          if (suggestion.type == null) { suggestion.type = type }
          sanitizedSuggestions.push(suggestion)
        }
      }
      return sanitizedSuggestions
    } else {
      return null
    }
  }

  uniqueFilter (completion) { return completion.text }

  paneItemIsValid (paneItem) {
    // TODO: remove conditional when `isTextEditor` is shipped.
    if (typeof atom.workspace.isTextEditor === 'function') {
      return atom.workspace.isTextEditor(paneItem)
    } else {
      if (paneItem == null) { return false }
      // Should we disqualify TextEditors with the Grammar text.plain.null-grammar?
      return (paneItem.getText != null)
    }
  }

  /*
  Section: Suggesting Completions
  */

  getSuggestions (options) {
    if (!options.prefix) {
      return
    }

    if (options.prefix.trim().length < this.minimumWordLength) {
      return
    }

    this.buildConfigIfScopeChanged(options)
    const editor = options.editor
    const bufferPosition = options.bufferPosition
    const prefix = options.prefix

    let numberOfWordsMatchingPrefix = 1
    const wordUnderCursor = this.wordAtBufferPosition(editor, bufferPosition)
    const iterable = editor.getCursors()
    for (let i = 0; i < iterable.length; i++) {
      const cursor = iterable[i]
      if (cursor === editor.getLastCursor()) { continue }
      const word = this.wordAtBufferPosition(editor, cursor.getBufferPosition())
      if (word === wordUnderCursor) { numberOfWordsMatchingPrefix += 1 }
    }

    const buffers = this.includeCompletionsFromAllBuffers ? null : [this.editor.getBuffer()]
    const symbolList = this.symbolStore.symbolsForConfig(
      this.config,
      buffers,
      prefix,
      wordUnderCursor,
      bufferPosition.row,
      numberOfWordsMatchingPrefix
    )

    symbolList.sort((a, b) => (b.score * b.localityScore) - (a.score * a.localityScore))
    return symbolList.slice(0, 20).map(a => a.symbol)
  }

  wordAtBufferPosition (editor, bufferPosition) {
    const lineToPosition = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
    let prefix = lineToPosition.match(this.endOfLineWordRegex)
    if (prefix) {
      prefix = prefix[0]
    } else {
      prefix = ''
    }

    const lineFromPosition = editor.getTextInRange([bufferPosition, [bufferPosition.row, Infinity]])
    let suffix = lineFromPosition.match(this.beginningOfLineWordRegex)
    if (suffix) {
      suffix = suffix[0]
    } else {
      suffix = ''
    }

    return prefix + suffix
  }

  settingsForScopeDescriptor (scopeDescriptor, keyPath) {
    return atom.config.getAll(keyPath, {scope: scopeDescriptor})
  }

  /*
  Section: Word List Building
  */

  buildWordListOnNextTick (editor) {
    return _.defer(() => {
      if (editor && editor.isAlive() && !editor.largeFileMode) {
        const start = {row: 0, column: 0}
        const oldExtent = {row: 0, column: 0}
        const newExtent = editor.getBuffer().getRange().getExtent()
        return this.symbolStore.recomputeSymbolsForEditorInBufferRange(editor, start, oldExtent, newExtent)
      }
    })
  }

  // FIXME: this should go in the core ScopeDescriptor class
  scopeDescriptorsEqual (a, b) {
    if (a === b) { return true }
    if ((a == null) || (b == null)) { return false }

    const arrayA = a.getScopesArray()
    const arrayB = b.getScopesArray()

    if (arrayA.length !== arrayB.length) { return false }

    for (let i = 0; i < arrayA.length; i++) {
      const scope = arrayA[i]
      if (scope !== arrayB[i]) { return false }
    }
    return true
  }
}
