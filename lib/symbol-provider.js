'use babel'

import _ from 'underscore-plus'
import { TextBuffer, CompositeDisposable, Disposable } from 'atom'
import { Selector } from 'selector-kit'
import { UnicodeLetters } from './unicode-helpers'
import SymbolStore from './symbol-store'

// TODO: remove this when `onDidStopChanging(changes)` ships on stable.
let bufferSupportsStopChanging = () => { typeof TextBuffer.prototype.onDidChangeText === 'function' }

export default class SymbolProvider {
  constructor () {
    this.defaults()
    this.dispose = this.dispose.bind(this)
    this.watchEditor = this.watchEditor.bind(this)
    this.updateCurrentEditor = this.updateCurrentEditor.bind(this)
    this.getSuggestions = this.getSuggestions.bind(this)
    this.buildWordListOnNextTick = this.buildWordListOnNextTick.bind(this)
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
    this.subscriptions.add(atom.workspace.observeActivePaneItem(this.updateCurrentEditor))
    this.subscriptions.add(atom.workspace.observeTextEditors(this.watchEditor))
  }

  defaults () {
    this.wordRegex = null
    this.beginningOfLineWordRegex = null
    this.endOfLineWordRegex = null
    this.symbolStore = null
    this.editor = null
    this.buffer = null
    this.changeUpdateDelay = 300

    this.textEditorSelectors = new Set(['atom-pane > .item-views > atom-text-editor'])
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

  addTextEditorSelector (selector) {
    this.textEditorSelectors.add(selector)
    return new Disposable(() => this.textEditorSelectors.delete(selector))
  }

  getTextEditorSelector () {
    return Array.from(this.textEditorSelectors).join(', ')
  }

  watchEditor (editor) {
    let bufferEditors
    let buffer = editor.getBuffer()
    let editorSubscriptions = new CompositeDisposable()

    // TODO: Remove this conditional once atom/ns-use-display-layers reaches stable and editor.onDidTokenize is always available
    let onDidTokenizeProvider = (editor.onDidTokenize != null) ? editor : editor.displayBuffer

    editorSubscriptions.add(onDidTokenizeProvider.onDidTokenize(() => {
      return this.buildWordListOnNextTick(editor)
    }))
    editorSubscriptions.add(editor.onDidDestroy(() => {
      let index = this.getWatchedEditorIndex(editor)
      let editors = this.watchedBuffers.get(editor.getBuffer())
      if (index > -1) { editors.splice(index, 1) }
      return editorSubscriptions.dispose()
    }))

    bufferEditors = this.watchedBuffers.get(buffer)
    if (bufferEditors) {
      return bufferEditors.push(editor)
    } else {
      let bufferSubscriptions = new CompositeDisposable()
      if (bufferSupportsStopChanging()) {
        bufferSubscriptions.add(buffer.onDidStopChanging(({changes}) => {
          let editors = this.watchedBuffers.get(buffer)
          if (editors && editors.length && editors[0]) {
            return changes.map(({start, oldExtent, newExtent}) =>
              this.symbolStore.recomputeSymbolsForEditorInBufferRange(editors[0], start, oldExtent, newExtent))
          }
        }))
      } else {
        bufferSubscriptions.add(buffer.onDidChange(({oldRange, newRange}) => {
          let editors = this.watchedBuffers.get(buffer)
          if (editors && editors.length && editors[0]) {
            let { start } = oldRange
            let oldExtent = oldRange.getExtent()
            let newExtent = newRange.getExtent()
            return this.symbolStore.recomputeSymbolsForEditorInBufferRange(editors[0], start, oldExtent, newExtent)
          }
        }))
      }

      bufferSubscriptions.add(buffer.onDidDestroy(() => {
        this.symbolStore.clear(buffer)
        bufferSubscriptions.dispose()
        return this.watchedBuffers.delete(buffer)
      }))

      this.watchedBuffers.set(buffer, [editor])
      return this.buildWordListOnNextTick(editor)
    }
  }

  isWatchingEditor (editor) {
    return this.getWatchedEditorIndex(editor) > -1
  }

  isWatchingBuffer (buffer) {
    return (this.watchedBuffers.get(buffer) != null)
  }

  getWatchedEditorIndex (editor) {
    let editors = this.watchedBuffers.get(editor.getBuffer())
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
    let legacyCompletions = this.settingsForScopeDescriptor(scopeDescriptor, 'editor.completions')
    let allConfigEntries = this.settingsForScopeDescriptor(scopeDescriptor, 'autocomplete.symbols')

    // Config entries are reverse sorted in order of specificity. We want most
    // specific to win; this simplifies the loop.
    allConfigEntries.reverse()

    for (let i = 0; i < legacyCompletions.length; i++) {
      let {value} = legacyCompletions[i]
      if (Array.isArray(value) && value.length) { this.addLegacyConfigEntry(value) }
    }

    let addedConfigEntry = false
    for (let j = 0; j < allConfigEntries.length; j++) {
      let {value} = allConfigEntries[j]
      if (!Array.isArray(value) && typeof value === 'object') {
        this.addConfigEntry(value)
        addedConfigEntry = true
      }
    }

    if (!addedConfigEntry) { return this.addConfigEntry(this.defaultConfig) }
  }

  addLegacyConfigEntry (suggestions) {
    suggestions = (suggestions.map((suggestion) => ({text: suggestion, type: 'builtin'})))
    if (this.config.builtin == null) { this.config.builtin = {suggestions: []} }
    this.config.builtin.suggestions = this.config.builtin.suggestions.concat(suggestions)
    return this.config.builtin.suggestions
  }

  addConfigEntry (config) {
    for (let type in config) {
      let options = config[type]
      if (this.config[type] == null) { this.config[type] = {} }
      if (options.selector != null) { this.config[type].selectors = Selector.create(options.selector) }
      this.config[type].typePriority = options.typePriority != null ? options.typePriority : 1
      this.config[type].wordRegex = this.wordRegex

      let suggestions = this.sanitizeSuggestionsFromConfig(options.suggestions, type)
      if ((suggestions != null) && suggestions.length) { this.config[type].suggestions = suggestions }
    }
  }

  sanitizeSuggestionsFromConfig (suggestions, type) {
    if ((suggestions != null) && Array.isArray(suggestions)) {
      let sanitizedSuggestions = []
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
    let editor = options.editor
    let bufferPosition = options.bufferPosition
    let prefix = options.prefix

    let numberOfWordsMatchingPrefix = 1
    let wordUnderCursor = this.wordAtBufferPosition(editor, bufferPosition)
    let iterable = editor.getCursors()
    for (let i = 0; i < iterable.length; i++) {
      let cursor = iterable[i]
      if (cursor === editor.getLastCursor()) { continue }
      let word = this.wordAtBufferPosition(editor, cursor.getBufferPosition())
      if (word === wordUnderCursor) { numberOfWordsMatchingPrefix += 1 }
    }

    let buffers = this.includeCompletionsFromAllBuffers ? null : [this.editor.getBuffer()]
    let symbolList = this.symbolStore.symbolsForConfig(
      this.config, buffers,
      prefix, wordUnderCursor,
      bufferPosition.row,
      numberOfWordsMatchingPrefix
    )

    symbolList.sort((a, b) => (b.score * b.localityScore) - (a.score * a.localityScore))
    return symbolList.slice(0, 20).map(a => a.symbol)
  }

  wordAtBufferPosition (editor, bufferPosition) {
    let lineToPosition = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
    let prefix = lineToPosition.match(this.endOfLineWordRegex)
    if (prefix) {
      prefix = prefix[0]
    } else {
      prefix = ''
    }

    let lineFromPosition = editor.getTextInRange([bufferPosition, [bufferPosition.row, Infinity]])
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
      if (!editor || !editor.isAlive()) {
        return
      }

      let start = {row: 0, column: 0}
      let oldExtent = {row: 0, column: 0}
      let newExtent = editor.getBuffer().getRange().getExtent()
      return this.symbolStore.recomputeSymbolsForEditorInBufferRange(editor, start, oldExtent, newExtent)
    }
    )
  }

  // FIXME: this should go in the core ScopeDescriptor class
  scopeDescriptorsEqual (a, b) {
    if (a === b) { return true }
    if ((a == null) || (b == null)) { return false }

    let arrayA = a.getScopesArray()
    let arrayB = b.getScopesArray()

    if (arrayA.length !== arrayB.length) { return false }

    for (let i = 0; i < arrayA.length; i++) {
      let scope = arrayA[i]
      if (scope !== arrayB[i]) { return false }
    }
    return true
  }
}
