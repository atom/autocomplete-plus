{deprecate} = require('grim')
module.exports =
class Suggestion
  constructor: (@provider, options) ->
    deprecate('`Suggestion` is no longer supported. Please switch to the new API: https://github.com/atom-community/autocomplete-plus/wiki/Provider-API')
    @word = options.word if options.word?
    @prefix = options.prefix if options.prefix?
    @label = options.label if options.label?
    @data = options.data if options.data?
    @renderLabelAsHtml = options.renderLabelAsHtml if options.renderLabelAsHtml?
    @className = options.className if options.className?
