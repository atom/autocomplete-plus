{Emitter, CompositeDisposable} = require 'atom'

module.exports =
class SuggestionList
  wordPrefixRegex: /^[\w-]/

  constructor: ->
    @active = false
    @emitter = new Emitter
    @subscriptions = new CompositeDisposable
    # Allow keyboard navigation of the suggestion list
    @subscriptions.add(atom.commands.add 'atom-text-editor.autocomplete-active',
      'autocomplete-plus:confirm': @confirmSelection,
      'autocomplete-plus:select-next': @selectNext,
      'autocomplete-plus:select-previous': @selectPrevious,
      'autocomplete-plus:cancel': @cancel
    )

  addKeyboardInteraction: ->
    @removeKeyboardInteraction()
    keys =
      'escape': 'autocomplete-plus:cancel'

    completionKey = atom.config.get('autocomplete-plus.confirmCompletion') or ''
    navigationKey = atom.config.get('autocomplete-plus.navigateCompletions') or ''

    keys['tab'] = 'autocomplete-plus:confirm' if completionKey.indexOf('tab') > -1
    keys['enter'] = 'autocomplete-plus:confirm' if completionKey.indexOf('enter') > -1

    if @items?.length > 1 and navigationKey is 'up,down'
      keys['up'] =  'autocomplete-plus:select-previous'
      keys['down'] = 'autocomplete-plus:select-next'
    else
      keys['ctrl-n'] = 'autocomplete-plus:select-next'
      keys['ctrl-p'] = 'autocomplete-plus:select-previous'

    @keymaps = atom.keymaps.add('atom-text-editor.autocomplete-active', {'atom-text-editor.autocomplete-active': keys})

    @subscriptions.add(@keymaps)

  removeKeyboardInteraction: ->
    @keymaps?.dispose()
    @subscriptions.remove(@keymaps)

  confirmSelection: =>
    @emitter.emit('did-confirm-selection')

  onDidConfirmSelection: (fn) ->
    @emitter.on('did-confirm-selection', fn)

  confirm: (match) =>
    @emitter.emit('did-confirm', match)

  onDidConfirm: (fn) ->
    @emitter.on('did-confirm', fn)

  selectNext: =>
    @emitter.emit('did-select-next')

  onDidSelectNext: (fn) ->
    @emitter.on('did-select-next', fn)

  selectPrevious: =>
    @emitter.emit('did-select-previous')

  onDidSelectPrevious: (fn) ->
    @emitter.on('did-select-previous', fn)

  cancel: =>
    @emitter.emit('did-cancel')

  onDidCancel: (fn) ->
    @emitter.on('did-cancel', fn)

  isActive: ->
    @active

  show: (editor, options) =>
    if atom.config.get('autocomplete-plus.suggestionListFollows') is 'Cursor'
      @showAtCursorPosition(editor, options)
    else
      @showAtBeginningOfPrefix(editor, options)

  showAtBeginningOfPrefix: (editor, {prefix}) =>
    return unless editor?

    bufferPosition = editor.getCursorBufferPosition()
    bufferPosition = bufferPosition.translate([0, -prefix.length]) if @wordPrefixRegex.test(prefix)

    if @active
      unless bufferPosition.isEqual(@displayBufferPosition)
        @displayBufferPosition = bufferPosition
        @suggestionMarker?.setBufferRange([bufferPosition, bufferPosition])
    else
      @destroyOverlay()
      @displayBufferPosition = bufferPosition
      marker = @suggestionMarker = editor.markBufferPosition(bufferPosition)

      # HACK: When the marker is at the cursor position, it will move with the
      # cursor, but we want it planted to the buffer position at the beginning
      # of the prefix. When the marker moves forward, this callback will move it
      # back to the correct position.
      marker.onDidChange ({newHeadBufferPosition}) =>
        if newHeadBufferPosition.column > @displayBufferPosition.column
          marker.setBufferRange([@displayBufferPosition, @displayBufferPosition])

      @overlayDecoration = editor.decorateMarker(marker, {type: 'overlay', item: this})
      @addKeyboardInteraction()
      @active = true

  showAtCursorPosition: (editor) =>
    return if @active or not editor?
    @destroyOverlay()

    marker = editor.getLastCursor()?.getMarker()
    if marker?
      @overlayDecoration = editor.decorateMarker(marker, {type: 'overlay', item: this})
      @addKeyboardInteraction()
      @active = true

  hide: =>
    return unless @active
    @destroyOverlay()
    @removeKeyboardInteraction()
    @active = false

  destroyOverlay: =>
    if @suggestionMarker?
      @suggestionMarker.destroy()
    else
      @overlayDecoration?.destroy()
    @suggestionMarker = undefined
    @overlayDecoration = undefined

  changeItems: (@items) ->
    @emitter.emit('did-change-items', items)

  onDidChangeItems: (fn) ->
    @emitter.on('did-change-items', fn)

  # Public: Clean up, stop listening to events
  dispose: ->
    @subscriptions.dispose()
    @emitter.emit('did-dispose')
    @emitter.dispose()

  onDidDispose: (fn) ->
    @emitter.on('did-dispose', fn)
