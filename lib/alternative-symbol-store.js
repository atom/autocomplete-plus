"use babel"

import {selectorsMatchScopeChain, buildScopeChainString} from './scope-helpers'

class Symbol {
  constructor (text, scopes) {
    this.text = text
    this.scopeChain = buildScopeChainString(scopes)
  }

  appliesToConfig (config) {
    let applies = false
    let typePriority = -1
    for (let type of Object.keys(config)) {
      let options = config[type]
      if (options.selector == null) continue
      if (options.typePriority > typePriority && selectorsMatchScopeChain(options.selector, this.scopeChain)) {
        applies = true
        typePriority = options.typePriority
      }
    }

    return applies
  }
}

export default class SymbolStore {
  constructor (wordRegex) {
    this.wordRegex = wordRegex
    this.linesByBuffer = new WeakMap
  }

  symbolsForConfig (config, buffer, wordUnderCursor, numberOfCursors) {
    let symbolsByWord = new Map()
    let bufferRow = 0
    for (let symbols of this.linesForBuffer(buffer)) {
      for (let symbol of symbols) {
        let symbolForWord = symbolsByWord.get(symbol.text)
        if (symbolForWord != null) {
          symbolForWord.bufferRows.push(bufferRow)
        } else if (symbol.appliesToConfig(config) && wordUnderCursor !== symbol.text) {
          symbolForWord = {text: symbol.text, bufferRows: [bufferRow]}
          symbolsByWord.set(symbol.text, symbolForWord)
        }
      }

      bufferRow++
    }

    let suggestions = []
    for (let type of Object.keys(config)) {
      let options = config[type]
      if (options.suggestions) suggestions.push(options.suggestions)
    }

    return Array.from(symbolsByWord.values()).concat(suggestions)
  }

  splice (editor, oldRange, newRange) {
    let newLines = this.computeSymbolsInRange(editor, newRange)
    this.linesForBuffer(editor.buffer).splice(oldRange.start.row, oldRange.getExtent().row, ...newLines)
  }

  computeSymbolsInRange (editor, range) {
    let lines = []
    for (var bufferRow = range.start.row; bufferRow < range.end.row; bufferRow++) {
      let tokenizedLine = editor.displayBuffer.tokenizedBuffer.tokenizedLineForRow(bufferRow)
      if (tokenizedLine == null) continue

      let symbols = []
      let tokenIterator = tokenizedLine.getTokenIterator()
      while (tokenIterator.next()) {
        let wordsWithinToken = tokenIterator.getText().match(this.wordRegex) || []
        for (let wordWithinToken of wordsWithinToken) {
          symbols.push(new Symbol(wordWithinToken, tokenIterator.getScopes()))
        }
      }
      lines.push(symbols)
    }
    return lines
  }

  linesForBuffer (buffer) {
    if (!this.linesByBuffer.has(buffer)) {
      this.linesByBuffer.set(buffer, [])
    }

    return this.linesByBuffer.get(buffer)
  }
}
