# Public: A provider provides an interface to the autocomplete package. Third-party
# packages can register providers which will then be used to generate the
# suggestions list.
module.exports =
class Provider
  wordRegex: /\b\w*[a-zA-Z_-]+\w*\b/g

  constructor: (@editorView) ->
    {@editor} = editorView
    @initialize.apply this, arguments

  # Public: An initializer for subclasses
  initialize: ->
    return

  # Public: Defines whether the words returned at {::buildWordList} should be added to
  # the default suggestions or should be displayed exclusively
  exclusive: false

  # Public: Gets called when the document has been changed. Returns an array with
  # suggestions. If `exclusive` is set to true and this method returns suggestions,
  # the suggestions will be the only ones that are displayed.
  #
  # Returns An {Array} of suggestions.
  buildSuggestions: ->
    throw new Error "Subclass must implement a buildWordList(prefix) method"

  # Public: Gets called when a suggestion has been confirmed by the user. Return true
  # to replace the word with the suggestion. Return false if you want to handle
  # the behavior yourself.
  #
  # suggestion - The {Suggestion} to confirm
  #
  # Returns {Boolean} indicating whether the suggestion should be automatically replaced.
  confirm: (suggestion) ->
    return true

  # Public: Finds and returns the content before the current cursor position
  #
  # selection - The {Selection} for the current cursor position
  #
  # Returns {String} with the prefix of the {Selection}
  prefixOfSelection: (selection) ->
    selectionRange = selection.getBufferRange()
    lineRange = [[selectionRange.start.row, 0], [selectionRange.end.row, @editor.lineTextForBufferRow(selectionRange.end.row).length]]
    prefix = ""
    @editor.getBuffer().scanInRange @wordRegex, lineRange, ({match, range, stop}) ->
      stop() if range.start.isGreaterThan(selectionRange.end)

      if range.intersectsWith(selectionRange)
        prefixOffset = selectionRange.start.column - range.start.column
        prefix = match[0][0...prefixOffset] if range.start.isLessThan(selectionRange.start)

    return prefix
