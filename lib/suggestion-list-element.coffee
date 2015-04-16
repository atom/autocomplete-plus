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

  getHighlightedHTML: (text, snippet, replacementPrefix) ->
    # 1. Highlight relevant characters
    # 2. Remove snippet metadata and wrap snippets for context

    replacement = text
    replacement = @removeEmptySnippets(snippet) if _.isString(snippet)
    return replacement unless replacement?.length

    snippets = []
    snippets = @findSnippets(replacement) if _.isString(snippet)
    snippetStarts = []
    snippetEnds = []
    skipChars = []
    for snippet in snippets
      snippetStarts.push(snippet.snippetStart)
      snippetEnds.push(snippet.snippetEnd)
      skipChars = skipChars.concat([snippet.snippetStart...snippet.bodyStart])
      skipChars = skipChars.concat([snippet.bodyEnd + 1..snippet.snippetEnd])
      skipChars = skipChars.concat(snippet.skipChars) if snippet.skipChars.length

    characterMatches = @findCharacterMatches(replacement, replacementPrefix, snippets)

    highlightedHTML = ''

    for i in [0...replacement.length]
      if snippets.length?
        if snippetStarts.indexOf(i) isnt -1
          highlightedHTML += '<span class="snippet-completion">'
          continue

        if snippetEnds.indexOf(i) isnt -1
          highlightedHTML += '</span>'
          continue

        continue if skipChars.indexOf(i) isnt -1

      if characterMatches.indexOf(i) is -1
        highlightedHTML += replacement[i]
        continue

      highlightedHTML += '<span class="character-match">' + replacement[i] + '</span>'

    highlightedHTML

  removeEmptySnippets: (text) ->
    return text unless text?.length and text.indexOf('$') isnt -1 # No snippets
    text.replace(@emptySnippetGroupRegex, '') # Remove all occurrences of $0 or ${0} or ${0:}

  removeAllSnippets: (text) ->
    return text unless text.length > 0 and text.indexOf('$') isnt -1 # No snippets
    text.replace(@emptySnippetGroupRegex, '') # Remove all occurrences of $0 or ${0} or ${0:}
    snippets = @findSnippets(text)
    return text unless snippets.length
    delta = 0
    for snippet in snippets
      text = text.substring(0, snippet.snippetStart - delta) + text.substring(snippet.bodyStart - delta, snippet.bodyEnd + 1 - delta) + text.substring(snippet.snippetEnd + 1 - delta, text.length)
      delta += (snippet.bodyStart - snippet.snippetStart) + (snippet.snippetEnd - snippet.bodyEnd)

    text

  findCharacterMatches: (text, replacementPrefix, snippets) ->
    return [] unless text?.length and replacementPrefix?.length
    skipChars = []
    if snippets?.length
      for snippet in snippets
        skipChars = skipChars.concat(snippet.skipChars) if snippet.skipChars.length
        skipChars = skipChars.concat([snippet.snippetStart...snippet.bodyStart])
        skipChars = skipChars.concat([(snippet.bodyEnd + 1)..snippet.snippetEnd])

    matches = []
    wordIndex = 0
    for ch, i in replacementPrefix
      while wordIndex < text.length and text[wordIndex].toLowerCase() isnt ch.toLowerCase()
        wordIndex += 1
      break if wordIndex >= text.length
      continue if skipChars.indexOf(wordIndex) isnt -1
      matches.push(wordIndex)
      wordIndex += 1

    matches

  findSnippets: (text) ->
    return [] unless text.length > 0 and text.indexOf('$') isnt -1 # No snippets
    snippets = []

    inSnippet = false
    inSnippetBody = false
    snippetStart = -1
    snippetEnd = -1
    bodyStart = -1
    bodyEnd = -1
    skipChars = []

    # We're not using a regex because escaped right braces cannot be tracked without lookbehind,
    # which doesn't exist yet for javascript; consequently we need to iterate through each character.
    # This might feel ugly, but it's necessary.
    for char, index in text.split('')
      if inSnippet and snippetEnd is index
        snippet =
          snippetStart: snippetStart
          snippetEnd: snippetEnd
          bodyStart: bodyStart
          bodyEnd: bodyEnd
          skipChars: skipChars
        snippets.push(snippet)
        inSnippet = false
        inBody = false
        snippetStart = -1
        snippetEnd = -1
        bodyStart = -1
        bodyEnd = -1
        skipChars = []
        continue

      inBody = true if inSnippet and index >= bodyStart and index <= bodyEnd
      inBody = false if inSnippet and (index > bodyEnd or index < bodyStart)
      inBody = false if bodyStart is -1 or bodyEnd is -1
      continue if inSnippet and not inBody

      continue if inSnippet and inBody

      # Determine if we've found a new snippet
      if not inSnippet and text.indexOf('${', index) is index
        # Find index of colon
        colonIndex = text.indexOf(':', index + 3)
        if colonIndex isnt -1
          # Disqualify snippet unless the text between '${' and ':' are digits
          groupStart = index + 2
          groupEnd = colonIndex - 1
          if groupEnd >= groupStart
            for i in [groupStart...groupEnd]
              colonIndex = -1 if isNaN(parseInt(text.charAt(i)))
          else
            colonIndex = -1

        # Find index of '}'
        rightBraceIndex = -1
        if colonIndex isnt -1
          i = index + 4
          loop
            rightBraceIndex = text.indexOf('}', i)
            break if rightBraceIndex is -1
            if text.charAt(rightBraceIndex - 2) is '\\' and text.charAt(rightBraceIndex - 1) is '\\'
              skipChars.push(rightBraceIndex - 2, rightBraceIndex - 1)
            else
              break
            i = rightBraceIndex + 1

        if colonIndex isnt -1 and rightBraceIndex isnt -1 and colonIndex < rightBraceIndex
          inSnippet = true
          inBody = false
          snippetStart = index
          snippetEnd = rightBraceIndex
          bodyStart = colonIndex + 1
          bodyEnd = rightBraceIndex - 1
          continue
        else
          inSnippet = false
          inBody = false
          snippetStart = -1
          snippetEnd = -1
          bodyStart = -1
          bodyEnd = -1
          skipChars = []

    snippets

  dispose: ->
    @subscriptions.dispose()
    @parentNode?.removeChild(this)

module.exports = SuggestionListElement = document.registerElement('autocomplete-suggestion-list', {prototype: SuggestionListElement.prototype})
