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

function waitForAutocompletePromise (editor) {
  const editorView = atom.views.getView(editor)

  return conditionPromise(
    () => editorView.querySelectorAll('.autocomplete-plus').length === 1
  )
}

let triggerAutocompletion = (editor, moveCursor = true, char = 'f') => {
  if (moveCursor) {
    editor.moveToBottom()
    editor.moveToBeginningOfLine()
  }
  editor.insertText(char)
  waitForAutocomplete()
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

async function conditionPromise (condition) {
  const startTime = Date.now()

  while (true) {
    await timeoutPromise(100)

    if (await condition()) {
      return
    }

    if (Date.now() - startTime > 5000) {
      throw new Error('Timed out waiting on condition')
    }
  }
}

function timeoutPromise (timeout) {
  return new Promise(function (resolve) {
    setTimeout(resolve, timeout)
  })
}

module.exports = {
  conditionPromise,
  triggerAutocompletion,
  waitForAutocomplete,
  waitForAutocompletePromise,
  buildIMECompositionEvent,
  buildTextInputEvent,
  waitForDeferredSuggestions
}
