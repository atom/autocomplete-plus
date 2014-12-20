React = require 'react-atom-fork'
{ol, li, span, input, div} = require 'reactionary-atom-fork'
{CompositeDisposable} = require 'event-kit'
_ = require 'underscore-plus'

SelectListComponent = React.createClass

  getInitialState: ->
    items: @props.items || []
    selectedIndex: 0

  componentDidUpdate: ->
    @refs.selected?.getDOMNode().scrollIntoView(false)
    @updateEventListeners(@refs.input.getDOMNode()) if @refs.input

  updateEventListeners: (input) ->
    if @input != input
      input.addEventListener 'compositionstart', =>
        @props.setComposition true
        null

      input.addEventListener 'compositionend', =>
        @props.setComposition false
        null

  updateItems: (items) ->
    @setState(items: items, selectedIndex: 0, =>
      setTimeout =>
        @refs.input?.getDOMNode().focus()
      , 0
    )

  render: ->
    div input(ref: 'input', key: 'autocomplete-plus-input'),
      ol
        key: 'autocomplete-plus-list',
        className: "list-group",
        @state.items?.map ({word, label, renderLabelAsHtml, className}, index) =>
          itemClasses = []
          itemClasses.push className if className
          itemClasses.push 'selected' if index == @state.selectedIndex

          itemProps =
            className: itemClasses.join(' '),
            'data-index': index,
            key: word

          itemProps.ref = 'selected' if index == @state.selectedIndex

          labelAttributes = className: "label"
          labelAttributes.dangerouslySetInnerHTML = __html: label if renderLabelAsHtml
          li itemProps,
            span className: "word", word
            span labelAttributes, (label unless renderLabelAsHtml) if label?

class SelectListElement extends HTMLElement
  maxItems: 10

  createdCallback: ->
    @subscriptions = new CompositeDisposable
    @classList.add "popover-list"
    @classList.add "select-list"
    @classList.add "autocomplete-plus"
    @registerMouseHandling()

  # This should be unnecessary but the events we need to override
  # are handled at a level that can't be blocked by react synthetic
  # events because they are handled at the document
  registerMouseHandling: ->
    @onmousewheel = (event) -> event.stopPropagation()
    @onmousedown = (event) ->
      item = event.target
      item = item.parentNode while !(item.dataset?.index) && item != this
      @component?.setState selectedIndex: item.dataset?.index

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
    @subscriptions.add @model.onDidDispose(@destroyed.bind(this))

  itemsChanged: (items) ->
    @component?.updateItems(items?.slice(0, @maxItems))

  moveSelectionUp: () ->
    unless @component?.state.selectedIndex == 0
      @component?.setState selectedIndex: --@component.state.selectedIndex
    else
      @component?.setState selectedIndex: (@component?.state.items.length - 1)

  moveSelectionDown: () ->
    unless @component?.state.selectedIndex == (@component?.state.items.length - 1)
      @component?.setState selectedIndex: ++@component.state.selectedIndex
    else
      @component?.setState selectedIndex: 0

  # Private: Get the currently selected item
  #
  # Returns the selected {Object}
  getSelectedItem: ->
    @component?.state?.items[@component?.state?.selectedIndex]

  # Private: Confirms the currently selected item or cancels the list view
  # if no item has been selected
  confirmSelection: ->
    item = @getSelectedItem()
    if item?
      @model.confirm(item)
    else
      @model.cancel()

  mountComponent: ->
    @maxItems = atom.config.get('autocomplete-plus.maxSuggestions')
    @componentDescriptor ?= new SelectListComponent
      setComposition: (state) =>
        @model.compositionInProgress = state
    @component = React.renderComponent(@componentDescriptor, this)
    @itemsChanged(@model.items)

  unmountComponent: ->
    return unless @component?.isMounted()
    React.unmountComponentAtNode(this)
    @component = null

  destroyed: =>
    @subscriptions.dispose()
    @parentNode?.removeChild(this)

module.exports = SelectListElement = document.registerElement 'select-list', prototype: SelectListElement.prototype
