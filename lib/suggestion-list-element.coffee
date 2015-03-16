{CompositeDisposable} = require 'atom'
_ = require 'underscore-plus'

class SuggestionListElement extends HTMLElement
  maxItems: 200
  snippetRegex: /\$\{[0-9]+:([^}]+)\}/g
  snippetMarkerChar: '|'
  snippetMarkerRegex: /\|/g

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
    @subscriptions.add(@model.onDidChangeItems(@itemsChanged.bind(this)))
    @subscriptions.add(@model.onDidSelectNext(@moveSelectionDown.bind(this)))
    @subscriptions.add(@model.onDidSelectPrevious(@moveSelectionUp.bind(this)))
    @subscriptions.add(@model.onDidConfirmSelection(@confirmSelection.bind(this)))
    @subscriptions.add(@model.onDidDispose(@dispose.bind(this)))
    this

  # This should be unnecessary but the events we need to override
  # are handled at a level that can't be blocked by react synthetic
  # events because they are handled at the document
  registerMouseHandling: ->
    @onmousewheel = (event) -> event.stopPropagation()
    @onmousedown = (event) ->
      item = event.target
      item = item.parentNode while not (item.dataset?.index) and item isnt this
      @selectedIndex = item.dataset?.index
      event.stopPropagation()

    @onmouseup = (event) ->
      event.stopPropagation()
      @confirmSelection()

  itemsChanged: ->
    @selectedIndex = 0
    @renderItems()

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
    @ol = document.createElement('ol')
    @appendChild(@ol)
    @ol.className = 'list-group'

  calculateMaxListHeight: ->
    maxVisibleItems = atom.config.get('autocomplete-plus.maxVisibleSuggestions')
    li = document.createElement('li')
    li.textContent = 'test'
    @ol.appendChild(li)
    itemHeight = li.offsetHeight
    @ol.style['max-height'] = "#{maxVisibleItems * itemHeight}px"
    li.remove()

  renderItems: ->
    items = @visibleItems() ? []
    @renderItem(item, index) for item, index in items
    li.remove() while li = @ol.childNodes[items.length]
    @selectedLi?.scrollIntoView(false)

  renderItem: ({snippet, text, rightLabel, rightLabelHTML, className, replacementPrefix}, index) ->
    li = @ol.childNodes[index]
    unless li
      li = document.createElement('li')
      @ol.appendChild(li)
      li.dataset.index = index

    li.className = ''
    li.classList.add(className) if className
    li.classList.add('selected') if index is @selectedIndex
    @selectedLi = li if index is @selectedIndex

    wordSpan = li.childNodes[0]
    unless wordSpan
      wordSpan = document.createElement('span')
      li.appendChild(wordSpan)
      wordSpan.className = 'word'

    wordSpan.innerHTML = @getHighlightedHTML(text, snippet, replacementPrefix)

    labelSpan = li.childNodes[1]
    hasRightLabel = rightLabel or rightLabelHTML
    if hasRightLabel
      unless labelSpan
        labelSpan = document.createElement('span')
        li.appendChild(labelSpan) if hasRightLabel
        labelSpan.className = 'completion-label text-smaller text-subtle'

      if rightLabelHTML?
        labelSpan.innerHTML = rightLabelHTML
      else
        labelSpan.textContent = rightLabel
    else
      labelSpan?.remove()

  getHighlightedHTML: (text, snippet, replacementPrefix) ->
    # 1. Pull the snippets out, replacing with placeholder
    # 2. Highlight relevant characters
    # 3. Place snippet HTML back at the placeholders

    # Pull out snippet
    # e.g. replacementPrefix: 'a', snippet: 'abc(${d}, ${e})f'
    # ->   replacement: 'abc(|, |)f'
    replacement = text
    snippetCompletions = []
    if _.isString(snippet)
      replacement = snippet.replace @snippetRegex, (match, snippetText) =>
        snippetCompletions.push "<span class=\"snippet-completion\">#{snippetText}</span>"
        @snippetMarkerChar

    # Add spans for replacement prefix
    # e.g. replacement: 'abc(|, |)f'
    # ->   highlightedHTML: '<span class="character-match">a</span>bc(|, |)f'
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

    # Place the snippets back at the placeholders
    # e.g. highlightedHTML: '<span class="character-match">a</span>bc(|, |)f'
    # ->   highlightedHTML: '<span class="character-match">a</span>bc(<span class="snippet-completion">d</span>, <span class="snippet-completion">e</span>)f'
    if snippetCompletions.length
      completionIndex = 0
      highlightedHTML = highlightedHTML.replace @snippetMarkerRegex, (match, snippetText) ->
        snippetCompletions[completionIndex++]

    highlightedHTML

  dispose: ->
    @subscriptions.dispose()
    @parentNode?.removeChild(this)

module.exports = SuggestionListElement = document.registerElement('autocomplete-suggestion-list', {prototype: SuggestionListElement.prototype})
