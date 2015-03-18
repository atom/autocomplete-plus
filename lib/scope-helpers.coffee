slick = require 'atom-slick'

EscapeCharacterRegex = /[-!"#$%&'*+,/:;=?@|^~()<>{}[\]]/g

parseScopeChain = (scopeChain) ->
  return [] unless scopeChain?
  scopeChain = scopeChain.replace EscapeCharacterRegex, (match) -> "\\#{match[0]}"
  scope for scope in slick.parse(scopeChain)[0] ? []

selectorForScopeChain = (selectors, scopeChain) ->
  for selector in selectors
    scopes = parseScopeChain(scopeChain)
    while scopes.length > 0
      return selector if selector.matches(scopes)
      scopes.pop()
  null

selectorsMatchScopeChain = (selectors, scopeChain) ->
  selectorForScopeChain(selectors, scopeChain)?

module.exports = {parseScopeChain, selectorsMatchScopeChain, selectorForScopeChain}
