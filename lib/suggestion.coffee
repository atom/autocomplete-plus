module.exports =
class Suggestion
  constructor: (@provider, options) ->
    @word = options.word if options.word?
    @prefix = options.prefix if options.prefix?
    @label = options.label if options.label?
    @data = options.data if options.data?
