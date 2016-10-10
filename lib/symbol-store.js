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
    for (let type of Object.keys(config)) {
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
    this.prefixCache = fuzzaldrinPlus.prepQuery(prefix)

    let firstLetter = prefix[0].toLowerCase()
    let symbolsByWord = new Map()
    let wordOccurrences = new Map()
    let builtinSymbolsByWord = new Set()

    let suggestions = []
    for (let type of Object.keys(config)) {
      let symbols = config[type].suggestions || EMPTY_ARRAY
      for (let symbol of symbols) {
        let {score} = this.scoreSymbol(prefix, symbol, cursorBufferRow, Number.MAX_VALUE)
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

    for (let bufferLines of this.linesForBuffers(buffers)) {
      let symbolBufferRow = 0
      for (let lineSymbolsByLetter of bufferLines) {
        let symbols = lineSymbolsByLetter.get(firstLetter) || EMPTY_ARRAY
        for (let symbol of symbols) {
          wordOccurrences.set(symbol.text, (wordOccurrences.get(symbol.text) || 0) + 1)

          let symbolForWord = symbolsByWord.get(symbol.text)
          if (symbolForWord != null) {
            symbolForWord.localityScore = Math.max(
              this.getLocalityScore(cursorBufferRow, symbolBufferRow),
              symbolForWord.localityScore
            )
          } else if (wordUnderCursor === symbol.text && wordOccurrences.get(symbol.text) <= numberOfCursors) {
            continue
          } else {
            let {score, localityScore} = this.scoreSymbol(prefix, symbol, cursorBufferRow, symbolBufferRow)
            if (score > 0) {
              let type = symbol.matchingTypeForConfig(config)
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
    let newEnd = start.row + newExtent.row
    let newLines = []
    // TODO: Remove this conditional once atom/ns-use-display-layers reaches stable and editor.tokenizedBuffer is available
    let tokenizedBuffer = editor.tokenizedBuffer ? editor.tokenizedBuffer : editor.displayBuffer.tokenizedBuffer

    for (let bufferRow = start.row; bufferRow <= newEnd; bufferRow++) {
      let tokenizedLine = tokenizedBuffer.tokenizedLineForRow(bufferRow)
      if (tokenizedLine == null) continue

      let symbolsByLetter = new Map()
      let tokenIterator = tokenizedLine.getTokenIterator()
      while (tokenIterator.next()) {
        let wordsWithinToken = tokenIterator.getText().match(this.wordRegex) || EMPTY_ARRAY
        for (let wordWithinToken of wordsWithinToken) {
          let symbol = new Symbol(wordWithinToken, tokenIterator.getScopes())
          let firstLetter = symbol.text[0].toLowerCase()
          if (!symbolsByLetter.has(firstLetter)) symbolsByLetter.set(firstLetter, [])
          symbolsByLetter.get(firstLetter).push(symbol)
        }
      }

      newLines.push(symbolsByLetter)
    }

    let bufferLines = this.linesForBuffer(editor.getBuffer())
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
    let text = symbol.text || symbol.snippet
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

    let fuzzaldrinProvider = this.useAlternateScoring ? fuzzaldrinPlus : fuzzaldrin
    let score = fuzzaldrinProvider.score(text, prefix, this.prefixCache)
    let localityScore = this.getLocalityScore(cursorBufferRow, symbolBufferRow)
    return {score, localityScore}
  }

  getLocalityScore (cursorBufferRow, symbolBufferRow) {
    if (!this.useLocalityBonus) {
      return 1
    }

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
      return 1 + Math.max(-Math.pow(0.2 * rowDifference - 3, 3) / 25 + 0.5, 0)
    }
  }
}
