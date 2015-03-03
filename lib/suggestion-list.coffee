{Emitter, CompositeDisposable} = require 'atom'

module.exports =
class SuggestionList
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
    @subscriptions.remove(@marker)
    @emitter.emit('did-cancel')

  onDidCancel: (fn) ->
    @emitter.on('did-cancel', fn)

  isActive: ->
    @active

  show: (editor) =>
    return if @active
    return unless editor?
    @destroyOverlay()

    if atom.config.get('autocomplete-plus.suggestionListFollows') is 'Cursor'
      @marker = editor.getLastCursor()?.getMarker()
      return unless @marker?
    else
      cursor = editor.getLastCursor()
      return unless cursor?
      position = cursor.getBeginningOfCurrentWordBufferPosition()
      @marker = editor.markBufferPosition(position)
      @subscriptions.add(@marker)

    @overlayDecoration = editor.decorateMarker(@marker, {type: 'overlay', item: this})
    @addKeyboardInteraction()
    @active = true

  hide: =>
    return unless @active
    @destroyOverlay()
    @removeKeyboardInteraction()
    @active = false

  destroyOverlay: =>
    @overlayDecoration?.destroy()
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
