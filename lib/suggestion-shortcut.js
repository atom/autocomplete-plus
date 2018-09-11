'use babel'

const MIN_INDEX = 1
const MAX_INDEX = 9

const CMD_PREFIX = 'autocomplete-plus:menu:'

/**
 * Create a notation from a key binding
 * e.g. ctrl-a -> ^a
 *      cmd-1  -> ⌘1 on mac
 *             -> ^1 on PC
 */
let keystrokesToNotation = (keystrokes) => {
  return keystrokes
    .replace('cmd', process.platform === 'darwin' ? '⌘' : '^')
    .replace('ctrl', '^')
    .replace('-', '')
}

module.exports = {
  getKeyStrokeNotation: (index) => {
    if (index >= MIN_INDEX && index <= MAX_INDEX) {
      let keys = atom.keymaps.findKeyBindings({command: CMD_PREFIX + index})
      if (keys.length === 1) {
        let {keystrokes} = keys[0]
        return keystrokesToNotation(keystrokes)
      }
    }
  }
}
