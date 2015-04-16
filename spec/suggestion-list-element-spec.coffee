SuggestionListElement = require '../lib/suggestion-list-element'
_ = require 'underscore-plus'

describe 'Suggestion List Element', ->
  [suggestionListElement] = []

  beforeEach ->
    suggestionListElement = new SuggestionListElement()

  afterEach ->
    suggestionListElement?.dispose()
    suggestionListElement = null

  describe 'getDisplayHTML', ->
    it 'handles the empty string in the text field', ->
      text = ''
      snippet = undefined
      replacementPrefix = 'a'
      html = suggestionListElement.getDisplayHTML(text, snippet, replacementPrefix)
      expect(html).toBe('')

    it 'handles the empty string in the snippet field', ->
      text = undefined
      snippet = ''
      replacementPrefix = 'a'
      html = suggestionListElement.getDisplayHTML(text, snippet, replacementPrefix)
      expect(html).toBe('')

    it 'handles an empty prefix', ->
      text = undefined
      snippet = 'abc'
      replacementPrefix = ''
      html = suggestionListElement.getDisplayHTML(text, snippet, replacementPrefix)
      expect(html).toBe('abc')

    it 'outputs correct html when there are no snippets in the snippet field', ->
      text = ''
      snippet = 'abc(d, e)f'
      replacementPrefix = 'a'
      html = suggestionListElement.getDisplayHTML(text, snippet, replacementPrefix)
      expect(html).toBe('<span class="character-match">a</span>bc(d, e)f')

    it 'outputs correct html when there are character matches', ->
      text = ''
      snippet = 'abc(d, e)f'
      replacementPrefix = 'omg'
      html = suggestionListElement.getDisplayHTML(text, snippet, replacementPrefix)
      expect(html).toBe('abc(d, e)f')

    it 'outputs correct html when the text field is used', ->
      text = 'abc(d, e)f'
      snippet = undefined
      replacementPrefix = 'a'
      html = suggestionListElement.getDisplayHTML(text, snippet, replacementPrefix)
      expect(html).toBe('<span class="character-match">a</span>bc(d, e)f')

    it 'replaces a snippet with no escaped right braces', ->
      text = ''
      snippet = 'abc(${1:d}, ${2:e})f'
      replacementPrefix = 'a'
      html = suggestionListElement.getDisplayHTML(text, snippet, replacementPrefix)
      expect(html).toBe('<span class="character-match">a</span>bc(<span class="snippet-completion">d</span>, <span class="snippet-completion">e</span>)f')

    it 'replaces a snippet with no escaped right braces', ->
      text = ''
      snippet = 'text(${1:ab}, ${2:cd})'
      replacementPrefix = 'ta'
      html = suggestionListElement.getDisplayHTML(text, snippet, replacementPrefix)
      expect(html).toBe('<span class="character-match">t</span>ext(<span class="snippet-completion"><span class="character-match">a</span>b</span>, <span class="snippet-completion">cd</span>)')

    ffit 'replaces a snippet with escaped right braces', ->
      text = ''
      snippet = 'abc(${1:d}, ${2:e})f ${3:interface{\\}}'
      replacementPrefix = 'a'
      expect(suggestionListElement.getDisplayHTML(text, snippet, replacementPrefix)).toBe('<span class="character-match">a</span>bc(<span class="snippet-completion">d</span>, <span class="snippet-completion">e</span>)f <span class="snippet-completion">interface{}</span>')

    ffit 'replaces a snippet with escaped multiple right braces', ->
      text = ''
      snippet = 'abc(${1:d}, ${2:something{ok\\}}, ${3:e})f ${4:interface{\\}}'
      replacementPrefix = 'a'
      expect(suggestionListElement.getDisplayHTML(text, snippet, replacementPrefix)).toBe('<span class="character-match">a</span>bc(<span class="snippet-completion">d</span>, <span class="snippet-completion">something{ok}</span>, <span class="snippet-completion">e</span>)f <span class="snippet-completion">interface{}</span>')

    it 'replaces a snippet with elements that have no text', ->
      text = ''
      snippet = 'abc(${1:d}, ${2:e})f${3}'
      replacementPrefix = 'a'
      expect(suggestionListElement.getDisplayHTML(text, snippet, replacementPrefix)).toBe('<span class="character-match">a</span>bc(<span class="snippet-completion">d</span>, <span class="snippet-completion">e</span>)f')

  describe 'findCharacterMatches', ->
    assertMatches = (text, replacementPrefix, truthyIndices) ->
      text = suggestionListElement.removeEmptySnippets(text)
      snippets = suggestionListElement.findSnippets(text)
      text = suggestionListElement.removeSnippetsFromText(snippets, text)
      matches = suggestionListElement.findCharacterMatches(text, replacementPrefix)
      for i in [0...text.length]
        if truthyIndices.indexOf(i) isnt -1
          expect(matches["#{i}"]).toBeTruthy()
        else
          expect(matches["#{i}"]).toBeFalsy()

    it 'finds matches when no snippets exist', ->
      assertMatches('hello', '', [])
      assertMatches('hello', 'h', [0])
      assertMatches('hello', 'hl', [0,2])
      assertMatches('hello', 'hlo', [0,2,4])

    it 'finds matches when snippets exist', ->
      assertMatches('${0:hello}', '', [])
      assertMatches('${0:hello}', 'h', [0])
      assertMatches('${0:hello}', 'hl', [0,2])
      assertMatches('${0:hello}', 'hlo', [0,2,4])
      assertMatches('${0:hello}world', '', [])
      assertMatches('${0:hello}world', 'h', [0])
      assertMatches('${0:hello}world', 'hw', [0,5])
      assertMatches('${0:hello}world', 'hlw', [0,2,5])
      assertMatches('hello${0:world}', '', [])
      assertMatches('hello${0:world}', 'h', [0])
      assertMatches('hello${0:world}', 'hw', [0,5])
      assertMatches('hello${0:world}', 'hlw', [0,2,5])

  describe 'findSnippets', ->
    it 'has no results when no snippets exist', ->
      expect(suggestionListElement.findSnippets('hello')).toEqual({})

    it 'identifies a single snippet', ->
      # Without escaped right brace
      expect(suggestionListElement.findSnippets('${0:hello}')).toBeDefined()
      expect(suggestionListElement.findSnippets('${0:hello}')['0']).toEqual('start')
      expect(suggestionListElement.findSnippets('${0:hello}')['1']).toEqual('skip')
      expect(suggestionListElement.findSnippets('${0:hello}')['2']).toEqual('skip')
      expect(suggestionListElement.findSnippets('${0:hello}')['3']).toEqual('skip')
      expect(suggestionListElement.findSnippets('${0:hello}')['4']).toEqual('bodystart')
      expect(suggestionListElement.findSnippets('${0:hello}')['5']).toBeUndefined()
      expect(suggestionListElement.findSnippets('${0:hello}')['6']).toBeUndefined()
      expect(suggestionListElement.findSnippets('${0:hello}')['7']).toBeUndefined()
      expect(suggestionListElement.findSnippets('${0:hello}')['8']).toEqual('bodyend')
      expect(suggestionListElement.findSnippets('${0:hello}')['9']).toEqual('end')

      # With escaped right brace
      expect(suggestionListElement.findSnippets('${0:hello{\\}}')).toBeDefined()
      expect(suggestionListElement.findSnippets('${0:hello{\\}}')['0']).toEqual('start')
      expect(suggestionListElement.findSnippets('${0:hello{\\}}')['12']).toEqual('end')
      expect(suggestionListElement.findSnippets('${0:hello{\\}}')['4']).toEqual('bodystart')
      expect(suggestionListElement.findSnippets('${0:hello{\\}}')['11']).toEqual('bodyend')
      expect(suggestionListElement.findSnippets('${0:hello{\\}}')['10']).toEqual('skip')

    it 'identifies a snippet surrounded by text', ->
      # Without escaped right brace
      expect(suggestionListElement.findSnippets('hello${0:hello}')).toBeDefined()
      expect(suggestionListElement.findSnippets('hello${0:hello}')['5']).toEqual('start')
      expect(suggestionListElement.findSnippets('hello${0:hello}')['14']).toEqual('end')
      expect(suggestionListElement.findSnippets('hello${0:hello}')['9']).toEqual('bodystart')
      expect(suggestionListElement.findSnippets('hello${0:hello}')['13']).toEqual('bodyend')
      expect(suggestionListElement.findSnippets('${0:hello}hello')).toBeDefined()
      expect(suggestionListElement.findSnippets('${0:hello}hello')['0']).toEqual('start')
      expect(suggestionListElement.findSnippets('${0:hello}hello')['9']).toEqual('end')
      expect(suggestionListElement.findSnippets('${0:hello}hello')['4']).toEqual('bodystart')
      expect(suggestionListElement.findSnippets('${0:hello}hello')['8']).toEqual('bodyend')
      expect(suggestionListElement.findSnippets('hello${0:hello}hello')).toBeDefined()
      expect(suggestionListElement.findSnippets('hello${0:hello}hello')['5']).toEqual('start')
      expect(suggestionListElement.findSnippets('hello${0:hello}hello')['14']).toEqual('end')
      expect(suggestionListElement.findSnippets('hello${0:hello}hello')['9']).toEqual('bodystart')
      expect(suggestionListElement.findSnippets('hello${0:hello}hello')['13']).toEqual('bodyend')

      # With escaped right brace
      # expect(suggestionListElement.findSnippets('hello${0:hello{\\}}')).toBeDefined()
      # expect(suggestionListElement.findSnippets('hello${0:hello{\\}}')['5']).toEqual('start')
      # expect(suggestionListElement.findSnippets('hello${0:hello{\\}}')['18']).toEqual('end')
      # expect(suggestionListElement.findSnippets('hello${0:hello{\\}}')['9']).toEqual('bodystart')
      # expect(suggestionListElement.findSnippets('hello${0:hello{\\}}')['17']).toEqual('bodyend')
      # expect(suggestionListElement.findSnippets('hello${0:hello{\\}}')['15']).toEqual('skip')
      # expect(suggestionListElement.findSnippets('hello${0:hello{\\}}')['16']).toEqual('skip')
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}hello')).toBeDefined()
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}hello')['0']).toEqual('start')
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}hello')['13']).toEqual('end')
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}hello')['4']).toEqual('bodystart')
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}hello')['12']).toEqual('bodyend')
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}hello')['10']).toEqual('skip')
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}hello')['11']).toEqual('skip')
      # expect(suggestionListElement.findSnippets('hello${0:hello{\\}}hello')).toBeDefined()
      # expect(suggestionListElement.findSnippets('hello${0:hello{\\}}hello')['5']).toEqual('start')
      # expect(suggestionListElement.findSnippets('hello${0:hello{\\}}hello')['18']).toEqual('end')
      # expect(suggestionListElement.findSnippets('hello${0:hello{\\}}hello')['9']).toEqual('bodystart')
      # expect(suggestionListElement.findSnippets('hello${0:hello{\\}}hello')['17']).toEqual('bodyend')
      # expect(suggestionListElement.findSnippets('hello${0:hello{\\}}hello')['15']).toEqual('skip')
      # expect(suggestionListElement.findSnippets('hello${0:hello{\\}}hello')['16']).toEqual('skip')

    it 'identifies multiple snippets', ->
      # Without escaped right brace
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')).toBeDefined()
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')['0']).toEqual('start')
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')['9']).toEqual('end')
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')['4']).toEqual('bodystart')
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')['8']).toEqual('bodyend')
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')['10']).toEqual('start')
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')['19']).toEqual('end')
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')['14']).toEqual('bodystart')
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}')['18']).toEqual('bodyend')

      # With escaped right brace
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}${1:world}')).toBeDefined()
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}${1:world}')['0']).toEqual('start')
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}${1:world}')['13']).toEqual('end')
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}${1:world}')['4']).toEqual('bodystart')
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}${1:world}')['12']).toEqual('bodyend')
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}${1:world}')['10']).toEqual('skip')
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}${1:world}')['11']).toEqual('skip')
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}${1:world}')['14']).toEqual('start')
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}${1:world}')['23']).toEqual('end')
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}${1:world}')['18']).toEqual('bodystart')
      # expect(suggestionListElement.findSnippets('${0:hello{\\}}${1:world}')['22']).toEqual('bodyend')

    it 'identifies multiple snippets surrounded by text', ->
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')).toBeDefined()
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')['5']).toEqual('start')
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')['14']).toEqual('end')
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')['9']).toEqual('bodystart')
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')['13']).toEqual('bodyend')
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')['15']).toEqual('start')
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')['24']).toEqual('end')
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')['19']).toEqual('bodystart')
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}')['23']).toEqual('bodyend')
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')).toBeDefined()
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')['0']).toEqual('start')
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')['9']).toEqual('end')
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')['4']).toEqual('bodystart')
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')['8']).toEqual('bodyend')
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')['10']).toEqual('start')
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')['19']).toEqual('end')
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')['14']).toEqual('bodystart')
      expect(suggestionListElement.findSnippets('${0:hello}${1:world}hello')['18']).toEqual('bodyend')
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')).toBeDefined()
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')['5']).toEqual('start')
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')['14']).toEqual('end')
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')['9']).toEqual('bodystart')
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')['13']).toEqual('bodyend')
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')['15']).toEqual('start')
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')['24']).toEqual('end')
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')['19']).toEqual('bodystart')
      expect(suggestionListElement.findSnippets('hello${0:hello}${1:world}hello')['23']).toEqual('bodyend')

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
