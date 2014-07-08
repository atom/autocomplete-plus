exports.triggerAutocompletion = (editor, moveCursor=true) ->
  if moveCursor
    editor.moveCursorToBottom()
    editor.moveCursorToBeginningOfLine()
  editor.insertText "f"

exports.buildIMECompositionEvent = (event, {data, target}={}) ->
  event = new CustomEvent(event, bubbles: true)
  event.data = data
  Object.defineProperty(event, 'target', get: -> target)
  event

exports.buildTextInputEvent = ({data, target}) ->
  event = new CustomEvent('textInput', bubbles: true)
  event.data = data
  Object.defineProperty(event, 'target', get: -> target)
  event
