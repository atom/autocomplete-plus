window.triggerAutocompletion = (editor, moveCursor=true) ->
  if moveCursor
    editor.moveCursorToBottom()
    editor.moveCursorToBeginningOfLine()
  editor.insertText "f"

