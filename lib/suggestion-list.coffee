{Emitter, CompositeDisposable} = require 'atom'

module.exports =
class SuggestionList
  wordPrefixRegex: /^[\w-]/

  constructor: ->
    @active = false
    @emitter = new Emitter
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.commands.add 'atom-text-editor.autocomplete-active',
      'autocomplete-plus:confirm': @confirmSelection,
      'autocomplete-plus:cancel': @cancel
      'core:move-up': (event) =>
        if @isActive() and @items?.length > 1
          @selectPrevious()
          event.stopImmediatePropagation()
      'core:move-down': (event) =>
        if @isActive() and @items?.length > 1
          @selectNext()
          event.stopImmediatePropagation()

  addKeyboardInteraction: ->
    @removeKeyboardInteraction()
    keys =
      'escape': 'autocomplete-plus:cancel'

    completionKey = atom.config.get('autocomplete-plus.confirmCompletion') or ''

    keys['tab'] = 'autocomplete-plus:confirm' if completionKey.indexOf('tab') > -1
    keys['enter'] = 'autocomplete-plus:confirm' if completionKey.indexOf('enter') > -1

    @keymaps = atom.keymaps.add('atom-text-editor.autocomplete-active', {'atom-text-editor.autocomplete-active': keys})
    @subscriptions.add(@keymaps)

  removeKeyboardInteraction: ->
    @keymaps?.dispose()
    @keymaps = null
    @subscriptions.remove(@keymaps)

  confirmSelection: =>
    @emitter.emit('did-confirm-selection')

  onDidConfirmSelection: (fn) ->
    @emitter.on('did-confirm-selection', fn)

  confirm: (match) =>
    @emitter.emit('did-confirm', match)

  onDidConfirm: (fn) ->
    @emitter.on('did-confirm', fn)

  selectNext: ->
    @emitter.emit('did-select-next')

  onDidSelectNext: (fn) ->
    @emitter.on('did-select-next', fn)

  selectPrevious: ->
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
      marker = @suggestionMarker = editor.markBufferRange([bufferPosition, bufferPosition])
      @overlayDecoration = editor.decorateMarker(marker, {type: 'overlay', item: this, position: 'tail'})
      @addKeyboardInteraction()
      @active = true

  showAtCursorPosition: (editor) =>
    return if @active or not editor?
    @destroyOverlay()

    if marker = editor.getLastCursor()?.getMarker()
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
