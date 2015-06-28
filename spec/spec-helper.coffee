completionDelay = 100

beforeEach ->
  spyOn(atom.views, 'readDocument').andCallFake (fn) -> fn()
  spyOn(atom.views, 'updateDocument').andCallFake (fn) -> fn()
  atom.config.set('autocomplete-plus.defaultProvider', 'Symbol')
  atom.config.set('autocomplete-plus.minimumWordLength', 1)
  atom.config.set('autocomplete-plus.suggestionListFollows', 'Word')
  atom.config.set('autocomplete-plus.includeCompletionsFromAllBuffers', false)

exports.triggerAutocompletion = (editor, moveCursor = true, char = 'f') ->
  if moveCursor
    editor.moveToBottom()
    editor.moveToBeginningOfLine()
  editor.insertText(char)
  exports.waitForAutocomplete()

exports.waitForAutocomplete = ->
  advanceClock(completionDelay)
  waitsFor 'autocomplete to show', (done) ->
    setImmediate ->
      advanceClock(10)
      setImmediate ->
        advanceClock(10)
        done()

exports.buildIMECompositionEvent = (event, {data, target} = {}) ->
  event = new CustomEvent(event, {bubbles: true})
  event.data = data
  Object.defineProperty(event, 'target', {get: -> target})
  event

exports.buildTextInputEvent = ({data, target}) ->
  event = new CustomEvent('textInput', {bubbles: true})
  event.data = data
  Object.defineProperty(event, 'target', {get: -> target})
  event
