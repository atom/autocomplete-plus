{Selector} = require 'selector-kit'
semver = require 'semver'
{selectorForScopeChain, selectorsMatchScopeChain} = require './scope-helpers'

{API_VERSION} = require './private-symbols'

# Deferred requires
grim = null

module.exports =
class ProviderMetadata
  constructor: (@provider, @apiVersion) ->
    # TODO API: remove this when 2.0 support is removed
    if @provider.selector?
      @scopeSelectors = Selector.create(@provider.selector)
    else
      @scopeSelectors = Selector.create(@provider.scopeSelector)

    # TODO API: remove this when 2.0 support is removed
    if @provider.disableForSelector?
      @disableForScopeSelectors = Selector.create(@provider.disableForSelector)
    else if @provider.disableForScopeSelector?
      @disableForScopeSelectors = Selector.create(@provider.disableForScopeSelector)

    # TODO API: remove this when 1.0 support is removed
    if providerBlacklist = @provider.providerblacklist?['autocomplete-plus-fuzzyprovider']
      @disableDefaultProviderSelectors = Selector.create(providerBlacklist)

    @enableCustomTextEditorSelector = semver.satisfies(@provider[API_VERSION], '>=2.1.0')

  matchesEditor: (editor) ->
    if @enableCustomTextEditorSelector and @provider.getTextEditorSelector?
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
