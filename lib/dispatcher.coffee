async = require 'async'
{Subscriber, Emitter} = require 'emissary'

module.exports =
class Dispatcher
  Subscriber.includeInto(this)
  Emitter.includeInto(this)

  constructor: (@buffer) ->
    @providers = []

  registerProvider: (provider) ->

  run: ->
    return @complete(null) unless providers? and _.size(@providers) > 0
    async.map providers, (provider, callback) ->
      callback('Invalid provider') unless provider?
      provider.buildSuggestions(callback, position)
    , (err, suggestions) ->
      // TODO: Ensure Arrays Are Concatenated
      // Do something with the suggestions
      @complete(suggestions)

  complete: (suggestions) ->
    @emit 'dispatch-complete', suggestions
    return
