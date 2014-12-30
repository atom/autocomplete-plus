{CompositeDisposable} = require 'event-kit'
_ = require 'underscore-plus'

class SelectListElement extends HTMLElement
  maxItems: 10

  createdCallback: ->
    @subscriptions = new CompositeDisposable
    @classList.add "popover-list"
    @classList.add "select-list"
    @classList.add "autocomplete-plus"
    @classList.add "autocomplete-suggestion-list"
    @subscriptions.add(atom.config.observe('autocomplete-plus.maxSuggestions', => @maxItems = atom.config.get('autocomplete-plus.maxSuggestions')))
    @registerMouseHandling()

  # This should be unnecessary but the events we need to override
  # are handled at a level that can't be blocked by react synthetic
  # events because they are handled at the document
  registerMouseHandling: ->
    @onmousewheel = (event) -> event.stopPropagation()
    @onmousedown = (event) ->
      item = event.target
      item = item.parentNode while !(item.dataset?.index) && item != this
      @selectedIndex = item.dataset?.index

      event.stopPropagation()

    @onmouseup = (event) ->
      event.stopPropagation()
      @confirmSelection()

  attachedCallback: ->
    @mountComponent() unless @component?.isMounted()

  getModel: -> @model

  setModel: (model) ->
    @model = model
    @subscriptions.add @model.onDidChangeItems(@itemsChanged.bind(this))
    @subscriptions.add @model.onDoSelectNext(@moveSelectionDown.bind(this))
    @subscriptions.add @model.onDoSelectPrevious(@moveSelectionUp.bind(this))
    @subscriptions.add @model.onDoConfirmSelection(@confirmSelection.bind(this))
    @subscriptions.add @model.onDidDispose(@dispose.bind(this))

  itemsChanged: ->
    @selectedIndex = 0
    @renderItems()
    setTimeout =>
      @input.focus()
    , 0

  moveSelectionUp: () ->
    unless @selectedIndex <= 0
      @setSelectedIndex(@selectedIndex - 1)
    else
      @setSelectedIndex(@visibleItems().length - 1)

  moveSelectionDown: () ->
    unless @selectedIndex >= (@visibleItems().length - 1)
      @setSelectedIndex(@selectedIndex + 1)
    else
      @setSelectedIndex(0)

  setSelectedIndex: (index) ->
    @selectedIndex = index
    @renderItems()

  visibleItems: () ->
    @model?.items?.slice(0, @maxItems)

  # Private: Get the currently selected item
  #
  # Returns the selected {Object}
  getSelectedItem: ->
    @model?.items?[@selectedIndex]

  # Private: Confirms the currently selected item or cancels the list view
  # if no item has been selected
  confirmSelection: ->
    item = @getSelectedItem()
    if item?
      @model.confirm(item)
    else
      @model.cancel()

  mountComponent: ->
    @renderInput() unless @input
    @renderList() unless @ol
    @itemsChanged()

  renderInput: ->
    @input = document.createElement('input')
    @appendChild(@input)

    @input.addEventListener 'compositionstart', =>
      @model.compositionInProgress = true
      null

    @input.addEventListener 'compositionend', =>
      @model.compositionInProgress = false
      null

  renderList: ->
    @ol = document.createElement('ol')
    @appendChild(@ol)
    @ol.className = "list-group"

  renderItems: ->
    items = @visibleItems() || []
    items.forEach ({word, label, renderLabelAsHtml, className}, index) =>

      li = @ol.childNodes[index]
      unless li
        li = document.createElement('li')
        @ol.appendChild(li)
        li.dataset.index = index

      li.className = ''
      li.classList.add(className)
      li.classList.add('selected') if index == @selectedIndex
      @selectedLi = li if index == @selectedIndex

      wordSpan = li.childNodes[0]
      unless wordSpan
        wordSpan = document.createElement('span')
        li.appendChild(wordSpan)
        wordSpan.className = "word"

      wordSpan.textContent = word

      labelSpan = li.childNodes[1]
      if label
        unless labelSpan
          labelSpan = document.createElement('span')
          li.appendChild(labelSpan) if label
          labelSpan.className = "label"

        if renderLabelAsHtml
          labelSpan.innerHTML = label
        else
          labelSpan.textContent = label
      else
        labelSpan?.remove()

    itemToRemove = items.length
    li.remove() while li = @ol.childNodes[itemToRemove++]

    @selectedLi?.scrollIntoView(false)

  unmountComponent: ->
    @dispose()

  dispose: ->
    @subscriptions.dispose()
    @parentNode?.removeChild(this)

module.exports = SelectListElement = document.registerElement('autocomplete-suggestion-list', prototype: SelectListElement.prototype)
