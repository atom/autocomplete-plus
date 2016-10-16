'use babel'

export default class RefCountedTokenList {
  constructor () {
    this.clear()
  }

  clear () {
    this.references = {}
    this.tokens = []
  }

  getLength () { return this.tokens.length }

  getTokens () { return this.tokens }

  getTokenWrappers () {
    return ((() => {
      const result = []
      for (const key in this.references) {
        const tokenWrapper = this.references[key]
        result.push(tokenWrapper)
      }
      return result
    })())
  }

  getToken (tokenKey) {
    const wrapper = this.getTokenWrapper(tokenKey)
    if (wrapper) {
      return wrapper.token
    }
  }

  getTokenWrapper (tokenKey) {
    tokenKey = this.getTokenKey(tokenKey)
    return this.references[tokenKey]
  }

  refCountForToken (tokenKey) {
    tokenKey = this.getTokenKey(tokenKey)
    if (this.references[tokenKey] && this.references[tokenKey].count) {
      return this.references[tokenKey].count
    }
    return 0
  }

  addToken (token, tokenKey) {
    tokenKey = this.getTokenKey(token, tokenKey)
    return this.updateRefCount(tokenKey, token, 1)
  }

  // Returns true when the token was removed
  // Returns false when the token was not present and thus not removed
  removeToken (token, tokenKey) {
    tokenKey = this.getTokenKey(token, tokenKey)
    if (this.references[tokenKey] != null) {
      ({ token } = this.references[tokenKey])
      this.updateRefCount(tokenKey, token, -1)
      return true
    } else {
      return false
    }
  }

  /*
  Private Methods
  */

  updateRefCount (tokenKey, token, increment) {
    if (increment > 0 && (this.references[tokenKey] == null)) {
      if (this.references[tokenKey] == null) { this.references[tokenKey] = {tokenKey, token, count: 0} }
      this.addTokenToList(token)
    }

    if (this.references[tokenKey] != null) { this.references[tokenKey].count += increment }

    if (this.references[tokenKey] && this.references[tokenKey].count <= 0) {
      delete this.references[tokenKey]
      return this.removeTokenFromList(token)
    }
  }

  addTokenToList (token) {
    return this.tokens.push(token)
  }

  removeTokenFromList (token) {
    const index = this.tokens.indexOf(token)
    if (index > -1) { return this.tokens.splice(index, 1) }
  }

  getTokenKey (token, tokenKey) {
    // some words are reserved, like 'constructor' :/
    if (tokenKey) {
      return tokenKey + '$$'
    }

    return token + '$$'
  }
}
