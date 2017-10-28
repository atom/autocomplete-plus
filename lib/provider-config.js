const _ = require('underscore-plus')
const { Selector } = require('selector-kit')
const {selectorsMatchScopeChain, buildScopeChainString} = require('./scope-helpers')

class ProviderConfig {
  constructor (options = {}) {
    this.atomConfig = options.atomConfig || atom.config

    this.config = {}

    this.scopesToTypeMap = {}

    this.cachedConfigs = {}

    this.defaultConfig = {
      class: {
        selector: '.class.name, .inherited-class, .instance.type',
        typePriority: 4
      },
      function: {
        selector: '.function.name',
        typePriority: 3
      },
      variable: {
        selector: '.variable',
        typePriority: 2
      },
      '': {
        selector: '.source',
        typePriority: 1
      }
    }

    this.currentScopeDescriptor = null
  }

  getSuggestionsForScopeDescriptor (scopeDescriptor) {
    this.buildConfigIfScopeChanged(scopeDescriptor)

    return Object.values(this.config)
      .map(x => x.suggestions)
      .reduce((flat, suggestions) => suggestions ? flat.concat(suggestions) : flat, [])
  }

  scopeDescriptorToType (scopeDescriptor) {
    const scopeChain = '.' + scopeDescriptor.scopes.join(' .')

    if (this.scopesToTypeMap[scopeChain]) {
      return this.scopesToTypeMap[scopeChain]
    }

    this.buildConfigIfScopeChanged(scopeDescriptor)

    let matchingType = null
    let highestTypePriority = -1

    const config = this.config

    for (const type of Object.keys(config)) {
      let {selectors, typePriority} = config[type]
      if (selectors == null) continue
      if (typePriority == null) typePriority = 0
      if (typePriority > highestTypePriority &&
          selectorsMatchScopeChain(selectors, scopeChain)) {
        matchingType = type
        highestTypePriority = typePriority
      }
    }

    this.scopesToTypeMap[scopeChain] = matchingType

    return matchingType
  }

  buildConfigIfScopeChanged (scopeDescriptor) {
    if (!this.safeScopeDescriptorsEqual(this.currentScopeDescriptor, scopeDescriptor)) {
      this.buildConfig(scopeDescriptor)
      this.currentScopeDescriptor = scopeDescriptor
      return this.currentScopeDescriptor
    }
  }

  buildConfig (scopeDescriptor) {
    this.config = {}
    const legacyCompletions = this.settingsForScopeDescriptor(scopeDescriptor, 'editor.completions')
    const allConfigEntries = this.settingsForScopeDescriptor(scopeDescriptor, 'autocomplete.symbols')

    // TODO: ported from symbol provider - not sure about this
    // Config entries are reverse sorted in order of specificity. We want most
    // specific to win; this simplifies the loop.
    allConfigEntries.reverse()

    for (let i = 0; i < legacyCompletions.length; i++) {
      const { value } = legacyCompletions[i]
      if (Array.isArray(value) && value.length) {
        this.addLegacyConfigEntry(value)
      }
    }

    let addedConfigEntry = false
    for (let j = 0; j < allConfigEntries.length; j++) {
      const { value } = allConfigEntries[j]
      if (!Array.isArray(value) && typeof value === 'object') {
        this.addConfigEntry(value)
        addedConfigEntry = true
      }
    }

    if (!addedConfigEntry) { return this.addConfigEntry(this.defaultConfig) }
  }

  addLegacyConfigEntry (suggestions) {
    suggestions = (suggestions.map((suggestion) => ({text: suggestion, type: 'builtin'})))
    if (this.config.builtin == null) {
      this.config.builtin = {suggestions: []}
    }
    this.config.builtin.suggestions = this.config.builtin.suggestions.concat(suggestions)
    return this.config.builtin.suggestions
  }

  addConfigEntry (config) {
    for (const type in config) {
      const options = config[type]
      if (this.config[type] == null) { this.config[type] = {} }
      if (options.selector != null) { this.config[type].selectors = Selector.create(options.selector) }
      this.config[type].typePriority = options.typePriority != null ? options.typePriority : 1

      const suggestions = this.sanitizeSuggestionsFromConfig(options.suggestions, type)
      if ((suggestions != null) && suggestions.length) { this.config[type].suggestions = suggestions }
    }
  }

  sanitizeSuggestionsFromConfig (suggestions, type) {
    if ((suggestions != null) && Array.isArray(suggestions)) {
      const sanitizedSuggestions = []
      for (let i = 0; i < suggestions.length; i++) {
        let suggestion = suggestions[i]
        if (typeof suggestion === 'string') {
          sanitizedSuggestions.push({text: suggestion, type})
        } else if (typeof suggestions[0] === 'object' && ((suggestion.text != null) || (suggestion.snippet != null))) {
          suggestion = _.clone(suggestion)
          if (suggestion.type == null) { suggestion.type = type }
          sanitizedSuggestions.push(suggestion)
        }
      }
      return sanitizedSuggestions
    } else {
      return null
    }
  }

  settingsForScopeDescriptor (scopeDescriptor, keyPath) {
    const cacheKey = scopeDescriptor.scopes.join(' ') + ' ' + keyPath
    if (this.cachedConfigs[cacheKey]) {
      return this.cachedConfigs[cacheKey]
    }

    const config = this.atomConfig.getAll(keyPath, {scope: scopeDescriptor})

    this.cachedConfigs[cacheKey] = config

    return config
  }

  safeScopeDescriptorsEqual (a, b) {
    if ((a == null) || (b == null)) { return false }

    return a.isEqual(b)
  }
}

module.exports = ProviderConfig
