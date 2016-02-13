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
      'autocomplete-plus:confirmIfNonDefault': @confirmSelectionIfNonDefault,
      'autocomplete-plus:cancel': @cancel
    @subscriptions.add atom.config.observe 'autocomplete-plus.useCoreMovementCommands', => @bindToMovementCommands()

  bindToMovementCommands: ->
    useCoreMovementCommands = atom.config.get('autocomplete-plus.useCoreMovementCommands')
    commandNamespace = if useCoreMovementCommands then 'core' else 'autocomplete-plus'

    commands = {}
    commands["#{commandNamespace}:move-up"] = (event) =>
      if @isActive() and @items?.length > 1
        @selectPrevious()
        event.stopImmediatePropagation()
    commands["#{commandNamespace}:move-down"] = (event) =>
      if @isActive() and @items?.length > 1
        @selectNext()
        event.stopImmediatePropagation()
    commands["#{commandNamespace}:page-up"] = (event) =>
      if @isActive() and @items?.length > 1
        @selectPageUp()
        event.stopImmediatePropagation()
    commands["#{commandNamespace}:page-down"] = (event) =>
      if @isActive() and @items?.length > 1
        @selectPageDown()
        event.stopImmediatePropagation()
    commands["#{commandNamespace}:move-to-top"] = (event) =>
      if @isActive() and @items?.length > 1
        @selectTop()
        event.stopImmediatePropagation()
    commands["#{commandNamespace}:move-to-bottom"] = (event) =>
      if @isActive() and @items?.length > 1
        @selectBottom()
        event.stopImmediatePropagation()

    @movementCommandSubscriptions?.dispose()
    @movementCommandSubscriptions = new CompositeDisposable
    @movementCommandSubscriptions.add atom.commands.add('atom-text-editor.autocomplete-active', commands)

  addKeyboardInteraction: ->
    @removeKeyboardInteraction()
    completionKey = atom.config.get('autocomplete-plus.confirmCompletion') or ''

    keys = {}
    keys['tab']   = 'autocomplete-plus:confirm' if completionKey.indexOf('tab') > -1
    if completionKey.indexOf('enter') > -1
      if completionKey.indexOf('always') > -1
        keys['enter'] = 'autocomplete-plus:confirmIfNonDefault'
      else
        keys['enter'] = 'autocomplete-plus:confirm'

    @keymaps = atom.keymaps.add('atom-text-editor.autocomplete-active', {'atom-text-editor.autocomplete-active': keys})
    @subscriptions.add(@keymaps)

  removeKeyboardInteraction: ->
    @keymaps?.dispose()
    @keymaps = null
    @subscriptions.remove(@keymaps)

  ###
  Section: Event Triggers
  ###

  cancel: =>
    @emitter.emit('did-cancel')

  confirm: (match) =>
    @emitter.emit('did-confirm', match)

  confirmSelection: =>
    @emitter.emit('did-confirm-selection')

  confirmSelectionIfNonDefault: (event) =>
    @emitter.emit('did-confirm-selection-if-non-default', event)

  selectNext: ->
    @emitter.emit('did-select-next')

  selectPrevious: ->
    @emitter.emit('did-select-previous')

  selectPageUp: ->
    @emitter.emit('did-select-page-up')

  selectPageDown: ->
    @emitter.emit('did-select-page-down')

  selectTop: ->
    @emitter.emit('did-select-top')

  selectBottom: ->
    @emitter.emit('did-select-bottom')

  ###
  Section: Events
  ###

  onDidConfirmSelection: (fn) ->
    @emitter.on('did-confirm-selection', fn)

  onDidconfirmSelectionIfNonDefault: (fn) ->
    @emitter.on('did-confirm-selection-if-non-default', fn)

  onDidConfirm: (fn) ->
    @emitter.on('did-confirm', fn)

  onDidSelectNext: (fn) ->
    @emitter.on('did-select-next', fn)

  onDidSelectPrevious: (fn) ->
    @emitter.on('did-select-previous', fn)

  onDidSelectPageUp: (fn) ->
    @emitter.on('did-select-page-up', fn)

  onDidSelectPageDown: (fn) ->
    @emitter.on('did-select-page-down', fn)

  onDidSelectTop: (fn) ->
    @emitter.on('did-select-top', fn)

  onDidSelectBottom: (fn) ->
    @emitter.on('did-select-bottom', fn)

  onDidCancel: (fn) ->
    @emitter.on('did-cancel', fn)

  onDidDispose: (fn) ->
    @emitter.on('did-dispose', fn)

  onDidChangeItems: (fn) ->
    @emitter.on('did-change-items', fn)

  isActive: ->
    @active

  show: (editor, options) =>
    if atom.config.get('autocomplete-plus.suggestionListFollows') is 'Cursor'
      @showAtCursorPosition(editor, options)
    else
      prefix = options.prefix
      followRawPrefix = false
      for item in @items
        if item.replacementPrefix?
          prefix = item.replacementPrefix.trim()
          followRawPrefix = true
          break
      @showAtBeginningOfPrefix(editor, prefix, followRawPrefix)

  showAtBeginningOfPrefix: (editor, prefix, followRawPrefix=false) =>
    return unless editor?

    bufferPosition = editor.getCursorBufferPosition()
    bufferPosition = bufferPosition.translate([0, -prefix.length]) if followRawPrefix or @wordPrefixRegex.test(prefix)

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

  # Public: Clean up, stop listening to events
  dispose: ->
    @subscriptions.dispose()
    @movementCommandSubscriptions?.dispose()
    @emitter.emit('did-dispose')
    @emitter.dispose()
