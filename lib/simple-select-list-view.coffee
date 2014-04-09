{$, View} = require "atom"
_ = require "underscore-plus"

Keys =
  Escape: 27
  Enter: 13
  Tab: 9

class SimpleSelectListView extends View
  eventsAttached: false
  maxItems: 10
  @content: ->
    @div class: "select-list", =>
      @input class: "hidden-input", outlet: "hiddenInput"
      @ol class: "list-group", outlet: "list"

  ###
   * Overrides default initialization
  ###
  initialize: ->
    @on "core:move-up", (e) =>
      @selectPreviousItemView()

    @on "core:move-down", =>
      @selectNextItemView()

    @on "core:confirm", =>
      @confirmSelection()

    @on "core:cancel", =>
      @cancel()

    @list.on "mousedown", "li", (e) =>
      e.preventDefault()
      e.stopPropagation()

      @selectItemView $(e.target).closest("li")

    @list.on "mouseup", "li", (e) =>
      e.preventDefault()
      e.stopPropagation()

      if $(e.target).closest("li").hasClass "selected"
        @confirmSelection()

  setMaxItems: (@maxItems) -> return

  setItems: (items=[]) ->
    @items = items
    @populateList()

  selectPreviousItemView: ->
    view = @getSelectedItemView().prev()
    unless view.length
      view = @list.find "li:last"
    @selectItemView view

  selectNextItemView: ->
    view = @getSelectedItemView().next()
    unless view.length
      view = @list.find "li:first"
    @selectItemView view

  selectItemView: (view) ->
    return unless view.length

    @list.find(".selected").removeClass "selected"
    view.addClass "selected"
    @scrollToItemView view

  scrollToItemView: (view) ->
    scrollTop = @list.scrollTop()
    desiredTop = view.position().top + scrollTop
    desiredBottom = desiredTop + view.outerHeight()

    if desiredTop < scrollTop
      @list.scrollTop desiredTop
    else
      @list.scrollBottom desiredBottom

  getSelectedItemView: ->
    @list.find "li.selected"

  getSelectedItem: ->
    @getSelectedItemView().data "select-list-item"

  confirmSelection: ->
    item = @getSelectedItem()
    if item?
      @confirmed item
    else
      @cancel()

  setActive: ->
    @hiddenInput.focus()

    unless @eventsAttached
      @eventsAttached = true

      @hiddenInput.keydown (e) =>
        switch e.keyCode
          when Keys.Enter, Keys.Tab
            @trigger "core:confirm"
          when Keys.Escape
            @trigger "core:cancel"

        if e.keyCode in _.values(Keys)
          return false

  populateList: ->
    return unless @items?

    @list.empty()
    for i in [0...Math.min(@items.length, @maxItems)]
      item = @items[i]
      itemView = @viewForItem item
      $(itemView).data "select-list-item", item
      @list.append itemView

    @selectItemView @list.find "li:first"

  cancel: ->
    @list.empty()
    @detach()

module.exports = SimpleSelectListView
