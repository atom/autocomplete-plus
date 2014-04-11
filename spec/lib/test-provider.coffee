{Provider, Suggestion} = require "../../lib/autocomplete"

module.exports =
class TestProvider extends Provider
  buildSuggestions: ->
    [new Suggestion(this, word: "ohai", prefix: "")]
