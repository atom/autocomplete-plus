'use babel'

const EMPTY_ARRAY = []

import {selectorsMatchScopeChain, buildScopeChainString} from './scope-helpers'
import fuzzaldrin from 'fuzzaldrin'
import fuzzaldrinPlus from 'fuzzaldrin-plus'
import {spliceWithArray} from 'underscore-plus'

class Symbol {
  constructor (text, scopes) {
    this.text = text
    this.scopeChain = buildScopeChainString(scopes)
  }

  matchingTypeForConfig (config) {
    let matchingType = null
    let highestTypePriority = -1
    for (const type of Object.keys(config)) {
      let {selectors, typePriority} = config[type]
      if (selectors == null) continue
      if (typePriority == null) typePriority = 0
      if (typePriority > highestTypePriority && selectorsMatchScopeChain(selectors, this.scopeChain)) {
        matchingType = type
        highestTypePriority = typePriority
      }
    }

    return matchingType
  }
}

export default class SymbolStore {
  constructor (wordRegex) {
    this.wordRegex = wordRegex
    this.linesByBuffer = new Map()
  }

  clear (buffer) {
    if (buffer) {
      this.linesByBuffer.delete(buffer)
    } else {
      this.linesByBuffer.clear()
    }
  }

  symbolsForConfig (config, buffers, prefix, wordUnderCursor, cursorBufferRow, numberOfCursors) {
    this.prefixCache = fuzzaldrinPlus.prepareQuery(prefix)

    const firstLetter = prefix[0].toLowerCase()
    const symbolsByWord = new Map()
    const wordOccurrences = new Map()
    const builtinSymbolsByWord = new Set()

    const suggestions = []
    for (const type of Object.keys(config)) {
      const symbols = config[type].suggestions || EMPTY_ARRAY
      for (const symbol of symbols) {
        const {score} = this.scoreSymbol(prefix, symbol, cursorBufferRow, Number.MAX_VALUE)
        if (score > 0) {
          symbol.replacementPrefix = prefix
          suggestions.push({symbol, score})
          if (symbol.text) {
            builtinSymbolsByWord.add(symbol.text)
          } else if (symbol.snippet) {
            builtinSymbolsByWord.add(symbol.snippet)
          }
        }
      }
    }

    for (const bufferLines of this.linesForBuffers(buffers)) {
      let symbolBufferRow = 0
      for (const lineSymbolsByLetter of bufferLines) {
        const symbols = lineSymbolsByLetter.get(firstLetter) || EMPTY_ARRAY
        for (let symbol of symbols) {
          wordOccurrences.set(symbol.text, (wordOccurrences.get(symbol.text) || 0) + 1)

          const symbolForWord = symbolsByWord.get(symbol.text)
          if (symbolForWord != null) {
            symbolForWord.localityScore = Math.max(
              this.getLocalityScore(cursorBufferRow, symbolBufferRow),
              symbolForWord.localityScore
            )
          } else if (wordUnderCursor === symbol.text && wordOccurrences.get(symbol.text) <= numberOfCursors) {
            continue
          } else {
            const {score, localityScore} = this.scoreSymbol(prefix, symbol, cursorBufferRow, symbolBufferRow)
            if (score > 0) {
              const type = symbol.matchingTypeForConfig(config)
              if (type != null) {
                symbol = {text: symbol.text, type, replacementPrefix: prefix}
                if (!builtinSymbolsByWord.has(symbol.text)) {
                  symbolsByWord.set(symbol.text, {symbol, score, localityScore})
                }
              }
            }
          }
        }

        symbolBufferRow++
      }
    }

    return Array.from(symbolsByWord.values()).concat(suggestions)
  }

  recomputeSymbolsForEditorInBufferRange (editor, start, oldExtent, newExtent) {
    const newEnd = start.row + newExtent.row
    const newLines = []
    // TODO: Remove this conditional once atom/ns-use-display-layers reaches stable and editor.tokenizedBuffer is available
    const tokenizedBuffer = editor.tokenizedBuffer ? editor.tokenizedBuffer : editor.displayBuffer.tokenizedBuffer

    for (let bufferRow = start.row; bufferRow <= newEnd; bufferRow++) {
      const tokenizedLine = tokenizedBuffer.tokenizedLineForRow(bufferRow)
      if (tokenizedLine == null) continue

      const symbolsByLetter = new Map()
      const tokenIterator = tokenizedLine.getTokenIterator()
      while (tokenIterator.next()) {
        const wordsWithinToken = tokenIterator.getText().match(this.wordRegex) || EMPTY_ARRAY
        for (const wordWithinToken of wordsWithinToken) {
          const symbol = new Symbol(wordWithinToken, tokenIterator.getScopes())
          const firstLetter = symbol.text[0].toLowerCase()
          if (!symbolsByLetter.has(firstLetter)) symbolsByLetter.set(firstLetter, [])
          symbolsByLetter.get(firstLetter).push(symbol)
        }
      }

      newLines.push(symbolsByLetter)
    }

    const bufferLines = this.linesForBuffer(editor.getBuffer())
    spliceWithArray(bufferLines, start.row, oldExtent.row + 1, newLines)
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

  setUseStrictMatching (useStrictMatching) {
    this.useStrictMatching = useStrictMatching
  }

  scoreSymbol (prefix, symbol, cursorBufferRow, symbolBufferRow) {
    const text = symbol.text || symbol.snippet
    if (this.useStrictMatching) {
      return this.strictMatchScore(prefix, text)
    } else {
      return this.fuzzyMatchScore(prefix, text, cursorBufferRow, symbolBufferRow)
    }
  }

  strictMatchScore (prefix, text) {
    return {
      score: text.indexOf(prefix) === 0 ? 1 : 0,
      localityScore: 1
    }
  }

  fuzzyMatchScore (prefix, text, cursorBufferRow, symbolBufferRow) {
    if (text == null || prefix[0].toLowerCase() !== text[0].toLowerCase()) {
      return {score: 0, localityScore: 0}
    }

    const fuzzaldrinProvider = this.useAlternateScoring ? fuzzaldrinPlus : fuzzaldrin
    const score = fuzzaldrinProvider.score(text, prefix, { preparedQuery: this.prefixCache })
    const localityScore = this.getLocalityScore(cursorBufferRow, symbolBufferRow)
    return {score, localityScore}
  }

  getLocalityScore (cursorBufferRow, symbolBufferRow) {
    if (!this.useLocalityBonus) {
      return 1
    }

    const rowDifference = Math.abs(symbolBufferRow - cursorBufferRow)
    if (this.useAlternateScoring) {
      // Between 1 and 1 + strength. (here between 1.0 and 2.0)
      // Avoid a pow and a branching max.
      // 25 is the number of row where the bonus is 3/4 faded away.
      // strength is the factor in front of fade*fade. Here it is 1.0
      const fade = 25.0 / (25.0 + rowDifference)
      return 1.0 + fade * fade
    } else {
      // Will be between 1 and ~2.75
      return 1 + Math.max(-Math.pow(0.2 * rowDifference - 3, 3) / 25 + 0.5, 0)
    }
  }
}
