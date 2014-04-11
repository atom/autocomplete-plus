###
 * A provider provides an interface to the autocomplete+ package. Third-party
 * packages can register providers which will then be used to generate the
 * suggestions list.
###

module.exports =
class Provider
  wordRegex: /\b\w*[a-zA-Z_]\w*\b/g
  constructor: (@editorView) ->
    {@editor} = editorView
    @initialize.apply this, arguments

  ###
   * An an initializer for subclasses
   * @private
  ###
  initialize: ->
    return

  ###
   * Defines whether the words returned at #buildWordList() should be added to
   * the default suggestions or should be displayed exclusively
   * @type {Boolean}
  ###
  exclusive: false

  ###
   * Gets called when the document has been changed. Returns an array with
   * suggestions. If `exclusive` is set to true and this method returns suggestions,
   * the suggestions will be the only ones that are displayed.
   * @return {Array}
   * @public
  ###
  buildSuggestions: ->
    throw new Error "Subclass must implement a buildWordList(prefix) method"

  ###
   * Gets called when a suggestion has been confirmed by the user. Return true
   * to replace the word with the suggestion. Return false if you want to handle
   * the behavior yourself.
   * @param  {Suggestion} suggestion
   * @return {Boolean}
   * @public
  ###
  confirm: (suggestion) ->
    return true

  ###
   * Finds and returns the content before the current cursor position
   * @param {Selection} selection
   * @return {String}
   * @private
  ###
  prefixOfSelection: (selection) ->
    selectionRange = selection.getBufferRange()
    lineRange = [[selectionRange.start.row, 0], [selectionRange.end.row, @editor.lineLengthForBufferRow(selectionRange.end.row)]]
    prefix = ""
    @editor.getBuffer().scanInRange @wordRegex, lineRange, ({match, range, stop}) ->
      stop() if range.start.isGreaterThan(selectionRange.end)

      if range.intersectsWith(selectionRange)
        prefixOffset = selectionRange.start.column - range.start.column
        prefix = match[0][0...prefixOffset] if range.start.isLessThan(selectionRange.start)

    return prefix
