{CompositeDisposable} = require 'atom'
SnippetParser = require './snippet-parser'
{isString} = require('./type-helpers')

ItemTemplate = """
  <span class="icon-container"></span>
  <span class="left-label"></span>
  <span class="word-container">
    <span class="word"></span>
    <span class="right-label"></span>
  </span>
"""

ListTemplate = """
  <div class="suggestion-list-scroller">
    <ol class="list-group"></ol>
  </div>
  <div class="suggestion-description">
    <span class="suggestion-description-content"></span>
    <a class="suggestion-description-more-link" href="#">More..</a>
  </div>
"""

IconTemplate = '<i class="icon"></i>'

DefaultSuggestionTypeIconHTML =
  'snippet': '<i class="icon-move-right"></i>'
  'import': '<i class="icon-package"></i>'
  'require': '<i class="icon-package"></i>'
  'module': '<i class="icon-package"></i>'
  'package': '<i class="icon-package"></i>'
  'tag': '<i class="icon-code"></i>'
  'attribute': '<i class="icon-tag"></i>'

SnippetStart = 1
SnippetEnd = 2
SnippetStartAndEnd = 3

class SuggestionListElement extends HTMLElement
  maxItems: 200
  emptySnippetGroupRegex: /(\$\{\d+\:\})|(\$\{\d+\})|(\$\d+)/ig
  nodePool: null

  createdCallback: ->
    @subscriptions = new CompositeDisposable
    @classList.add('popover-list', 'select-list', 'autocomplete-suggestion-list')
    @registerMouseHandling()
    @snippetParser = new SnippetParser
    @nodePool = []

  attachedCallback: ->
    # TODO: Fix overlay decorator to in atom to apply class attribute correctly, then move this to overlay creation point.
    @parentElement.classList.add('autocomplete-plus')
    @addActiveClassToEditor()
    @renderList() unless @ol
    @itemsChanged()

  detachedCallback: ->
    @removeActiveClassFromEditor()

  initialize: (@model) ->
    return unless model?
    @subscriptions.add @model.onDidChangeItems(@itemsChanged.bind(this))
    @subscriptions.add @model.onDidSelectNext(@moveSelectionDown.bind(this))
    @subscriptions.add @model.onDidSelectPrevious(@moveSelectionUp.bind(this))
    @subscriptions.add @model.onDidConfirmSelection(@confirmSelection.bind(this))
    @subscriptions.add @model.onDidDispose(@dispose.bind(this))

    @subscriptions.add atom.config.observe 'autocomplete-plus.suggestionListFollows', (@suggestionListFollows) =>
    @subscriptions.add atom.config.observe 'autocomplete-plus.maxVisibleSuggestions', (@maxVisibleSuggestions) =>
    this

  # This should be unnecessary but the events we need to override
  # are handled at a level that can't be blocked by react synthetic
  # events because they are handled at the document
  registerMouseHandling: ->
    @onmousewheel = (event) -> event.stopPropagation()
    @onmousedown = (event) ->
      item = @findItem(event)
      if item?.dataset.index?
        @selectedIndex = item.dataset.index
        event.stopPropagation()

    @onmouseup = (event) ->
      item = @findItem(event)
      if item?.dataset.index?
        event.stopPropagation()
        @confirmSelection()

  findItem: (event) ->
    item = event.target
    item = item.parentNode while item.tagName isnt 'LI' and item isnt this
    item if item.tagName is 'LI'

  updateDescription: (item) ->
    item = item ? @model?.items?[@selectedIndex]
    return unless item?
    if item.description? and item.description.length > 0
      @descriptionContainer.style.display = 'block'
      @descriptionContent.textContent = item.description
      if item.descriptionMoreURL? and item.descriptionMoreURL.length?
        @descriptionMoreLink.style.display = 'inline'
        @descriptionMoreLink.setAttribute('href', item.descriptionMoreURL)
      else
        @descriptionMoreLink.style.display = 'none'
        @descriptionMoreLink.setAttribute('href', '#')
    else
      @descriptionContainer.style.display = 'none'

  itemsChanged: ->
    if @model?.items?.length
      @render()
    else
      @returnItemsToPool(0)

  render: ->
    @selectedIndex = 0
    atom.views.pollAfterNextUpdate?()
    atom.views.updateDocument @renderItems.bind(this)
    atom.views.readDocument @readUIPropsFromDOM.bind(this)

  addActiveClassToEditor: ->
    editorElement = atom.views.getView(atom.workspace.getActiveTextEditor())
    editorElement?.classList?.add 'autocomplete-active'

  removeActiveClassFromEditor: ->
    editorElement = atom.views.getView(atom.workspace.getActiveTextEditor())
    editorElement?.classList?.remove 'autocomplete-active'

  moveSelectionUp: ->
    unless @selectedIndex <= 0
      @setSelectedIndex(@selectedIndex - 1)
    else
      @setSelectedIndex(@visibleItems().length - 1)

  moveSelectionDown: ->
    unless @selectedIndex >= (@visibleItems().length - 1)
      @setSelectedIndex(@selectedIndex + 1)
    else
      @setSelectedIndex(0)

  setSelectedIndex: (index) ->
    @selectedIndex = index
    atom.views.updateDocument @renderSelectedItem.bind(this)

  visibleItems: ->
    @model?.items?.slice(0, @maxItems)

  # Private: Get the currently selected item
  #
  # Returns the selected {Object}
  getSelectedItem: ->
    @model?.items?[@selectedIndex]

  # Private: Confirms the currently selected item or cancels the list view
  # if no item has been selected
  confirmSelection: ->
    return unless @model.isActive()
    item = @getSelectedItem()
    if item?
      @model.confirm(item)
    else
      @model.cancel()

  renderList: ->
    @innerHTML = ListTemplate
    @ol = @querySelector('.list-group')
    @scroller = @querySelector('.suggestion-list-scroller')
    @descriptionContainer = @querySelector('.suggestion-description')
    @descriptionContent = @querySelector('.suggestion-description-content')
    @descriptionMoreLink = @querySelector('.suggestion-description-more-link')

  renderItems: ->
    @style.width = null
    items = @visibleItems() ? []
    longestDesc = 0
    longestDescIndex = null
    for item, index in items
      @renderItem(item, index)
      descLength = @descriptionLength(item)
      if descLength > longestDesc
        longestDesc = descLength
        longestDescIndex = index
    @updateDescription(items[longestDescIndex])
    @returnItemsToPool(items.length)

  returnItemsToPool: (pivotIndex) ->
    while @ol? and li = @ol.childNodes[pivotIndex]
      li.remove()
      @nodePool.push(li)
    return

  descriptionLength: (item) ->
    count = 0
    if item.description?
      count += item.description.length
    if item.descriptionMoreURL?
      count += 6
    count

  renderSelectedItem: ->
    @selectedLi?.classList.remove('selected')
    @selectedLi = @ol.childNodes[@selectedIndex]
    if @selectedLi?
      @selectedLi.classList.add('selected')
      @scrollSelectedItemIntoView()
      @updateDescription()

  # This is reading the DOM in the updateDOM cycle. If we dont, there is a flicker :/
  scrollSelectedItemIntoView: ->
    scrollTop = @scroller.scrollTop
    selectedItemTop = @selectedLi.offsetTop
    if selectedItemTop < scrollTop
      # scroll up
      return @scroller.scrollTop = selectedItemTop

    itemHeight = @uiProps.itemHeight
    scrollerHeight = @maxVisibleSuggestions * itemHeight + @uiProps.paddingHeight
    if selectedItemTop + itemHeight > scrollTop + scrollerHeight
      # scroll down
      @scroller.scrollTop = selectedItemTop - scrollerHeight + itemHeight

  readUIPropsFromDOM: ->
    wordContainer = @selectedLi?.querySelector('.word-container')

    @uiProps ?= {}
    @uiProps.width = @offsetWidth + 1
    @uiProps.marginLeft = -(wordContainer?.offsetLeft ? 0)
    @uiProps.itemHeight ?= @selectedLi.offsetHeight
    @uiProps.paddingHeight ?= (parseInt(getComputedStyle(this)['padding-top']) + parseInt(getComputedStyle(this)['padding-bottom'])) ? 0

    if atom.views.documentReadInProgress?
      # Run in atom >= 0.193. Will batch write updates and run them immediately after this read
      atom.views.updateDocument @updateUIForChangedProps.bind(this)
    else
      @updateUIForChangedProps()

  updateUIForChangedProps: ->
    @scroller.style['max-height'] = "#{@maxVisibleSuggestions * @uiProps.itemHeight + @uiProps.paddingHeight}px"
    @style.width = "#{@uiProps.width}px"
    if @suggestionListFollows is 'Word'
      @style['margin-left'] = "#{@uiProps.marginLeft}px"
    @updateDescription()

  # Splits the classes on spaces so as not to anger the DOM gods
  addClassToElement: (element, classNames) ->
    if classNames and classes = classNames.split(' ')
      for className in classes
        className = className.trim()
        element.classList.add(className) if className
    return

  renderItem: ({iconHTML, type, snippet, text, displayText, className, replacementPrefix, leftLabel, leftLabelHTML, rightLabel, rightLabelHTML}, index) ->
    li = @ol.childNodes[index]
    unless li
      if @nodePool.length > 0
        li = @nodePool.pop()
      else
        li = document.createElement('li')
        li.innerHTML = ItemTemplate
      li.dataset.index = index
      @ol.appendChild(li)

    li.className = ''
    li.classList.add('selected') if index is @selectedIndex
    @addClassToElement(li, className) if className
    @selectedLi = li if index is @selectedIndex

    typeIconContainer = li.querySelector('.icon-container')
    typeIconContainer.innerHTML = ''

    sanitizedType = escapeHtml(if isString(type) then type else '')
    sanitizedIconHTML = if isString(iconHTML) then iconHTML else undefined
    defaultLetterIconHTML = if sanitizedType then "<span class=\"icon-letter\">#{sanitizedType[0]}</span>" else ''
    defaultIconHTML = DefaultSuggestionTypeIconHTML[sanitizedType] ? defaultLetterIconHTML
    if (sanitizedIconHTML or defaultIconHTML) and iconHTML isnt false
      typeIconContainer.innerHTML = IconTemplate
      typeIcon = typeIconContainer.childNodes[0]
      typeIcon.innerHTML = sanitizedIconHTML ? defaultIconHTML
      @addClassToElement(typeIcon, type) if type

    wordSpan = li.querySelector('.word')
    wordSpan.innerHTML = @getDisplayHTML(text, snippet, displayText, replacementPrefix)

    leftLabelSpan = li.querySelector('.left-label')
    if leftLabelHTML?
      leftLabelSpan.innerHTML = leftLabelHTML
    else if leftLabel?
      leftLabelSpan.textContent = leftLabel
    else
      leftLabelSpan.textContent = ''

    rightLabelSpan = li.querySelector('.right-label')
    if rightLabelHTML?
      rightLabelSpan.innerHTML = rightLabelHTML
    else if rightLabel?
      rightLabelSpan.textContent = rightLabel
    else
      rightLabelSpan.textContent = ''

  getDisplayHTML: (text, snippet, displayText, replacementPrefix) ->
    replacementText = text
    if typeof displayText is 'string'
      replacementText = displayText
    else if typeof snippet is 'string'
      replacementText = @removeEmptySnippets(snippet)
      snippets = @snippetParser.findSnippets(replacementText)
      replacementText = @removeSnippetsFromText(snippets, replacementText)
      snippetIndices = @findSnippetIndices(snippets)
    characterMatchIndices = @findCharacterMatchIndices(replacementText, replacementPrefix)

    displayHTML = ''
    for character, index in replacementText
      if snippetIndices?[index] in [SnippetStart, SnippetStartAndEnd]
        displayHTML += '<span class="snippet-completion">'
      if characterMatchIndices?[index]
        displayHTML += '<span class="character-match">' + escapeHtml(replacementText[index]) + '</span>'
      else
        displayHTML += escapeHtml(replacementText[index])
      if snippetIndices?[index] in [SnippetEnd, SnippetStartAndEnd]
        displayHTML += '</span>'
    displayHTML

  removeEmptySnippets: (text) ->
    return text unless text?.length and text.indexOf('$') isnt -1 # No snippets
    text.replace(@emptySnippetGroupRegex, '') # Remove all occurrences of $0 or ${0} or ${0:}

  # Will convert 'abc(${1:d}, ${2:e})f' => 'abc(d, e)f'
  #
  # * `snippets` {Array} from `SnippetParser.findSnippets`
  # * `text` {String} to remove snippets from
  #
  # Returns {String}
  removeSnippetsFromText: (snippets, text) ->
    return text unless text.length and snippets?.length
    index = 0
    result = ''
    for {snippetStart, snippetEnd, body} in snippets
      result += text.slice(index, snippetStart) + body
      index = snippetEnd + 1
    result += text.slice(index, text.length) if index isnt text.length
    result

  # Computes the indices of snippets in the resulting string from
  # `removeSnippetsFromText`.
  #
  # * `snippets` {Array} from `SnippetParser.findSnippets`
  #
  # e.g. A replacement of 'abc(${1:d})e' is replaced to 'abc(d)e' will result in
  #
  # `{4: SnippetStartAndEnd}`
  #
  # Returns {Object} of {index: SnippetStart|End|StartAndEnd}
  findSnippetIndices: (snippets) ->
    return unless snippets?
    indices = {}
    offsetAccumulator = 0
    for {snippetStart, snippetEnd, body} in snippets
      bodyLength = body.length
      snippetLength = snippetEnd - snippetStart + 1
      startIndex = snippetStart - offsetAccumulator
      endIndex = startIndex + bodyLength - 1
      offsetAccumulator += snippetLength - bodyLength

      if startIndex is endIndex
        indices[startIndex] = SnippetStartAndEnd
      else
        indices[startIndex] = SnippetStart
        indices[endIndex] = SnippetEnd
    indices

  # Finds the indices of the chars in text that are matched by replacementPrefix
  #
  # e.g. text = 'abcde', replacementPrefix = 'acd' Will result in
  #
  # {0: true, 2: true, 3: true}
  #
  # Returns an {Object}
  findCharacterMatchIndices: (text, replacementPrefix) ->
    return unless text?.length and replacementPrefix?.length
    matches = {}
    wordIndex = 0
    for ch, i in replacementPrefix
      while wordIndex < text.length and text[wordIndex].toLowerCase() isnt ch.toLowerCase()
        wordIndex += 1
      break if wordIndex >= text.length
      matches[wordIndex] = true
      wordIndex += 1
    matches

  dispose: ->
    @subscriptions.dispose()
    @parentNode?.removeChild(this)

# https://github.com/component/escape-html/blob/master/index.js
escapeHtml = (html) ->
  String(html)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')

module.exports = SuggestionListElement = document.registerElement('autocomplete-suggestion-list', {prototype: SuggestionListElement.prototype})
