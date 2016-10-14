'use babel'

import slick from 'atom-slick'

const EscapeCharacterRegex = /[-!"#$%&'*+,/:;=?@|^~()<>{}[\]]/g

const cachedMatchesBySelector = new WeakMap()

const getCachedMatch = (selector, scopeChain) => {
  let cachedMatchesByScopeChain
  cachedMatchesByScopeChain = cachedMatchesBySelector.get(selector)
  if (cachedMatchesByScopeChain) {
    return cachedMatchesByScopeChain[scopeChain]
  }
}

const setCachedMatch = (selector, scopeChain, match) => {
  let cachedMatchesByScopeChain = cachedMatchesBySelector.get(selector)
  if (!cachedMatchesByScopeChain) {
    cachedMatchesByScopeChain = {}
    cachedMatchesBySelector.set(selector, cachedMatchesByScopeChain)
  }
  cachedMatchesByScopeChain[scopeChain] = match
  cachedMatchesByScopeChain[scopeChain]
}

const parseScopeChain = (scopeChain) => {
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

const selectorForScopeChain = (selectors, scopeChain) => {
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

const selectorsMatchScopeChain = (selectors, scopeChain) => { return selectorForScopeChain(selectors, scopeChain) != null }

const buildScopeChainString = (scopes) => { return `.${scopes.join(' .')}` }

export { selectorsMatchScopeChain, selectorForScopeChain, buildScopeChainString }
