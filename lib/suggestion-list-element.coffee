{CompositeDisposable} = require 'atom'
_ = require 'underscore-plus'

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

class SuggestionListElement extends HTMLElement
  maxItems: 200
  emptySnippetGroupRegex: /(\$\{\d+\:\})|(\$\{\d+\})|(\$\d+)/ig

  createdCallback: ->
    @subscriptions = new CompositeDisposable
    @classList.add('popover-list', 'select-list', 'autocomplete-suggestion-list')
    @registerMouseHandling()

  attachedCallback: ->
    # TODO: Fix overlay decorator to in atom to apply class attribute correctly, then move this to overlay creation point.
    @parentElement.classList.add('autocomplete-plus')
    @addActiveClassToEditor()
    @renderList() unless @ol
    @calculateMaxListHeight()
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

  updateDescription: ->
    item = @visibleItems()[@selectedIndex]
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
    @selectedIndex = 0
    atom.views.pollAfterNextUpdate?()
    atom.views.updateDocument =>
      @renderItems()
      @updateDescription()

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
    @renderItems()
    @updateDescription()

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

  calculateMaxListHeight: ->
    li = document.createElement('li')
    li.textContent = 'test'
    @ol.appendChild(li)
    itemHeight = li.offsetHeight
    paddingHeight = parseInt(getComputedStyle(this)['padding-top']) + parseInt(getComputedStyle(this)['padding-bottom']) ? 0
    @scroller.style['max-height'] = "#{@maxVisibleSuggestions * itemHeight + paddingHeight}px"
    li.remove()

  renderItems: ->
    items = @visibleItems() ? []
    @renderItem(item, index) for item, index in items
    li.remove() while li = @ol.childNodes[items.length]
    @selectedLi?.scrollIntoView(false)

    if @suggestionListFollows is 'Word'
      firstChild = @ol.childNodes[0]
      wordContainer = firstChild?.querySelector('.word-container')
      marginLeft = 0
      marginLeft = -wordContainer.offsetLeft if wordContainer?
      @style['margin-left'] = "#{marginLeft}px"

  renderItem: ({iconHTML, type, snippet, text, className, replacementPrefix, leftLabel, leftLabelHTML, rightLabel, rightLabelHTML}, index) ->
    li = @ol.childNodes[index]
    unless li
      li = document.createElement('li')
      li.innerHTML = ItemTemplate
      li.dataset.index = index
      @ol.appendChild(li)

    li.className = ''
    li.classList.add(className) if className
    li.classList.add('selected') if index is @selectedIndex
    @selectedLi = li if index is @selectedIndex

    typeIconContainer = li.querySelector('.icon-container')
    typeIconContainer.innerHTML = ''

    sanitizedType = if _.isString(type) then type else ''
    sanitizedIconHTML = if _.isString(iconHTML) then iconHTML else undefined
    defaultLetterIconHTML = if sanitizedType then "<span class=\"icon-letter\">#{sanitizedType[0]}</span>" else ''
    defaultIconHTML = DefaultSuggestionTypeIconHTML[sanitizedType] ? defaultLetterIconHTML
    if (sanitizedIconHTML or defaultIconHTML) and iconHTML isnt false
      typeIconContainer.innerHTML = IconTemplate
      typeIcon = typeIconContainer.childNodes[0]
      typeIcon.innerHTML = sanitizedIconHTML ? defaultIconHTML
      typeIcon.classList.add(type) if type

    wordSpan = li.querySelector('.word')
    wordSpan.innerHTML = @getHighlightedHTML(text, snippet, replacementPrefix)

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

  getHighlightedHTML: (text, snippet, replacementPrefix) =>
    # 1. Highlight relevant characters
    # 2. Remove / replace snippet metadata to enhance readability

    replacement = text
    replacement = snippet if _.isString(snippet)
    return replacement unless replacement.length > 0

    # Add spans for replacement prefix
    # e.g. replacement: 'abc(${d}, ${e})f'
    # ->   highlightedHTML: '<span class="character-match">a</span>bc(${d}, ${e})f'
    highlightedHTML = ''
    wordIndex = 0
    lastWordIndex = 0
    for ch, i in replacementPrefix
      while wordIndex < replacement.length and replacement[wordIndex].toLowerCase() isnt ch.toLowerCase()
        wordIndex += 1

      break if wordIndex >= replacement.length
      preChar = replacement.substring(lastWordIndex, wordIndex)
      highlightedChar = "<span class=\"character-match\">#{replacement[wordIndex]}</span>"
      highlightedHTML = "#{highlightedHTML}#{preChar}#{highlightedChar}"
      wordIndex += 1
      lastWordIndex = wordIndex

    highlightedHTML += replacement.substring(lastWordIndex)

    # Remove / replace snippet metadata to make it more readable
    # e.g. highlightedHTML: '<span class="character-match">a</span>bc(${d}, ${e})f'
    # ->   highlightedHTML: '<span class="character-match">a</span>bc(<span class="snippet-completion">d</span>, <span class="snippet-completion">e</span>)f'
    highlightedHTML = @enhanceSnippet(highlightedHTML) if _.isString(snippet)
    highlightedHTML

  enhanceSnippet: (text) =>
    return text unless text.length > 0 and text.indexOf('$') isnt -1 # Not a snippet

    # Remove all occurrences of $0 or ${0} or ${0:}
    text = text.replace(@emptySnippetGroupRegex, '')
    return text unless text.indexOf('${') isnt -1 # No snippets left

    # Enhance snippet group(s) with metadata, and make their display more friendly
    oldText = text
    text = ''
    inSnippet = false
    inSnippetBody = false
    snippetStartIndex = -1
    snippetEndIndex = -1
    bodyStartIndex = -1
    bodyEndIndex = -1
    skipIndices = []

    # We're not using a regex because escaped right braces cannot be tracked without lookbehind,
    # which doesn't exist yet for javascript; consequently we need to iterate through each character.
    # This might feel ugly, but it's necessary.
    for char, index in oldText.split('')
      continue if skipIndices.indexOf(index) isnt -1

      if inSnippet and snippetEndIndex is index
        text += '</span>'
        inSnippet = false
        inSnippetBody = false
        snippetStartIndex = -1
        snippetEndIndex = -1
        bodyStartIndex = -1
        bodyEndIndex = -1
        continue

      inSnippetBody = true if inSnippet and index >= bodyStartIndex and index <= bodyEndIndex
      inSnippetBody = false if inSnippet and (index > bodyEndIndex or index < bodyStartIndex)
      inSnippetBody = false if bodyStartIndex is -1 or bodyEndIndex is -1
      continue if inSnippet and not inSnippetBody

      if inSnippet and inSnippetBody
        text += char
        continue

      # Determine if we've found a new snippet
      if not inSnippet and oldText.indexOf('${', index) is index
        # Find index of colon
        colonIndex = oldText.indexOf(':', index + 3)
        if colonIndex isnt -1
          # Disqualify snippet unless the text between '${' and ':' are digits
          groupStart = index + 2
          groupEnd = colonIndex - 1
          if groupEnd >= groupStart
            for i in [groupStart...groupEnd]
              colonIndex = -1 if isNaN(parseInt(oldText.charAt(i)))
          else
            colonIndex = -1

        # Find index of '}'
        rightBraceIndex = -1
        if colonIndex isnt -1
          i = index + 4
          loop
            rightBraceIndex = oldText.indexOf('}', i)
            break if rightBraceIndex is -1
            if oldText.charAt(rightBraceIndex - 2) is '\\' and oldText.charAt(rightBraceIndex - 1) is '\\'
              skipIndices.push(rightBraceIndex - 1, rightBraceIndex - 2)
            else
              break
            i = rightBraceIndex + 1

        if colonIndex isnt -1 and rightBraceIndex isnt -1 and colonIndex < rightBraceIndex
          inSnippet = true
          inSnippetBody = false
          snippetStartIndex = index
          snippetEndIndex = rightBraceIndex
          bodyStartIndex = colonIndex + 1
          bodyEndIndex = rightBraceIndex - 1
          text += '<span class="snippet-completion">'
          continue
        else
          inSnippet = false
          inSnippetBody = false
          snippetStartIndex = -1
          snippetEndIndex = -1
          bodyStartIndex = -1
          bodyEndIndex = -1

      unless (inSnippet or inSnippetBody)
        text += char
        continue

    return text

  dispose: ->
    @subscriptions.dispose()
    @parentNode?.removeChild(this)

module.exports = SuggestionListElement = document.registerElement('autocomplete-suggestion-list', {prototype: SuggestionListElement.prototype})
