module.exports =
class Suggestion
  constructor: (options) ->
    @word = options.word if options.word?
    @prefix = options.prefix if options.prefix?
