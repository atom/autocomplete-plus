"use babel"

const EMPTY_ARRAY = []

import {selectorsMatchScopeChain, buildScopeChainString} from './scope-helpers'
import fuzzaldrin from 'fuzzaldrin'
import fuzzaldrinPlus from 'fuzzaldrin-plus'

class Symbol {
  constructor (text, scopes) {
    this.text = text
    this.scopeChain = buildScopeChainString(scopes)
  }

  matchingTypeForConfig (config) {
    let matchingType = null
    let typePriority = -1
    for (let type of Object.keys(config)) {
      let options = config[type]
      if (options.selectors == null) continue
      if (options.typePriority > typePriority && selectorsMatchScopeChain(options.selectors, this.scopeChain)) {
        matchingType = type
        typePriority = options.typePriority
      }
    }

    return matchingType
  }
}

export default class SymbolStore {
  constructor (wordRegex) {
    this.wordRegex = wordRegex
    this.linesByBuffer = new Map
  }

  clear (buffer) {
    if (buffer) {
      this.linesByBuffer.delete(buffer)
    } else {
      this.linesByBuffer.clear()
    }
  }

  symbolsForConfig (config, buffers, prefix, wordUnderCursor, cursorBufferRow, numberOfCursors) {
    this.prefixCache = fuzzaldrinPlus.prepQuery(prefix)

    let startingLetter = prefix[0].toLowerCase()
    let symbolsByWord = new Map()
    let countsByWord = new Map()
    for (let bufferLines of this.linesForBuffers(buffers)) {
      let symbolBufferRow = 0
      for (let bufferLine of bufferLines) {
        let symbolsByLetter = bufferLine[0].get(startingLetter) || EMPTY_ARRAY
        for (let symbol of symbolsByLetter) {
          countsByWord.set(symbol.text, (countsByWord.get(symbol.text) || 0) + 1)

          let symbolForWord = symbolsByWord.get(symbol.text)
          if (symbolForWord != null) {
            symbolForWord.localityScore = Math.max(
              this.getLocalityScore(cursorBufferRow, symbolBufferRow),
              symbolForWord.localityScore
            )
          } else if (wordUnderCursor === symbol.text && countsByWord.get(symbol.text) <= numberOfCursors) {
            continue
          } else {
            let {score, localityScore} = this.scoreSymbol(prefix, symbol, cursorBufferRow, symbolBufferRow)
            if (score > 0) {
              let type = symbol.matchingTypeForConfig(config)
              if (type) {
                symbol = {text: symbol.text, type, replacementPrefix: prefix}
                symbolsByWord.set(symbol.text, {symbol, score, localityScore})
              }
            }
          }
        }

        symbolBufferRow++
      }
    }

    let suggestions = []
    for (let type of Object.keys(config)) {
      let options = config[type].suggestions || EMPTY_ARRAY
      for (let suggestion of suggestions) {
        let {score, localityScore} = this.scoreSymbol(prefix, suggestion, cursorBufferRow, Number.MAX_VALUE)
        if (score > 0) {
          suggestion.replacementPrefix = prefix
          suggestions.push({symbol: suggestion, score})
        }
      }
    }

    return Array.from(symbolsByWord.values()).concat(suggestions)
  }

  splice (editor, oldRange, newRange) {
    let symbolLines = this.linesForBuffer(editor.getBuffer())
    let newLines = []
    for (var bufferRow = newRange.start.row; bufferRow < newRange.end.row; bufferRow++) {
      let tokenizedLine = editor.displayBuffer.tokenizedBuffer.tokenizedLineForRow(bufferRow)
      if (tokenizedLine == null) continue

      let symbolsByLetter = new Map
      let symbols = []
      let tokenIterator = tokenizedLine.getTokenIterator()
      while (tokenIterator.next()) {
        let wordsWithinToken = tokenIterator.getText().match(this.wordRegex) || EMPTY_ARRAY
        for (let wordWithinToken of wordsWithinToken) {
          let symbol = new Symbol(wordWithinToken, tokenIterator.getScopes())
          symbols.push(symbol)

          let symbolsStartingWithLetter = symbolsByLetter.get(symbol.text[0]) || []
          symbolsStartingWithLetter.push(symbol)
          symbolsByLetter.set(symbol.text[0].toLowerCase(), symbolsStartingWithLetter)
        }
      }

      symbols.unshift(symbolsByLetter)
      newLines.push(symbols)
    }

    this.linesForBuffer(editor.buffer).splice(oldRange.start.row, oldRange.getExtent().row, ...newLines)
  }

  linesForBuffers (buffers) {
    buffers = buffers || Array.from(this.linesByBuffer.keys())
    return buffers.map(buffer => this.linesForBuffer(buffer))
  }

  linesForBuffer (buffer) {
    if (!this.linesByBuffer.has(buffer)) {
      this.linesByBuffer.set(buffer, [])
    }

    return this.linesByBuffer.get(buffer)
  }

  setUseAlternateScoring (useAlternateScoring) {
    this.useAlternateScoring = useAlternateScoring
  }

  setUseLocalityBonus (useLocalityBonus) {
    this.useLocalityBonus = useLocalityBonus
  }

  scoreSymbol (prefix, symbol, cursorBufferRow, symbolBufferRow) {
    let fuzzaldrinProvider
    if (this.useAlternateScoring) {
      fuzzaldrinProvider = fuzzaldrinPlus
    }
    else {
      fuzzaldrinProvider = fuzzaldrin
    }

    let text = symbol.snippet || symbol.text
    if (text != null && prefix[0].toLowerCase() === text[0].toLowerCase()) {
      let score = fuzzaldrinProvider.score(text, prefix, this.prefixCache)
      let localityScore = this.getLocalityScore(cursorBufferRow, symbolBufferRow)

      return {score, localityScore}
    } else {
      return {score: 0, localityScore: 0}
    }
  }

  getLocalityScore (cursorBufferRow, symbolBufferRow) {
    let rowDifference = Math.abs(symbolBufferRow - cursorBufferRow)
    if (this.useAlternateScoring) {
      // Between 1 and 1 + strength. (here between 1.0 and 2.0)
      // Avoid a pow and a branching max.
      // 25 is the number of row where the bonus is 3/4 faded away.
      // strength is the factor in front of fade*fade. Here it is 1.0
      let fade = 25.0 / (25.0 + rowDifference)
      return 1.0 + fade * fade
    } else {
      // Will be between 1 and ~2.75
      return 1 + Math.max(-Math.pow(.2 * rowDifference - 3, 3) / 25 + .5, 0)
    }
  }
}
