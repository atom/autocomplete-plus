{Provider, Suggestion} = require "../../lib/autocomplete"

module.exports =
class TestProvider extends Provider
  buildSuggestions: ->
    [new Suggestion(this,
      word: "ohai",
      prefix: "ohai",
      label: "<span style=\"color: red\">ohai</span>",
      renderLabelAsHtml: true,
      className: 'ohai'
    )]
