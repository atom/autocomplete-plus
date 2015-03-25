composeChangedLines = (editor, {oldRange, oldText, newRange, newText}) ->
  startRow = Math.min(oldRange.start.row, newRange.start.row)
  endRow = Math.max(oldRange.end.row, newRange.end.row)

  newRangeStartIndex = linearIndexInRowRange(editor, newRange.start, startRow, endRow)
  newRangeEndIndex = linearIndexInRowRange(editor, newRange.end, startRow, endRow)

  newLines = editor.getTextInBufferRange([[startRow, 0], [endRow, 10000]])
  oldLines = newLines.slice(0, newRangeStartIndex) + oldText + newLines.slice(newRangeEndIndex)

  {oldLines, newLines}

linearIndexInRowRange = (editor, bufferPosition, startRow, endRow) ->
  buffer = editor.getBuffer()
  linearIndex = bufferPosition.column
  rowPointer = startRow
  while rowPointer < bufferPosition.row and rowPointer <= endRow
    linearIndex += buffer.lineLengthForRow(rowPointer)
    rowPointer++
  linearIndex

module.exports = {composeChangedLines}
