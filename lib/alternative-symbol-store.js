"use babel"

const EMPTY_ARRAY = []
import {selectorsMatchScopeChain, buildScopeChainString} from './scope-helpers'

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
    this.linesByBuffer = new WeakMap
  }

  symbolsForConfig (config, buffers, prefix, wordUnderCursor, numberOfCursors) {
    let symbolsByWord = new Map()
    let countsByWord = new Map()
    for (let bufferLines of this.linesForBuffers(buffers)) {
      let bufferRow = 0
      for (let symbols of bufferLines) {
        for (let symbol of symbols) {
          countsByWord.set((countsByWord.get(symbol.text) || 0) + 1)

          let symbolForWord = symbolsByWord.get(symbol.text)
          if (symbolForWord != null) {
            symbolForWord.bufferRows.push(bufferRow)
          } else if (wordUnderCursor === symbol.text && countsByWord.get(symbol.text) <= numberOfCursors) {
            continue
          } else if (prefix[0].toLowerCase() === symbol.text[0].toLowerCase()) {
            let type = symbol.matchingTypeForConfig(config)
            if (type) {
              symbolForWord = {text: symbol.text, bufferRows: [bufferRow], type: type}
              symbolsByWord.set(symbol.text, symbolForWord)
            }
          }
        }

        bufferRow++
      }
    }

    let suggestions = []
    for (let type of Object.keys(config)) {
      let options = config[type]
      if (options.suggestions) suggestions.push(options.suggestions)
    }

    return Array.from(symbolsByWord.values()).concat(suggestions)
  }

  splice (editor, oldRange, newRange) {
    let newLines = []
    for (var bufferRow = range.start.row; bufferRow < range.end.row; bufferRow++) {
      let tokenizedLine = editor.displayBuffer.tokenizedBuffer.tokenizedLineForRow(bufferRow)
      if (tokenizedLine == null) continue

      let symbols = []
      let tokenIterator = tokenizedLine.getTokenIterator()
      while (tokenIterator.next()) {
        let wordsWithinToken = tokenIterator.getText().match(this.wordRegex) || EMPTY_ARRAY
        for (let wordWithinToken of wordsWithinToken) {
          symbols.push(new Symbol(wordWithinToken, tokenIterator.getScopes()))
        }
      }
      newLines.push(symbols)
    }

    this.linesForBuffer(editor.buffer).splice(oldRange.start.row, oldRange.getExtent().row, ...newLines)
  }

  linesForBuffers (buffers = this.linesByBuffer.keys()) {
    let buffersLines = []
    for (let buffer of buffers) {
      if (!this.linesByBuffer.has(buffer)) {
        this.linesByBuffer.set(buffer, [])
      }

      buffersLines.push(this.linesByBuffer.get(buffer))
    }

    return buffersLines
  }
}
