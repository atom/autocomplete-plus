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

  describe 'findSnippets', ->
    it 'has no results when no snippets exist', ->
      expect(suggestionListElement.findSnippets('hello')).toEqual([])

    it 'has no results when only empty snippets exist', ->
      expect(suggestionListElement.findSnippets('hello$0')).toEqual([])
      expect(suggestionListElement.findSnippets('hello${0}')).toEqual([])
      expect(suggestionListElement.findSnippets('hello${0}')).toEqual([])
      expect(suggestionListElement.findSnippets('hello$0')).toEqual([])
      expect(suggestionListElement.findSnippets('$0hello')).toEqual([])
      expect(suggestionListElement.findSnippets('hello$0hello')).toEqual([])
      expect(suggestionListElement.findSnippets('hello$1000hello')).toEqual([])
      expect(suggestionListElement.findSnippets('hello${0}')).toEqual([])
      expect(suggestionListElement.findSnippets('${0}hello')).toEqual([])
      expect(suggestionListElement.findSnippets('hello${0}hello')).toEqual([])
      expect(suggestionListElement.findSnippets('hello${1000}hello')).toEqual([])
      expect(suggestionListElement.findSnippets('hello${0:}')).toEqual([])
      expect(suggestionListElement.findSnippets('${0:}hello')).toEqual([])
      expect(suggestionListElement.findSnippets('hello${0:}hello')).toEqual([])
      expect(suggestionListElement.findSnippets('hello${1000:}hello')).toEqual([])

    it 'identifies a single snippet', ->
      # Without escaped right brace
      expect(suggestionListElement.findSnippets('${0:hello}').length).toEqual(1)
      expect(suggestionListElement.findSnippets('${0:hello}')[0]).toBeDefined()
      expect(suggestionListElement.findSnippets('${0:hello}')[0].snippetStart).toEqual(0)
      expect(suggestionListElement.findSnippets('${0:hello}')[0].snippetEnd).toEqual(9)
      expect(suggestionListElement.findSnippets('${0:hello}')[0].bodyStart).toEqual(4)
      expect(suggestionListElement.findSnippets('${0:hello}')[0].bodyEnd).toEqual(8)
      expect(suggestionListElement.findSnippets('${0:hello}')[0].skipChars.length).toEqual(0)

      # With escaped right brace
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}').length).toEqual(1)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}')[0]).toBeDefined()
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}')[0].snippetStart).toEqual(0)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}')[0].snippetEnd).toEqual(13)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}')[0].bodyStart).toEqual(4)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}')[0].bodyEnd).toEqual(12)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}')[0].skipChars.length).toEqual(2)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}')[0].skipChars[0]).toEqual(10)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}')[0].skipChars[1]).toEqual(11)

    it 'identifies a snippet surrounded by text', ->
      # Without escaped right brace
      expect(suggestionListElement.findSnippets('hello${0:hello}').length).toEqual(1)
      expect(suggestionListElement.findSnippets('hello${0:hello}')[0]).toBeDefined()
      expect(suggestionListElement.findSnippets('hello${0:hello}')[0].snippetStart).toEqual(5)
      expect(suggestionListElement.findSnippets('hello${0:hello}')[0].snippetEnd).toEqual(14)
      expect(suggestionListElement.findSnippets('hello${0:hello}')[0].bodyStart).toEqual(9)
      expect(suggestionListElement.findSnippets('hello${0:hello}')[0].bodyEnd).toEqual(13)
      expect(suggestionListElement.findSnippets('hello${0:hello}')[0].skipChars.length).toEqual(0)
      expect(suggestionListElement.findSnippets('${0:hello}hello').length).toEqual(1)
      expect(suggestionListElement.findSnippets('${0:hello}hello')[0]).toBeDefined()
      expect(suggestionListElement.findSnippets('${0:hello}hello')[0].snippetStart).toEqual(0)
      expect(suggestionListElement.findSnippets('${0:hello}hello')[0].snippetEnd).toEqual(9)
      expect(suggestionListElement.findSnippets('${0:hello}hello')[0].bodyStart).toEqual(4)
      expect(suggestionListElement.findSnippets('${0:hello}hello')[0].bodyEnd).toEqual(8)
      expect(suggestionListElement.findSnippets('${0:hello}hello')[0].skipChars.length).toEqual(0)
      expect(suggestionListElement.findSnippets('hello${0:hello}hello').length).toEqual(1)
      expect(suggestionListElement.findSnippets('hello${0:hello}hello')[0]).toBeDefined()
      expect(suggestionListElement.findSnippets('hello${0:hello}hello')[0].snippetStart).toEqual(5)
      expect(suggestionListElement.findSnippets('hello${0:hello}hello')[0].snippetEnd).toEqual(14)
      expect(suggestionListElement.findSnippets('hello${0:hello}hello')[0].bodyStart).toEqual(9)
      expect(suggestionListElement.findSnippets('hello${0:hello}hello')[0].bodyEnd).toEqual(13)
      expect(suggestionListElement.findSnippets('hello${0:hello}hello')[0].skipChars.length).toEqual(0)

      # With escaped right brace
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}').length).toEqual(1)
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}')[0]).toBeDefined()
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}')[0].snippetStart).toEqual(5)
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}')[0].snippetEnd).toEqual(18)
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}')[0].bodyStart).toEqual(9)
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}')[0].bodyEnd).toEqual(17)
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}')[0].skipChars.length).toEqual(2)
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}')[0].skipChars[0]).toEqual(15)
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}')[0].skipChars[1]).toEqual(16)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}hello').length).toEqual(1)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}hello')[0]).toBeDefined()
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}hello')[0].snippetStart).toEqual(0)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}hello')[0].snippetEnd).toEqual(13)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}hello')[0].bodyStart).toEqual(4)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}hello')[0].bodyEnd).toEqual(12)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}hello')[0].skipChars.length).toEqual(2)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}hello')[0].skipChars[0]).toEqual(10)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}hello')[0].skipChars[1]).toEqual(11)
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}hello').length).toEqual(1)
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}hello')[0]).toBeDefined()
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}hello')[0].snippetStart).toEqual(5)
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}hello')[0].snippetEnd).toEqual(18)
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}hello')[0].bodyStart).toEqual(9)
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}hello')[0].bodyEnd).toEqual(17)
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}hello')[0].skipChars.length).toEqual(2)
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}hello')[0].skipChars[0]).toEqual(15)
      expect(suggestionListElement.findSnippets('hello${0:hello{\\\\}}hello')[0].skipChars[1]).toEqual(16)

    it 'identifies multiple snippets', ->
      # Without escaped right brace
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}').length).toEqual(2)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')[0]).toBeDefined()
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')[0].snippetStart).toEqual(0)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')[0].snippetEnd).toEqual(9)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')[0].bodyStart).toEqual(4)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')[0].bodyEnd).toEqual(8)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')[0].skipChars.length).toEqual(0)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')[1]).toBeDefined()
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')[1].snippetStart).toEqual(10)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')[1].snippetEnd).toEqual(19)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')[1].bodyStart).toEqual(14)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')[1].bodyEnd).toEqual(18)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')[1].skipChars.length).toEqual(0)

      # With escaped right brace
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}${1:world}').length).toEqual(2)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}${1:world}')[0]).toBeDefined()
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}${1:world}')[0].snippetStart).toEqual(0)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}${1:world}')[0].snippetEnd).toEqual(13)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}${1:world}')[0].bodyStart).toEqual(4)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}${1:world}')[0].bodyEnd).toEqual(12)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}${1:world}')[0].skipChars.length).toEqual(2)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}${1:world}')[0].skipChars[0]).toEqual(10)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}${1:world}')[0].skipChars[1]).toEqual(11)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}${1:world}')[1]).toBeDefined()
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}${1:world}')[1].snippetStart).toEqual(14)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}${1:world}')[1].snippetEnd).toEqual(23)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}${1:world}')[1].bodyStart).toEqual(18)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}${1:world}')[1].bodyEnd).toEqual(22)
      expect(suggestionListElement.findSnippets('${0:hello{\\\\}}${1:world}')[1].skipChars.length).toEqual(0)

    it 'identifies multiple snippets surrounded by text', ->
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}').length).toEqual(2)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')[0]).toBeDefined()
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')[0].snippetStart).toEqual(5)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')[0].snippetEnd).toEqual(14)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')[0].bodyStart).toEqual(9)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')[0].bodyEnd).toEqual(13)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')[0].skipChars.length).toEqual(0)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')[1]).toBeDefined()
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')[1].snippetStart).toEqual(15)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')[1].snippetEnd).toEqual(24)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')[1].bodyStart).toEqual(19)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')[1].bodyEnd).toEqual(23)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')[1].skipChars.length).toEqual(0)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello').length).toEqual(2)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')[0]).toBeDefined()
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')[0].snippetStart).toEqual(0)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')[0].snippetEnd).toEqual(9)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')[0].bodyStart).toEqual(4)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')[0].bodyEnd).toEqual(8)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')[0].skipChars.length).toEqual(0)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')[1]).toBeDefined()
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')[1].snippetStart).toEqual(10)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')[1].snippetEnd).toEqual(19)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')[1].bodyStart).toEqual(14)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')[1].bodyEnd).toEqual(18)
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')[1].skipChars.length).toEqual(0)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello').length).toEqual(2)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')[0]).toBeDefined()
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')[0].snippetStart).toEqual(5)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')[0].snippetEnd).toEqual(14)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')[0].bodyStart).toEqual(9)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')[0].bodyEnd).toEqual(13)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')[0].skipChars.length).toEqual(0)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')[1]).toBeDefined()
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')[1].snippetStart).toEqual(15)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')[1].snippetEnd).toEqual(24)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')[1].bodyStart).toEqual(19)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')[1].bodyEnd).toEqual(23)
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')[1].skipChars.length).toEqual(0)

  describe 'removeEmptySnippets', ->
    it 'removes an empty snippet group', ->
      expect(suggestionListElement.removeEmptySnippets('$0')).toBe('')
      expect(suggestionListElement.removeEmptySnippets('$1000')).toBe('')

    it 'removes an empty snippet group with surrounding text', ->
      expect(suggestionListElement.removeEmptySnippets('hello$0')).toBe('hello')
      expect(suggestionListElement.removeEmptySnippets('$0hello')).toBe('hello')
      expect(suggestionListElement.removeEmptySnippets('hello$0hello')).toBe('hellohello')
      expect(suggestionListElement.removeEmptySnippets('hello$1000hello')).toBe('hellohello')

    it 'removes an empty snippet group with braces', ->
      expect(suggestionListElement.removeEmptySnippets('${0}')).toBe('')
      expect(suggestionListElement.removeEmptySnippets('${1000}')).toBe('')

    it 'removes an empty snippet group with braces with surrounding text', ->
      expect(suggestionListElement.removeEmptySnippets('hello${0}')).toBe('hello')
      expect(suggestionListElement.removeEmptySnippets('${0}hello')).toBe('hello')
      expect(suggestionListElement.removeEmptySnippets('hello${0}hello')).toBe('hellohello')
      expect(suggestionListElement.removeEmptySnippets('hello${1000}hello')).toBe('hellohello')

    it 'removes an empty snippet group with braces and a colon', ->
      expect(suggestionListElement.removeEmptySnippets('${0:}')).toBe('')
      expect(suggestionListElement.removeEmptySnippets('${1000:}')).toBe('')

    it 'removes an empty snippet group with braces and a colon with surrounding text', ->
      expect(suggestionListElement.removeEmptySnippets('hello${0:}')).toBe('hello')
      expect(suggestionListElement.removeEmptySnippets('${0:}hello')).toBe('hello')
      expect(suggestionListElement.removeEmptySnippets('hello${0:}hello')).toBe('hellohello')
      expect(suggestionListElement.removeEmptySnippets('hello${1000:}hello')).toBe('hellohello')

  describe 'enhanceSnippet', ->
    it 'wraps a snippet group', ->
      expect(suggestionListElement.enhanceSnippet('${0:hello}')).toBe('<span class="snippet-completion">hello</span>')
      expect(suggestionListElement.enhanceSnippet('${1000:hello}')).toBe('<span class="snippet-completion">hello</span>')

    it 'tolerates an escaped right brace', ->
      expect(suggestionListElement.enhanceSnippet('${0:hello{\\\\}}')).toBe('<span class="snippet-completion">hello{}</span>')
      expect(suggestionListElement.enhanceSnippet('${1000:hello{\\\\}}')).toBe('<span class="snippet-completion">hello{}</span>')
