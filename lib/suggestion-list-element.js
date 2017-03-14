const {CompositeDisposable} = require('atom')
const SnippetParser = require('./snippet-parser')
const {isString} = require('./type-helpers')
const fuzzaldrinPlus = require('fuzzaldrin-plus')
const marked = require('marked')

const ItemTemplate = `<span class="icon-container"></span>
  <span class="left-label"></span>
  <span class="word-container">
    <span class="word"></span>
  </span>
  <span class="right-label"></span>`

const ListTemplate = `<div class="suggestion-list-scroller">
    <ol class="list-group"></ol>
  </div>
  <div class="suggestion-description">
    <span class="suggestion-description-content"></span>
    <a class="suggestion-description-more-link" href="#">More..</a>
  </div>`

const IconTemplate = '<i class="icon"></i>'

const DefaultSuggestionTypeIconHTML = {
  'snippet': '<i class="icon-move-right"></i>',
  'import': '<i class="icon-package"></i>',
  'require': '<i class="icon-package"></i>',
  'module': '<i class="icon-package"></i>',
  'package': '<i class="icon-package"></i>',
  'tag': '<i class="icon-code"></i>',
  'attribute': '<i class="icon-tag"></i>'
}

const SnippetStart = 1
const SnippetEnd = 2
const SnippetStartAndEnd = 3

