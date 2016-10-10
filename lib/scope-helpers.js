'use babel'

import slick from 'atom-slick'

let EscapeCharacterRegex = /[-!"#$%&'*+,/:;=?@|^~()<>{}[\]]/g

let cachedMatchesBySelector = new WeakMap()

let getCachedMatch = function (selector, scopeChain) {
  let cachedMatchesByScopeChain
  cachedMatchesByScopeChain = cachedMatchesBySelector.get(selector)
  if (cachedMatchesByScopeChain) {
    return cachedMatchesByScopeChain[scopeChain]
  }
}

let setCachedMatch = (selector, scopeChain, match) => {
  let cachedMatchesByScopeChain = cachedMatchesBySelector.get(selector)
  if (!cachedMatchesByScopeChain) {
    cachedMatchesByScopeChain = {}
    cachedMatchesBySelector.set(selector, cachedMatchesByScopeChain)
  }
  cachedMatchesByScopeChain[scopeChain] = match
  return cachedMatchesByScopeChain[scopeChain]
}

let parseScopeChain = (scopeChain) => {
  scopeChain = scopeChain.replace(EscapeCharacterRegex, (match) => {
    return '\\' + match[0]
  })

  let parsed = slick.parse(scopeChain)[0]
  if (!parsed || parsed.length === 0) {
    return []
  }

  let result = []
  for (let i = 0; i < parsed.length; i++) {
    result.push(parsed[i])
  }

  return result
}

let selectorForScopeChain = (selectors, scopeChain) => {
  for (let i = 0; i < selectors.length; i++) {
    let selector = selectors[i]
    let cachedMatch = getCachedMatch(selector, scopeChain)
    if (cachedMatch != null) {
      if (cachedMatch) {
        return selector
      } else {
        continue
      }
    } else {
      let scopes = parseScopeChain(scopeChain)
      while (scopes.length > 0) {
        if (selector.matches(scopes)) {
          setCachedMatch(selector, scopeChain, true)
          return selector
        }
        scopes.pop()
      }
      setCachedMatch(selector, scopeChain, false)
    }
  }

  return null
}

let selectorsMatchScopeChain = (selectors, scopeChain) => selectorForScopeChain(selectors, scopeChain) != null

let buildScopeChainString = scopes => `.${scopes.join(' .')}`

export { selectorsMatchScopeChain, selectorForScopeChain, buildScopeChainString }
