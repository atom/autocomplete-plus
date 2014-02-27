{$, SelectListView, EditorView} = require "atom"

class SimpleSelectListView extends SelectListView
  verticalCursorMovementBlocked: false
  @content: ->
    @div class: "select-list", =>
      @div class: "error-message", outlet: "error"
      @div class: "loading", outlet: "loadingArea", =>
        @span class: "loading-message", outlet: "loading"
        @span class: "badge", outlet: "loadingBadge"
      @ol class: "list-group", outlet: "list"

  focusList: ->
    @filterEditorView.focus()

  initialize: ->
    @on "core:move-up", (e) =>
      @selectPreviousItemView()

    @on "core:move-down", =>
      @selectNextItemView()

    @on "core:confirm", =>
      @confirmSelection()

    @on "core:cancel", =>
      @cancel()

  populateList: ->
    return unless @items?

    @list.empty()
    @setError null
    for i in [0...Math.min(@items.length, @maxItems)]
      item = @items[i]
      itemView = @viewForItem item
      $(itemView).data "select-list-item", item
      @list.append itemView

    @selectItemView @list.find "li:first"

  cancel: ->
    @list.empty()
    @cancelling = true
    @detach()
    @cancelling = false

module.exports = SimpleSelectListView
