SuggestionListElement = require '../lib/suggestion-list-element'
_ = require 'underscore-plus'

describe 'Suggestion List Element', ->
  [suggestionListElement] = []

  beforeEach ->
    suggestionListElement = new SuggestionListElement()

  afterEach ->
    suggestionListElement?.dispose()
    suggestionListElement = null

  describe 'getHighlightedHTML', ->
    it 'replaces a snippet with no escaped right braces', ->
      text = ''
      snippet = 'abc(${1:d}, ${2:e})f'
      replacementPrefix = 'a'
      expect(suggestionListElement.getHighlightedHTML(text, snippet, replacementPrefix)).toBe('<span class="character-match">a</span>bc(<span class="snippet-completion">d</span>, <span class="snippet-completion">e</span>)f')

    it 'replaces a snippet with escaped right braces', ->
      text = ''
      snippet = 'abc(${1:d}, ${2:e})f ${3:interface{\\\\}}'
      replacementPrefix = 'a'
      expect(suggestionListElement.getHighlightedHTML(text, snippet, replacementPrefix)).toBe('<span class="character-match">a</span>bc(<span class="snippet-completion">d</span>, <span class="snippet-completion">e</span>)f <span class="snippet-completion">interface{}</span>')

    it 'replaces a snippet with elements that have no text', ->
      text = ''
      snippet = 'abc(${1:d}, ${2:e})f${3}'
      replacementPrefix = 'a'
      expect(suggestionListElement.getHighlightedHTML(text, snippet, replacementPrefix)).toBe('<span class="character-match">a</span>bc(<span class="snippet-completion">d</span>, <span class="snippet-completion">e</span>)f')

  describe 'enhanceSnippet', ->
    it 'removes an empty snippet group', ->
      expect(suggestionListElement.enhanceSnippet('$0')).toBe('')
      expect(suggestionListElement.enhanceSnippet('$1000')).toBe('')

    it 'removes an empty snippet group with surrounding text', ->
      expect(suggestionListElement.enhanceSnippet('hello$0')).toBe('hello')
      expect(suggestionListElement.enhanceSnippet('$0hello')).toBe('hello')
      expect(suggestionListElement.enhanceSnippet('hello$0hello')).toBe('hellohello')
      expect(suggestionListElement.enhanceSnippet('hello$1000hello')).toBe('hellohello')

    it 'removes an empty snippet group with braces', ->
      expect(suggestionListElement.enhanceSnippet('${0}')).toBe('')
      expect(suggestionListElement.enhanceSnippet('${1000}')).toBe('')

    it 'removes an empty snippet group with braces with surrounding text', ->
      expect(suggestionListElement.enhanceSnippet('hello${0}')).toBe('hello')
      expect(suggestionListElement.enhanceSnippet('${0}hello')).toBe('hello')
      expect(suggestionListElement.enhanceSnippet('hello${0}hello')).toBe('hellohello')
      expect(suggestionListElement.enhanceSnippet('hello${1000}hello')).toBe('hellohello')

    it 'removes an empty snippet group with braces and a colon', ->
      expect(suggestionListElement.enhanceSnippet('${0:}')).toBe('')
      expect(suggestionListElement.enhanceSnippet('${1000:}')).toBe('')

    it 'removes an empty snippet group with braces and a colon with surrounding text', ->
      expect(suggestionListElement.enhanceSnippet('hello${0:}')).toBe('hello')
      expect(suggestionListElement.enhanceSnippet('${0:}hello')).toBe('hello')
      expect(suggestionListElement.enhanceSnippet('hello${0:}hello')).toBe('hellohello')
      expect(suggestionListElement.enhanceSnippet('hello${1000:}hello')).toBe('hellohello')

    it 'wraps a snippet group', ->
      expect(suggestionListElement.enhanceSnippet('${0:hello}')).toBe('<span class="snippet-completion">hello</span>')
      expect(suggestionListElement.enhanceSnippet('${1000:hello}')).toBe('<span class="snippet-completion">hello</span>')

    it 'tolerates an escaped right brace', ->
      expect(suggestionListElement.enhanceSnippet('${0:hello{\\\\}}')).toBe('<span class="snippet-completion">hello{}</span>')
      expect(suggestionListElement.enhanceSnippet('${1000:hello{\\\\}}')).toBe('<span class="snippet-completion">hello{}</span>')
