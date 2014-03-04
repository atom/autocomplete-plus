{$, SelectListView, EditorView} = require "atom"
_ = require "underscore-plus"

Keys =
  Escape: 27
  Enter: 13
  Tab: 9

class SimpleSelectListView extends SelectListView
  eventsAttached: false
  maxItems: 10
  @content: ->
    @div class: "select-list", =>
      @input class: "fake-input", outlet: "fakeInput"
      @div class: "error-message", outlet: "error"
      @div class: "loading", outlet: "loadingArea", =>
        @span class: "loading-message", outlet: "loading"
        @span class: "badge", outlet: "loadingBadge"
      @ol class: "list-group", outlet: "list"

  ###
   * Overrides default initialization
  ###
  initialize: ->
    @on "core:move-up", (e) =>
      @selectPreviousItemView()

    @on "core:move-down", =>
      @selectNextItemView()

  setActive: ->
    @fakeInput.focus()

    unless @eventsAttached
      @eventsAttached = true

      @fakeInput.keydown (e) =>
        switch e.keyCode
          when Keys.Enter, Keys.Tab
            @confirmSelection()
          when Keys.Escape
            @cancel()

        if e.keyCode in _.values(Keys)
          return false

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
