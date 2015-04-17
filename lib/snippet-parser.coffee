module.exports =
class SnippetParser
  reset: ->
    @inSnippet = false
    @inSnippetBody = false
    @snippetStart = -1
    @snippetEnd = -1
    @bodyStart = -1
    @bodyEnd = -1
    @escapedBraceIndices = null

  findSnippets: (text) ->
    return unless text.length > 0 and text.indexOf('$') isnt -1 # No snippets
    @reset()
    snippets = []

    # We're not using a regex because escaped right braces cannot be tracked without lookbehind,
    # which doesn't exist yet for javascript; consequently we need to iterate through each character.
    # This might feel ugly, but it's necessary.
    for char, index in text
      if @inSnippet and @snippetEnd is index
        body = text.slice(@bodyStart, @bodyEnd + 1)
        body = @removeBraceEscaping(body, @bodyStart, @escapedBraceIndices)
        snippets.push({@snippetStart, @snippetEnd, @bodyStart, @bodyEnd, body})
        @reset()
        continue

      @inBody = true if @inSnippet and index >= @bodyStart and index <= @bodyEnd
      @inBody = false if @inSnippet and (index > @bodyEnd or index < @bodyStart)
      @inBody = false if @bodyStart is -1 or @bodyEnd is -1
      continue if @inSnippet and not @inBody
      continue if @inSnippet and @inBody

      # Determine if we've found a new snippet
      if not @inSnippet and text.indexOf('${', index) is index
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
            if text.charAt(rightBraceIndex - 1) is '\\'
              @escapedBraceIndices ?= []
              @escapedBraceIndices.push(rightBraceIndex - 1)
            else
              break
            i = rightBraceIndex + 1

        if colonIndex isnt -1 and rightBraceIndex isnt -1 and colonIndex < rightBraceIndex
          @inSnippet = true
          @inBody = false
          @snippetStart = index
          @snippetEnd = rightBraceIndex
          @bodyStart = colonIndex + 1
          @bodyEnd = rightBraceIndex - 1
          continue
        else
          @reset()

    snippets

  removeBraceEscaping: (body, bodyStart, escapedBraceIndices) ->
    if escapedBraceIndices?
      for bodyIndex, i in escapedBraceIndices
        body = removeCharFromString(body, bodyIndex - bodyStart - i)
    body

removeCharFromString = (str, index) -> str.slice(0, index) + str.slice(index + 1)
