'use babel'

import fuzzaldrin from 'fuzzaldrin'
import { CompositeDisposable } from 'atom'
import RefCountedTokenList from './ref-counted-token-list'
import { UnicodeLetters } from './unicode-helpers'

export default class FuzzyProvider {
  constructor () {
    this.deferBuildWordListInterval = 300
    this.updateBuildWordListTimeout = null
    this.updateCurrentEditorTimeout = null
    this.wordRegex = null
    this.tokenList = new RefCountedTokenList()
    this.currentEditorSubscriptions = null
    this.editor = null
    this.buffer = null

    this.scopeSelector = '*'
    this.inclusionPriority = 0
    this.suggestionPriority = 0
    this.debouncedUpdateCurrentEditor = this.debouncedUpdateCurrentEditor.bind(this)
    this.updateCurrentEditor = this.updateCurrentEditor.bind(this)
    this.getSuggestions = this.getSuggestions.bind(this)
    this.bufferSaved = this.bufferSaved.bind(this)
    this.bufferWillChange = this.bufferWillChange.bind(this)
    this.bufferDidChange = this.bufferDidChange.bind(this)
    this.buildWordList = this.buildWordList.bind(this)
    this.findSuggestionsForWord = this.findSuggestionsForWord.bind(this)
    this.dispose = this.dispose.bind(this)
    this.subscriptions = new CompositeDisposable()
    this.subscriptions.add(atom.config.observe('autocomplete-plus.enableExtendedUnicodeSupport', enableExtendedUnicodeSupport => {
      if (enableExtendedUnicodeSupport) {
        this.wordRegex = new RegExp(`[${UnicodeLetters}\\d_]+[${UnicodeLetters}\\d_-]*`, 'g')
      } else {
        this.wordRegex = /\b\w+[\w-]*\b/g
      }
    }))
    this.debouncedBuildWordList()
    this.subscriptions.add(atom.workspace.observeActivePaneItem(this.debouncedUpdateCurrentEditor))
    const builtinProviderBlacklist = atom.config.get('autocomplete-plus.builtinProviderBlacklist')
    if ((builtinProviderBlacklist != null) && builtinProviderBlacklist.length) { this.disableForScopeSelector = builtinProviderBlacklist }
  }

  debouncedUpdateCurrentEditor (currentPaneItem) {
    clearTimeout(this.updateBuildWordListTimeout)
    clearTimeout(this.updateCurrentEditorTimeout)
    this.updateCurrentEditorTimeout = setTimeout(() => {
      this.updateCurrentEditor(currentPaneItem)
    }
    , this.deferBuildWordListInterval)
  }

  updateCurrentEditor (currentPaneItem) {
    if (currentPaneItem == null) { return }
    if (currentPaneItem === this.editor) { return }

    // Stop listening to buffer events
    if (this.currentEditorSubscriptions) {
      this.currentEditorSubscriptions.dispose()
    }

    this.editor = null
    this.buffer = null

    if (!this.paneItemIsValid(currentPaneItem)) { return }

    // Track the new editor, editorView, and buffer
    this.editor = currentPaneItem
    this.buffer = this.editor.getBuffer()

    // Subscribe to buffer events:
    this.currentEditorSubscriptions = new CompositeDisposable()
    if (this.editor && !this.editor.largeFileMode) {
      this.currentEditorSubscriptions.add(this.buffer.onDidSave(this.bufferSaved))
      this.currentEditorSubscriptions.add(this.buffer.onWillChange(this.bufferWillChange))
      this.currentEditorSubscriptions.add(this.buffer.onDidChange(this.bufferDidChange))
      this.buildWordList()
    }
  }

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

  // Public:  Gets called when the document has been changed. Returns an array
  // with suggestions. If `exclusive` is set to true and this method returns
  // suggestions, the suggestions will be the only ones that are displayed.
  //
  // Returns an {Array} of Suggestion instances
  getSuggestions ({editor, prefix, scopeDescriptor}) {
    if (editor == null) { return }

    // No prefix? Don't autocomplete!
    if (!prefix.trim().length) { return }

    const suggestions = this.findSuggestionsForWord(prefix, scopeDescriptor)

    // No suggestions? Don't autocomplete!
    if (!suggestions || !suggestions.length) {
      return
    }

    // Now we're ready - display the suggestions
    return suggestions
  }

