const {CompositeDisposable} = require('atom')
const AutocompleteManager = require('./autocomplete-manager')

module.exports = {
  autocompleteManager: null,
  subscriptions: null,

  // Public: Creates AutocompleteManager instances for all active and future editors (soon, just a single AutocompleteManager)
  activate () {
    this.subscriptions = new CompositeDisposable()
    return this.requireAutocompleteManagerAsync()
  },

  // Public: Cleans everything up, removes all AutocompleteManager instances
  deactivate () {
    if (this.subscriptions) {
      this.subscriptions.dispose()
    }
    this.subscriptions = null
    this.autocompleteManager = null
  },

  requireAutocompleteManagerAsync (callback) {
    if (this.autocompleteManager) {
      if (callback) {
        callback(this.autocompleteManager)
      }
    } else {
      setImmediate(() => {
        const a = this.getAutocompleteManager()
        if (a && callback) {
          callback(a)
        }
      })
    }
  },

  getAutocompleteManager () {
    if (!this.autocompleteManager) {
      this.autocompleteManager = new AutocompleteManager()
      this.subscriptions.add(this.autocompleteManager)
    }

    return this.autocompleteManager
  },

  consumeSnippets (snippetsManager) {
    return this.requireAutocompleteManagerAsync((autocompleteManager) => {
      autocompleteManager.setSnippetsManager(snippetsManager)
    })
  },

  /*
  Section: Provider API
  */

  // 1.0.0 API
  // service - {provider: provider1}
  consumeProvider_1_0 (service) {
    if (!service || !service.provider) {
      return
    }
    // TODO API: Deprecate, tell them to upgrade to 3.0
    return this.consumeProvider([service.provider], '1.0.0')
  },

  // 1.1.0 API
  // service - {providers: [provider1, provider2, ...]}
  consumeProvider_1_1 (service) {
    if (!service || !service.providers) {
      return
    }
    // TODO API: Deprecate, tell them to upgrade to 3.0
    return this.consumeProvider(service.providers, '1.1.0')
  },

  // 2.0.0 API
  // providers - either a provider or a list of providers
  consumeProvider_2_0 (providers) {
    // TODO API: Deprecate, tell them to upgrade to 3.0
    return this.consumeProvider(providers, '2.0.0')
  },

  // 3.0.0 API
  // providers - either a provider or a list of providers
  consumeProvider_3_0 (providers) {
    return this.consumeProvider(providers, '3.0.0')
  },

  consumeProvider (providers, apiVersion = '3.0.0') {
    if (!providers) {
      return
    }
    if (providers && !Array.isArray(providers)) {
      providers = [providers]
    }
    if (!providers.length > 0) {
      return
    }

    const registrations = new CompositeDisposable()
    this.requireAutocompleteManagerAsync((autocompleteManager) => {
      for (let i = 0; i < providers.length; i++) {
        const provider = providers[i]
        registrations.add(autocompleteManager.providerManager.registerProvider(provider, apiVersion))
      }
    })
    return registrations
  }
}
