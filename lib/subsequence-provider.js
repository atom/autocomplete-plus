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

    this.subscriptions.add(this.atomConfig.observe('editor.nonWordCharacters', val => {
      this.additionalWordCharacters = ''
      this.possibileWordCharacters.split('').forEach(character => {
        if (!val.includes(character)) {
          this.additionalWordCharacters += character
        }
      })
    }))

    this.subscriptions.add(this.atomWorkspace.observeTextEditors((e) => {
      this.watchBuffer(e)
    }))

    this.configSuggestionsBuffer = new TextBuffer()
  }

  defaults () {
    this.atomConfig = atom.config
    this.atomWorkspace = atom.workspace

    this.additionalWordCharacters = '_'
    this.possibileWordCharacters = '/\\()"\':,.;<>~!@#$%^&*|+=[]{}`?_-…'
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

  bufferToSubsequenceMatches (prefix, buffer) {
    const position = this.watchedBuffers.get(buffer).getCursorBufferPosition()
    return buffer.findWordsWithSubsequenceInRange(
      prefix,
      this.additionalWordCharacters,
      this.maxResultsPerBuffer,
      this.clampedRange(this.maxSearchRowDelta, position.row, buffer.getEndPosition().row)
    )
  }

  matchToSuggestion (match) {
    const editor = this.watchedBuffers.get(match.buffer)
    const scopeDescriptor = editor.scopeDescriptorForBufferPosition(match.positions[0])

    return match.configSuggestion || {
      text: match.word,
      type: this.providerConfig.scopeDescriptorToType(scopeDescriptor)
    }
  }

  matchesToSuggestions (buffers, currentBuffer, lastCursorRow, wordsUnderCursors, matchesByBuffer) {
    const relevantMatches = []
    const matchedWords = {}
    let match

    for (var k = 0; k < matchesByBuffer.length; k++) {
      for (var l = 0; l < matchesByBuffer[k].length; l++) {
        match = matchesByBuffer[k][l]

        if (matchedWords[match.word]) {
          continue
        } else {
          matchedWords[match.word] = true
        }

        if (wordsUnderCursors.includes(match.word)) continue

        if (this.strictMatching && match.word.indexOf(prefix) !== 0) continue

        if (k < matchesByBuffer.length - 1) {
          match.buffer = buffers[k]
        }

        relevantMatches.push(
          this.useLocalityBonus
            ? applyLocalityBonus(currentBuffer, lastCursorRow, match)
            : match
        )
      }
    }

    const finalMatches = relevantMatches.sort(compareMatches)

    const suggestions = []

    for (var n = 0; n < Math.min(finalMatches.length, this.maxSuggestions); n++) {
      suggestions.push(this.matchToSuggestion(finalMatches[n]))
    }

    return suggestions
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

    const currentBuffer = editor.getBuffer()
    const lastCursorRow = editor.getLastCursor().getBufferPosition().row

    const buffers = this.includeCompletionsFromAllBuffers
      ? Array.from(this.watchedBuffers.keys())
      : [editor.getBuffer()]
    const bufferMatches = buffers.map(this.bufferToSubsequenceMatches.bind(this, prefix))

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

    return Promise
      .all(bufferMatches.concat(configMatches))
      .then(this.matchesToSuggestions.bind(
        this,
        buffers,
        currentBuffer,
        lastCursorRow,
        wordsUnderCursors
      ))
  }
}

const applyLocalityBonus = (currentBuffer, lastCursorRow, match) => {
  if (match.buffer === currentBuffer && match.score > 0) {
    let distances = match
      .positions
      .map(pos => Math.abs(pos.row - lastCursorRow))
    let closest = Math.min.apply(Math, distances)
    match.score += Math.floor(11 / (1 + 0.04 * closest))
  }
  return match
}

const compareMatches = (a, b) => {
  if (a.score - b.score === 0) {
    return a.word.length - b.word.length
  }
  return b.score - a.score
}

module.exports = SubsequenceProvider