  // Private: Gets called when the user saves the document. Rebuilds the word
  // list.
  bufferSaved () {
    return this.buildWordList()
  }

  bufferWillChange ({oldRange}) {
    const oldLines = this.editor.getTextInBufferRange([[oldRange.start.row, 0], [oldRange.end.row, Infinity]])
    return this.removeWordsForText(oldLines)
  }

  bufferDidChange ({newRange}) {
    const newLines = this.editor.getTextInBufferRange([[newRange.start.row, 0], [newRange.end.row, Infinity]])
    return this.addWordsForText(newLines)
  }

  debouncedBuildWordList () {
    clearTimeout(this.updateBuildWordListTimeout)
    this.updateBuildWordListTimeout = setTimeout(() => {
      this.buildWordList()
    }
    , this.deferBuildWordListInterval)
  }

  buildWordList () {
    if (this.editor == null) { return }

    this.tokenList.clear()
    let editors
    if (atom.config.get('autocomplete-plus.includeCompletionsFromAllBuffers')) {
      editors = atom.workspace.getTextEditors()
    } else {
      editors = [this.editor]
    }

    return editors.map((editor) =>
      this.addWordsForText(editor.getText()))
  }

  addWordsForText (text) {
    const minimumWordLength = atom.config.get('autocomplete-plus.minimumWordLength')
    const matches = text.match(this.wordRegex)
    if (matches == null) { return }
    return (() => {
      const result = []
      for (let i = 0; i < matches.length; i++) {
        const match = matches[i]
        let item
        if ((minimumWordLength && match.length >= minimumWordLength) || !minimumWordLength) {
          item = this.tokenList.addToken(match)
        }
        result.push(item)
      }
      return result
    })()
  }

  removeWordsForText (text) {
    const matches = text.match(this.wordRegex)
    if (matches == null) { return }
    return matches.map((match) =>
      this.tokenList.removeToken(match))
  }

  // Private: Finds possible matches for the given string / prefix
  //
  // prefix - {String} The prefix
  //
  // Returns an {Array} of Suggestion instances
  findSuggestionsForWord (prefix, scopeDescriptor) {
    if (!this.tokenList.getLength() || (this.editor == null)) { return }

    // Merge the scope specific words into the default word list
    let tokens = this.tokenList.getTokens()
    tokens = tokens.concat(this.getCompletionsForCursorScope(scopeDescriptor))

    let words
    if (atom.config.get('autocomplete-plus.strictMatching')) {
      words = tokens.filter((word) => {
        if (!word) {
          return false
        }
        return word.indexOf(prefix) === 0
      })
    } else {
      words = fuzzaldrin.filter(tokens, prefix)
    }

    const results = []

    // dont show matches that are the same as the prefix
    for (let i = 0; i < words.length; i++) {
      // must match the first char!
      const word = words[i]
      if (word !== prefix) {
        if (!word || !prefix || prefix[0].toLowerCase() !== word[0].toLowerCase()) { continue }
        results.push({text: word, replacementPrefix: prefix})
      }
    }
    return results
  }

  settingsForScopeDescriptor (scopeDescriptor, keyPath) {
    return atom.config.getAll(keyPath, {scope: scopeDescriptor})
  }

  // Private: Finds autocompletions in the current syntax scope (e.g. css values)
  //
  // Returns an {Array} of strings
  getCompletionsForCursorScope (scopeDescriptor) {
    const completions = this.settingsForScopeDescriptor(scopeDescriptor, 'editor.completions')
    const seen = {}
    const resultCompletions = []
    for (let i = 0; i < completions.length; i++) {
      const {value} = completions[i]
      if (Array.isArray(value)) {
        for (let j = 0; j < value.length; j++) {
          const completion = value[j]
          if (!seen[completion]) {
            resultCompletions.push(completion)
            seen[completion] = true
          }
        }
      }
    }
    return resultCompletions
  }

  // Public: Clean up, stop listening to events
  dispose () {
    clearTimeout(this.updateBuildWordListTimeout)
    clearTimeout(this.updateCurrentEditorTimeout)
    if (this.currentEditorSubscriptions) {
      this.currentEditorSubscriptions.dispose()
    }
    return this.subscriptions.dispose()
  }
}
