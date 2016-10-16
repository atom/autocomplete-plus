'use babel'

import { Selector } from 'selector-kit'
import semver from 'semver'
import { selectorForScopeChain, selectorsMatchScopeChain } from './scope-helpers'

import { API_VERSION } from './private-symbols'

export default class ProviderMetadata {
  constructor (provider, apiVersion) {
    // TODO API: remove this when 2.0 support is removed

    this.provider = provider
    this.apiVersion = apiVersion
    if (this.provider.selector != null) {
      this.scopeSelectors = Selector.create(this.provider.selector)
    } else {
      this.scopeSelectors = Selector.create(this.provider.scopeSelector)
    }

    // TODO API: remove this when 2.0 support is removed
    if (this.provider.disableForSelector != null) {
      this.disableForScopeSelectors = Selector.create(this.provider.disableForSelector)
    } else if (this.provider.disableForScopeSelector != null) {
      this.disableForScopeSelectors = Selector.create(this.provider.disableForScopeSelector)
    }

    // TODO API: remove this when 1.0 support is removed
    let providerBlacklist
    if (this.provider.providerblacklist && this.provider.providerblacklist['autocomplete-plus-fuzzyprovider']) {
      providerBlacklist = this.provider.providerblacklist['autocomplete-plus-fuzzyprovider']
    }
    if (providerBlacklist) {
      this.disableDefaultProviderSelectors = Selector.create(providerBlacklist)
    }

    this.enableCustomTextEditorSelector = semver.satisfies(this.provider[API_VERSION], '>=3.0.0')
  }

  matchesEditor (editor) {
    if (this.enableCustomTextEditorSelector && (this.provider.getTextEditorSelector != null)) {
      return atom.views.getView(editor).matches(this.provider.getTextEditorSelector())
    } else {
      // Backwards compatibility.
      return atom.views.getView(editor).matches('atom-pane > .item-views > atom-text-editor')
    }
  }

  matchesScopeChain (scopeChain) {
    if (this.disableForScopeSelectors != null) {
      if (selectorsMatchScopeChain(this.disableForScopeSelectors, scopeChain)) { return false }
    }

    if (selectorsMatchScopeChain(this.scopeSelectors, scopeChain)) {
      return true
    } else {
      return false
    }
  }

  shouldDisableDefaultProvider (scopeChain) {
    if (this.disableDefaultProviderSelectors != null) {
      return selectorsMatchScopeChain(this.disableDefaultProviderSelectors, scopeChain)
    } else {
      return false
    }
  }

  getSpecificity (scopeChain) {
    const selector = selectorForScopeChain(this.scopeSelectors, scopeChain)
    if (selector) {
      return selector.getSpecificity()
    } else {
      return 0
    }
  }
}
