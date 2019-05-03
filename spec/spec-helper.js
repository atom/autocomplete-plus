/* eslint-env jasmine */

let completionDelay = 100

beforeEach(() => {
  spyOn(atom.views, 'readDocument').andCallFake(fn => fn())
  spyOn(atom.views, 'updateDocument').andCallFake(fn => fn())
  atom.config.set('autocomplete-plus.minimumWordLength', 1)
  atom.config.set('autocomplete-plus.suggestionListFollows', 'Word')
  atom.config.set('autocomplete-plus.useCoreMovementCommands', true)
  atom.config.set('autocomplete-plus.includeCompletionsFromAllBuffers', false)
})

let triggerAutocompletion = (editor, moveCursor = true, char = 'f') => {
  if (moveCursor) {
    editor.moveToBottom()
    editor.moveToBeginningOfLine()
  }
  editor.insertText(char)
  module.exports.waitForAutocomplete()
}

let waitForAutocomplete = () => {
  advanceClock(completionDelay)
  return waitsFor('autocomplete to show', (done) => {
    setImmediate(() => {
      advanceClock(10)
      setImmediate(() => {
        advanceClock(10)
        done()
      })
    })
  })
}

let waitForDeferredSuggestions = (editorView, totalSuggestions) => {
  waitsFor(() => {
    return editorView.querySelector('.autocomplete-plus autocomplete-suggestion-list .suggestion-list-scroller')
  })

  runs(() => {
    const scroller = editorView.querySelector('.autocomplete-plus autocomplete-suggestion-list .suggestion-list-scroller')
    scroller.scrollTo(0, 100)
    scroller.scrollTo(0, 0)
  })

  waitsFor(() => {
    return editorView.querySelectorAll('.autocomplete-plus li').length === totalSuggestions
  })
}

let buildIMECompositionEvent = (event, {data, target} = {}) => {
  event = new CustomEvent(event, {bubbles: true})
  event.data = data
  Object.defineProperty(event, 'target', {get () { return target }})
  return event
}

let buildTextInputEvent = ({data, target}) => {
  let event = new CustomEvent('textInput', {bubbles: true})
  event.data = data
  Object.defineProperty(event, 'target', {get () { return target }})
  return event
}

module.exports = {
  triggerAutocompletion,
  waitForAutocomplete,
  buildIMECompositionEvent,
  buildTextInputEvent,
  waitForDeferredSuggestions
}
