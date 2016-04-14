{Selector} = require 'selector-kit'
{selectorForScopeChain, selectorsMatchScopeChain} = require './scope-helpers'

# Deferred requires
grim = null

module.exports =
class ProviderMetadata
  constructor: (@provider, @apiVersion) ->
    if @provider.selector?
      grim ?= require 'grim'
      grim.deprecate """
        Autocomplete provider '#{@provider.constructor.name}(#{@provider.id})'
        specifies `selector` instead of the `scopeSelector` attribute.
        See https://github.com/atom/autocomplete-plus/wiki/Provider-API.
      """
      @scopeSelectors = Selector.create(@provider.selector)
    else
      @scopeSelectors = Selector.create(@provider.scopeSelector)

    if @provider.disableForSelector?
      grim ?= require 'grim'
      grim.deprecate """
        Autocomplete provider '#{@provider.constructor.name}(#{@provider.id})'
        specifies `disableForSelector` instead of the `disableForScopeSelector`
        attribute.
        See https://github.com/atom/autocomplete-plus/wiki/Provider-API.
      """
      @disableForScopeSelectors = Selector.create(@provider.disableForSelector)
    else if @provider.disableForScopeSelector?
      @disableForScopeSelectors = Selector.create(@provider.disableForScopeSelector)

    # TODO API: remove this when 1.0 is pulled out
    if providerBlacklist = @provider.providerblacklist?['autocomplete-plus-fuzzyprovider']
      @disableDefaultProviderSelectors = Selector.create(providerBlacklist)

  matchesEditor: (editor) ->
    if @provider.getTextEditorSelector?
      atom.views.getView(editor).matches(@provider.getTextEditorSelector())
    else
      # Backwards compatibility.
      atom.views.getView(editor).matches('atom-pane > .item-views > atom-text-editor')

  matchesScopeChain: (scopeChain) ->
    if @disableForScopeSelectors?
      return false if selectorsMatchScopeChain(@disableForScopeSelectors, scopeChain)

    if selectorsMatchScopeChain(@scopeSelectors, scopeChain)
      true
    else
      false

  shouldDisableDefaultProvider: (scopeChain) ->
    if @disableDefaultProviderSelectors?
      selectorsMatchScopeChain(@disableDefaultProviderSelectors, scopeChain)
    else
      false

  getSpecificity: (scopeChain) ->
    if selector = selectorForScopeChain(@scopeSelectors, scopeChain)
      selector.getSpecificity()
    else
      0
