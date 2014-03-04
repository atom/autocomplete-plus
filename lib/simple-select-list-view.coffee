{$, SelectListView, EditorView} = require "atom"
_ = require "underscore-plus"

Keys =
  Escape: 27
  Enter: 13

class SimpleSelectListView extends SelectListView
  eventsAttached: false
  @content: ->
    @div class: "select-list", =>
      @input class: "fake-input", outlet: "fakeInput"
      @div class: "error-message", outlet: "error"
      @div class: "loading", outlet: "loadingArea", =>
        @span class: "loading-message", outlet: "loading"
        @span class: "badge", outlet: "loadingBadge"
      @ol class: "list-group", outlet: "list"

  focusList: ->
    @filterEditorView.focus()

  setActive: ->
    @fakeInput.focus()

    unless @eventsAttached
      @eventsAttached = true

      # Makes sure that `autosave` does not try to run `getModel` when
      # losing focus. Weird stuff going on here.
      @fakeInput.focusout -> false

      @fakeInput.keydown (e) =>
        switch e.keyCode
          when Keys.Enter
            @confirmSelection()
          when Keys.Escape
            @cancel()

        if e.keyCode in _.values(Keys)
          return false

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
