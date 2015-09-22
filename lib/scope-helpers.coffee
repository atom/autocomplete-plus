slick = require 'atom-slick'

EscapeCharacterRegex = /[-!"#$%&'*+,/:;=?@|^~()<>{}[\]]/g

cachedMatchesBySelector = new WeakMap

getCachedMatch = (selector, scopeChain) ->
  if cachedMatchesByScopeChain = cachedMatchesBySelector.get(selector)
    return cachedMatchesByScopeChain[scopeChain]

setCachedMatch = (selector, scopeChain, match) ->
  unless cachedMatchesByScopeChain = cachedMatchesBySelector.get(selector)
    cachedMatchesByScopeChain = {}
    cachedMatchesBySelector.set(selector, cachedMatchesByScopeChain)
  cachedMatchesByScopeChain[scopeChain] = match

parseScopeChain = (scopeChain) ->
  scopeChain = scopeChain.replace EscapeCharacterRegex, (match) -> "\\#{match[0]}"
  scope for scope in slick.parse(scopeChain)[0] ? []

selectorForScopeChain = (selectors, scopeChain) ->
  for selector in selectors
    cachedMatch = getCachedMatch(selector, scopeChain)
    if cachedMatch?
      if cachedMatch
        return selector
      else
        continue
    else
      scopes = parseScopeChain(scopeChain)
      while scopes.length > 0
        if selector.matches(scopes)
          setCachedMatch(selector, scopeChain, true)
          return selector
        scopes.pop()
      setCachedMatch(selector, scopeChain, false)

  null

selectorsMatchScopeChain = (selectors, scopeChain) ->
  selectorForScopeChain(selectors, scopeChain)?

module.exports = {parseScopeChain, selectorsMatchScopeChain, selectorForScopeChain}
