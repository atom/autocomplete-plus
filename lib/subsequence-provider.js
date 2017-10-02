const { CompositeDisposable, TextBuffer } = require('atom')
const ProviderConfig = require('./provider-config')

class SubsequenceProvider {
  constructor (options = {}) {
    this.defaults()

    this.subscriptions = new CompositeDisposable()
    this.watchedBuffers = new Map()

    if (options.atomConfig) {
      this.atomConfig = options.atomConfig
    }

    if (options.atomWorkspace) {
      this.atomWorkspace = options.atomWorkspace
    }

    this.providerConfig = new ProviderConfig({
      atomConfig: this.atomConfig
    })

    // make this.X available where X is the autocomplete-plus.X setting
    const settings = [
      'autocomplete-plus.enableExtendedUnicodeSupport', // TODO
      'autocomplete-plus.minimumWordLength',
      'autocomplete-plus.includeCompletionsFromAllBuffers',
      'autocomplete-plus.useLocalityBonus',
      'autocomplete-plus.strictMatching'
    ]
    settings.forEach(property => {
      this.subscriptions.add(this.atomConfig.observe(property, val => {
        this[property.split('.')[1]] = val
      }))
    })

    this.subscriptions.add(this.atomWorkspace.observeTextEditors((e) => {
      this.watchBuffer(e)
    }))

    this.configSuggestionsBuffer = new TextBuffer()
  }

  defaults () {
    this.atomConfig = atom.config
    this.atomWorkspace = atom.workspace

    this.additionalWordChars = '_'
    this.enableExtendedUnicodeSupport = false
    this.maxSuggestions = 20
    this.maxResultsPerBuffer = 100
    this.maxSearchRowDelta = 3000

    this.labels = ['workspace-center', 'default', 'subsequence-provider']
    this.scopeSelector = '*'
    this.inclusionPriority = 0
    this.suggestionPriority = 0

    this.watchedBuffers = null
  }

  dispose () {
    return this.subscriptions.dispose()
  }

  watchBuffer (editor) {
    const buffer = editor.getBuffer()

    this.watchedBuffers.set(buffer, editor)

    const bufferSubscriptions = new CompositeDisposable()

    bufferSubscriptions.add(buffer.onDidDestroy(() => {
      bufferSubscriptions.dispose()
      return this.watchedBuffers.delete(buffer)
    }))
  }

  // This is kind of a hack. We throw the config suggestions in a buffer, so
  // we can use .findWordsWithSubsequence on them.
  configSuggestionsToSubsequenceMatches (suggestions, prefix) {
    const suggestionText = suggestions
      .map(sug => sug.displayText || sug.snippet || sug.text)
      .join('\n')

    this.configSuggestionsBuffer.setText(suggestionText)

    const assocSuggestion = word => {
      word.configSuggestion = suggestions[word.positions[0].row]
      return word
    }

    return this.configSuggestionsBuffer.findWordsWithSubsequence(
      prefix,
      '(){}[] :;,$@%',
      this.maxResultsPerBuffer
    ).then(words => words.map(assocSuggestion))
  }

  clampedRange (maxDelta, cursorRow, maxRow) {
    const clampedMinRow = Math.max(0, cursorRow - maxDelta)
    const clampedMaxRow = Math.min(maxRow, cursorRow + maxDelta)
    const actualMinRowDelta = cursorRow - clampedMinRow
    const actualMaxRowDelta = clampedMaxRow - cursorRow

    return {
      start: {
        row: clampedMinRow - maxDelta + actualMaxRowDelta,
        column: 0
      },
      end: {
        row: clampedMaxRow + maxDelta - actualMinRowDelta,
        column: 0
      }
    }
  }

  /*
  Section: Suggesting Completions
  */

  getSuggestions ({editor, bufferPosition, prefix, scopeDescriptor}) {
    if (!prefix) {
      return
    }

    if (prefix.trim().length < this.minimumWordLength) {
      return
    }

    const buffers = this.includeCompletionsFromAllBuffers
      ? Array.from(this.watchedBuffers.keys())
      : [editor.getBuffer()]

    const configSuggestions = this.providerConfig.getSuggestionsForScopeDescriptor(
      scopeDescriptor
    )

    const configMatches = this.configSuggestionsToSubsequenceMatches(
      configSuggestions,
      prefix
    )

    const wordsUnderCursors = editor.getCursors().map(cursor =>
      editor.getBuffer().getTextInRange(cursor.getCurrentWordBufferRange())
    )

    const bufferToMaxSearchRange = (buffer) => {
      const position = this.watchedBuffers.get(buffer).getCursorBufferPosition()
      return this.clampedRange(this.maxSearchRowDelta, position.row, buffer.getEndPosition().row)
    }

    const bufferToSubsequenceMatches = (buffer) => {
      return buffer.findWordsWithSubsequenceInRange(
        prefix,
        this.additionalWordChars,
        this.maxResultsPerBuffer,
        bufferToMaxSearchRange(buffer)
      )
    }

    const subsequenceMatchToType = (match) => {
      const editor = this.watchedBuffers.get(match.buffer)
      const scopeDescriptor = editor.scopeDescriptorForBufferPosition(match.positions[0])
      return this.providerConfig.scopeDescriptorToType(scopeDescriptor)
    }

    const matchToSuggestion = match => {
      return match.configSuggestion || {
        text: match.word,
        type: subsequenceMatchToType(match)
      }
    }

    const isWordUnderCursor = match => {
      return !(wordsUnderCursors.indexOf(match.word) === -1 ||
        match.positions.length > wordsUnderCursors.filter(word => match.word === word).length)
    }

    const applyLocalityBonus = match => {
      if (match.buffer === editor.getBuffer() && match.score > 0) {
        let lastCursorRow = editor.getLastCursor().getBufferPosition().row
        let distances = match
          .positions
          .map(pos => Math.abs(pos.row - lastCursorRow))
        let closest = Math.min.apply(Math, distances)
        match.score += Math.floor(11 / (1 + 0.04 * closest))
      }
      return match
    }

    const isStrictIfEnabled = match => {
      return this.strictMatching
        ? match.word.indexOf(prefix) === 0
        : true
    }

    const bufferResultsToSuggestions = matchesByBuffer => {
      const relevantMatches = []
      let matchedWords = {}

      for (let k = 0; k < matchesByBuffer.length; k++) {
        for (let l = 0; l < matchesByBuffer[k].length; l++) {
          let match = matchesByBuffer[k][l]

          if (isWordUnderCursor(match)) continue

          if (!isStrictIfEnabled(match)) continue

          if (matchedWords[match.word]) continue

          if (k < matchesByBuffer.length - 1) {
            match.buffer = buffers[k]
          }

          relevantMatches.push(
            this.useLocalityBonus ? applyLocalityBonus(match) : match
          )

          matchedWords[match.word] = true
        }
      }

      return relevantMatches
        .sort((a, b) => b.score - a.score)
        .slice(0, this.maxSuggestions)
        .map(matchToSuggestion)
    }

    return Promise
      .all(buffers.map(bufferToSubsequenceMatches).concat(configMatches))
      .then(bufferResultsToSuggestions)
  }
}

module.exports = SubsequenceProvider
