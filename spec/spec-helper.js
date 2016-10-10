'use babel'
/* eslint-env jasmine */

let completionDelay = 100

beforeEach(function () {
  spyOn(atom.views, 'readDocument').andCallFake(fn => fn())
  spyOn(atom.views, 'updateDocument').andCallFake(fn => fn())
  atom.config.set('autocomplete-plus.defaultProvider', 'Symbol')
  atom.config.set('autocomplete-plus.minimumWordLength', 1)
  atom.config.set('autocomplete-plus.suggestionListFollows', 'Word')
  atom.config.set('autocomplete-plus.useCoreMovementCommands', true)
  return atom.config.set('autocomplete-plus.includeCompletionsFromAllBuffers', false)
})

export function triggerAutocompletion (editor, moveCursor = true, char = 'f') {
  if (moveCursor) {
    editor.moveToBottom()
    editor.moveToBeginningOfLine()
  }
  editor.insertText(char)
  return exports.waitForAutocomplete()
}

export function waitForAutocomplete () {
  advanceClock(completionDelay)
  return waitsFor('autocomplete to show', done =>
    setImmediate(function () {
      advanceClock(10)
      return setImmediate(function () {
        advanceClock(10)
        return done()
      })
    })

  )
}

export function buildIMECompositionEvent (event, {data, target} = {}) {
  event = new CustomEvent(event, {bubbles: true})
  event.data = data
  Object.defineProperty(event, 'target', {get () { return target }})
  return event
}

export function buildTextInputEvent ({data, target}) {
  let event = new CustomEvent('textInput', {bubbles: true})
  event.data = data
  Object.defineProperty(event, 'target', {get () { return target }})
  return event
}