module.exports = class SuggestionListElement {
  constructor (model) {
    this.element = document.createElement('autocomplete-suggestion-list')
    this.maxItems = 200
    this.emptySnippetGroupRegex = /(\$\{\d+:\})|(\$\{\d+\})|(\$\d+)/ig
    this.slashesInSnippetRegex = /\\\\/g
    this.nodePool = null
    this.subscriptions = new CompositeDisposable()
    this.element.classList.add('popover-list', 'select-list', 'autocomplete-suggestion-list')
    this.registerMouseHandling()
    this.snippetParser = new SnippetParser()
    this.nodePool = []
    this.element.innerHTML = ListTemplate
    this.ol = this.element.querySelector('.list-group')
    this.scroller = this.element.querySelector('.suggestion-list-scroller')
    this.descriptionContainer = this.element.querySelector('.suggestion-description')
    this.descriptionContent = this.element.querySelector('.suggestion-description-content')
    this.descriptionMoreLink = this.element.querySelector('.suggestion-description-more-link')

    this.model = model
    if (this.model == null) { return }
    this.subscriptions.add(this.model.onDidChangeItems(this.itemsChanged.bind(this)))
    this.subscriptions.add(this.model.onDidSelectNext(this.moveSelectionDown.bind(this)))
    this.subscriptions.add(this.model.onDidSelectPrevious(this.moveSelectionUp.bind(this)))
    this.subscriptions.add(this.model.onDidSelectPageUp(this.moveSelectionPageUp.bind(this)))
    this.subscriptions.add(this.model.onDidSelectPageDown(this.moveSelectionPageDown.bind(this)))
    this.subscriptions.add(this.model.onDidSelectTop(this.moveSelectionToTop.bind(this)))
    this.subscriptions.add(this.model.onDidSelectBottom(this.moveSelectionToBottom.bind(this)))
    this.subscriptions.add(this.model.onDidConfirmSelection(this.confirmSelection.bind(this)))
    this.subscriptions.add(this.model.onDidconfirmSelectionIfNonDefault(this.confirmSelectionIfNonDefault.bind(this)))
    this.subscriptions.add(this.model.onDidDispose(this.dispose.bind(this)))

    this.subscriptions.add(atom.config.observe('autocomplete-plus.suggestionListFollows', suggestionListFollows => {
      this.suggestionListFollows = suggestionListFollows
    }))
    this.subscriptions.add(atom.config.observe('autocomplete-plus.maxVisibleSuggestions', maxVisibleSuggestions => {
      this.maxVisibleSuggestions = maxVisibleSuggestions
    }))
    this.subscriptions.add(atom.config.observe('autocomplete-plus.useAlternateScoring', useAlternateScoring => {
      this.useAlternateScoring = useAlternateScoring
    }))
  }

  didAttach () {
    this.itemsChanged()
  }

  // This should be unnecessary but the events we need to override
  // are handled at a level that can't be blocked by react synthetic
  // events because they are handled at the document
  registerMouseHandling () {
    this.element.onmousewheel = event => event.stopPropagation()
    this.element.onmousedown = (event) => {
      const item = this.findItem(event)
      if (item && item.dataset && item.dataset.index) {
        this.selectedIndex = item.dataset.index
        event.stopPropagation()
      }
    }

    this.element.onmouseup = (event) => {
      const item = this.findItem(event)
      if (item && item.dataset && item.dataset.index) {
        event.stopPropagation()
        this.confirmSelection()
      }
    }
  }

  findItem (event) {
    let item = event.target
    while (item.tagName !== 'LI' && item !== this.element) { item = item.parentNode }
    if (item.tagName === 'LI') { return item }
  }

  updateDescription (item) {
    if (!item) {
      if (this.model && this.model.items) {
        item = this.model.items[this.selectedIndex]
      }
    }
    if (!item) {
      return
    }

    if (item.descriptionMarkdown && item.descriptionMarkdown.length > 0) {
      this.descriptionContainer.style.display = 'block'
      this.descriptionContent.innerHTML = marked.parse(item.descriptionMarkdown, {sanitize: true})
      this.setDescriptionMoreLink(item)
    } else if (item.description && item.description.length > 0) {
      this.descriptionContainer.style.display = 'block'
      this.descriptionContent.textContent = item.description
      this.setDescriptionMoreLink(item)
    } else {
      this.descriptionContainer.style.display = 'none'
    }
  }

  setDescriptionMoreLink (item) {
    if ((item.descriptionMoreURL != null) && (item.descriptionMoreURL.length != null)) {
      this.descriptionMoreLink.style.display = 'inline'
      this.descriptionMoreLink.setAttribute('href', item.descriptionMoreURL)
    } else {
      this.descriptionMoreLink.style.display = 'none'
      this.descriptionMoreLink.setAttribute('href', '#')
    }
  }

  itemsChanged () {
    if (this.model && this.model.items && this.model.items.length) {
      return this.render()
    } else {
      return this.returnItemsToPool(0)
    }
  }

  render () {
    this.nonDefaultIndex = false
    this.selectedIndex = 0
    if (atom.views.pollAfterNextUpdate) {
      atom.views.pollAfterNextUpdate()
    }

    atom.views.updateDocument(this.renderItems.bind(this))
    atom.views.readDocument(this.readUIPropsFromDOM.bind(this))
  }

  moveSelectionUp () {
    if (this.selectedIndex > 0) {
      return this.setSelectedIndex(this.selectedIndex - 1)
    } else {
      return this.setSelectedIndex(this.visibleItems().length - 1)
    }
  }

  moveSelectionDown () {
    if (this.selectedIndex < (this.visibleItems().length - 1)) {
      return this.setSelectedIndex(this.selectedIndex + 1)
    } else {
      return this.setSelectedIndex(0)
    }
  }

  moveSelectionPageUp () {
    const newIndex = Math.max(0, this.selectedIndex - this.maxVisibleSuggestions)
    if (this.selectedIndex !== newIndex) { return this.setSelectedIndex(newIndex) }
  }

  moveSelectionPageDown () {
    const itemsLength = this.visibleItems().length
    const newIndex = Math.min(itemsLength - 1, this.selectedIndex + this.maxVisibleSuggestions)
    if (this.selectedIndex !== newIndex) { return this.setSelectedIndex(newIndex) }
  }

  moveSelectionToTop () {
    const newIndex = 0
    if (this.selectedIndex !== newIndex) { return this.setSelectedIndex(newIndex) }
  }

  moveSelectionToBottom () {
    const newIndex = this.visibleItems().length - 1
    if (this.selectedIndex !== newIndex) { return this.setSelectedIndex(newIndex) }
  }

  setSelectedIndex (index) {
    this.nonDefaultIndex = true
    this.selectedIndex = index
    return atom.views.updateDocument(this.renderSelectedItem.bind(this))
  }

  visibleItems () {
    if (this.model && this.model.items) {
      return this.model.items.slice(0, this.maxItems)
    }
  }

  // Private: Get the currently selected item
  //
  // Returns the selected {Object}
  getSelectedItem () {
    if (this.model && this.model.items) {
      return this.model.items[this.selectedIndex]
    }
  }

  // Private: Confirms the currently selected item or cancels the list view
  // if no item has been selected
  confirmSelection () {
    if (!this.model.isActive()) { return }
    const item = this.getSelectedItem()
    if (item != null) {
      return this.model.confirm(item)
    } else {
      return this.model.cancel()
    }
  }

  // Private: Confirms the currently selected item only if it is not the default
  // item or cancels the view if none has been selected.
  confirmSelectionIfNonDefault (event) {
    if (!this.model.isActive()) { return }
    if (this.nonDefaultIndex) {
      return this.confirmSelection()
    } else {
      this.model.cancel()
      return event.abortKeyBinding()
    }
  }

  renderItems () {
    let left
    this.element.style.width = null
    const items = (left = this.visibleItems()) != null ? left : []
    let longestDesc = 0
    let longestDescIndex = null
    for (let index = 0; index < items.length; index++) {
      const item = items[index]
      this.renderItem(item, index)
      const descLength = this.descriptionLength(item)
      if (descLength > longestDesc) {
        longestDesc = descLength
        longestDescIndex = index
      }
    }
    this.updateDescription(items[longestDescIndex])
    return this.returnItemsToPool(items.length)
  }

  returnItemsToPool (pivotIndex) {
    if (!this.ol) { return }

    let li = this.ol.childNodes[pivotIndex]
    while ((this.ol != null) && li) {
      li.remove()
      this.nodePool.push(li)
      li = this.ol.childNodes[pivotIndex]
    }
  }

  descriptionLength (item) {
    let count = 0
    if (item.description != null) {
      count += item.description.length
    }
    if (item.descriptionMoreURL != null) {
      count += 6
    }
    return count
  }

  renderSelectedItem () {
    if (this.selectedLi && this.selectedLi.classList) {
      this.selectedLi.classList.remove('selected')
    }

    this.selectedLi = this.ol.childNodes[this.selectedIndex]
    if (this.selectedLi != null) {
      this.selectedLi.classList.add('selected')
      this.scrollSelectedItemIntoView()
      return this.updateDescription()
    }
  }

  // This is reading the DOM in the updateDOM cycle. If we dont, there is a flicker :/
  scrollSelectedItemIntoView () {
    const { scrollTop } = this.scroller
    const selectedItemTop = this.selectedLi.offsetTop
    if (selectedItemTop < scrollTop) {
      // scroll up
      this.scroller.scrollTop = selectedItemTop
      return
    }

    const { itemHeight } = this.uiProps
    const scrollerHeight = (this.maxVisibleSuggestions * itemHeight) + this.uiProps.paddingHeight
    if (selectedItemTop + itemHeight > scrollTop + scrollerHeight) {
      // scroll down
      this.scroller.scrollTop = (selectedItemTop - scrollerHeight) + itemHeight
    }
  }

  readUIPropsFromDOM () {
    let wordContainer
    if (this.selectedLi) {
      wordContainer = this.selectedLi.querySelector('.word-container')
    }

    if (!this.uiProps) { this.uiProps = {} }
    this.uiProps.width = this.element.offsetWidth + 1
    this.uiProps.marginLeft = 0
    if (wordContainer && wordContainer.offsetLeft) {
      this.uiProps.marginLeft = -wordContainer.offsetLeft
    }
    if (!this.uiProps.itemHeight) {
      this.uiProps.itemHeight = this.selectedLi.offsetHeight
    }
    if (!this.uiProps.paddingHeight) {
      this.uiProps.paddingHeight = parseInt(getComputedStyle(this.element)['padding-top']) + parseInt(getComputedStyle(this.element)['padding-bottom'])
      if (!this.uiProps.paddingHeight) {
        this.uiProps.paddingHeight = 0
      }
    }

    // Update UI during this read, so that when polling the document the latest
    // changes can be picked up.
    return this.updateUIForChangedProps()
  }

  updateUIForChangedProps () {
    this.scroller.style['max-height'] = `${(this.maxVisibleSuggestions * this.uiProps.itemHeight) + this.uiProps.paddingHeight}px`
    this.element.style.width = `${this.uiProps.width}px`
    if (this.suggestionListFollows === 'Word') {
      this.element.style['margin-left'] = `${this.uiProps.marginLeft}px`
    }
    return this.updateDescription()
  }

  // Splits the classes on spaces so as not to anger the DOM gods
  addClassToElement (element, classNames) {
    if (!classNames) { return }
    const classes = classNames.split(' ')
    if (classes) {
      for (let i = 0; i < classes.length; i++) {
        let className = classes[i]
        className = className.trim()
        if (className) { element.classList.add(className) }
      }
    }
  }

  renderItem ({iconHTML, type, snippet, text, displayText, className, replacementPrefix, leftLabel, leftLabelHTML, rightLabel, rightLabelHTML}, index) {
    let li = this.ol.childNodes[index]
    if (!li) {
      if (this.nodepool && this.nodePool.length > 0) {
        li = this.nodePool.pop()
      } else {
        li = document.createElement('li')
        li.innerHTML = ItemTemplate
      }
      li.dataset.index = index
      this.ol.appendChild(li)
    }

    li.className = ''
    if (index === this.selectedIndex) { li.classList.add('selected') }
    if (className) { this.addClassToElement(li, className) }
    if (index === this.selectedIndex) { this.selectedLi = li }

    const typeIconContainer = li.querySelector('.icon-container')
    typeIconContainer.innerHTML = ''

    const sanitizedType = escapeHtml(isString(type) ? type : '')
    const sanitizedIconHTML = isString(iconHTML) ? iconHTML : undefined
    const defaultLetterIconHTML = sanitizedType ? `<span class="icon-letter">${sanitizedType[0]}</span>` : ''
    const defaultIconHTML = DefaultSuggestionTypeIconHTML[sanitizedType] != null ? DefaultSuggestionTypeIconHTML[sanitizedType] : defaultLetterIconHTML
    if ((sanitizedIconHTML || defaultIconHTML) && iconHTML !== false) {
      typeIconContainer.innerHTML = IconTemplate
      const typeIcon = typeIconContainer.childNodes[0]
      typeIcon.innerHTML = sanitizedIconHTML != null ? sanitizedIconHTML : defaultIconHTML
      if (type) { this.addClassToElement(typeIcon, type) }
    }

    const wordSpan = li.querySelector('.word')
    wordSpan.innerHTML = this.getDisplayHTML(text, snippet, displayText, replacementPrefix)

    const leftLabelSpan = li.querySelector('.left-label')
    if (leftLabelHTML != null) {
      leftLabelSpan.innerHTML = leftLabelHTML
    } else if (leftLabel != null) {
      leftLabelSpan.textContent = leftLabel
    } else {
      leftLabelSpan.textContent = ''
    }

    const rightLabelSpan = li.querySelector('.right-label')
    if (rightLabelHTML != null) {
      rightLabelSpan.innerHTML = rightLabelHTML
    } else if (rightLabel != null) {
      rightLabelSpan.textContent = rightLabel
    } else {
      rightLabelSpan.textContent = ''
    }
  }

  getDisplayHTML (text, snippet, displayText, replacementPrefix) {
    let replacementText = text
    let snippetIndices
    if (typeof displayText === 'string') {
      replacementText = displayText
    } else if (typeof snippet === 'string') {
      replacementText = this.removeEmptySnippets(snippet)
      const snippets = this.snippetParser.findSnippets(replacementText)
      replacementText = this.removeSnippetsFromText(snippets, replacementText)
      snippetIndices = this.findSnippetIndices(snippets)
    }
    const characterMatchIndices = this.findCharacterMatchIndices(replacementText, replacementPrefix)

    let displayHTML = ''
    for (let index = 0; index < replacementText.length; index++) {
      if (snippetIndices && (snippetIndices[index] === SnippetStart || snippetIndices[index] === SnippetStartAndEnd)) {
        displayHTML += '<span class="snippet-completion">'
      }
      if (characterMatchIndices && characterMatchIndices[index]) {
        displayHTML += `<span class="character-match">${escapeHtml(replacementText[index])}</span>`
      } else {
        displayHTML += escapeHtml(replacementText[index])
      }
      if (snippetIndices && (snippetIndices[index] === SnippetEnd || snippetIndices[index] === SnippetStartAndEnd)) {
        displayHTML += '</span>'
      }
    }
    return displayHTML
  }

  removeEmptySnippets (text) {
    if (!text || !text.length || text.indexOf('$') === -1) { return text } // No snippets
    return text.replace(this.emptySnippetGroupRegex, '') // Remove all occurrences of $0 or ${0} or ${0:}
  }

  // Will convert 'abc(${1:d}, ${2:e})f' => 'abc(d, e)f'
  //
  // * `snippets` {Array} from `SnippetParser.findSnippets`
  // * `text` {String} to remove snippets from
  //
  // Returns {String}
  removeSnippetsFromText (snippets, text) {
    if (!text || !text.length || !snippets || !snippets.length) {
      return text
    }
    let index = 0
    let result = ''
    for (const {snippetStart, snippetEnd, body} of snippets) {
      result += text.slice(index, snippetStart) + body
      index = snippetEnd + 1
    }
    if (index !== text.length) {
      result += text.slice(index, text.length)
    }
    result = result.replace(this.slashesInSnippetRegex, '\\')
    return result
  }

  // Computes the indices of snippets in the resulting string from
  // `removeSnippetsFromText`.
  //
  // * `snippets` {Array} from `SnippetParser.findSnippets`
  //
  // e.g. A replacement of 'abc(${1:d})e' is replaced to 'abc(d)e' will result in
  //
  // `{4: SnippetStartAndEnd}`
  //
  // Returns {Object} of {index: SnippetStart|End|StartAndEnd}
  findSnippetIndices (snippets) {
    if (!snippets) {
      return
    }
    const indices = {}
    let offsetAccumulator = 0
    for (const {snippetStart, snippetEnd, body} of snippets) {
      const bodyLength = body.length
      const snippetLength = (snippetEnd - snippetStart) + 1
      const startIndex = snippetStart - offsetAccumulator
      const endIndex = (startIndex + bodyLength) - 1
      offsetAccumulator += snippetLength - bodyLength

      if (startIndex === endIndex) {
        indices[startIndex] = SnippetStartAndEnd
      } else {
        indices[startIndex] = SnippetStart
        indices[endIndex] = SnippetEnd
      }
    }

    return indices
  }

  // Finds the indices of the chars in text that are matched by replacementPrefix
  //
  // e.g. text = 'abcde', replacementPrefix = 'acd' Will result in
  //
  // {0: true, 2: true, 3: true}
  //
  // Returns an {Object}
  findCharacterMatchIndices (text, replacementPrefix) {
    if (!text || !text.length || !replacementPrefix || !replacementPrefix.length) { return }
    const matches = {}
    if (this.useAlternateScoring) {
      const matchIndices = fuzzaldrinPlus.match(text, replacementPrefix)
      for (const i of matchIndices) {
        matches[i] = true
      }
    } else {
      let wordIndex = 0
      for (let i = 0; i < replacementPrefix.length; i++) {
        const ch = replacementPrefix[i]
        while (wordIndex < text.length && text[wordIndex].toLowerCase() !== ch.toLowerCase()) {
          wordIndex += 1
        }
        if (wordIndex >= text.length) { break }
        matches[wordIndex] = true
        wordIndex += 1
      }
    }
    return matches
  }

  dispose () {
    this.subscriptions.dispose()
    if (this.parentNode) {
      this.parentNode.removeChild(this)
    }
  }
}

// https://github.com/component/escape-html/blob/master/index.js
const escapeHtml = (html) => {
  return String(html)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
}
