{deprecate} = require 'grim'
module.exports =
class Suggestion
  constructor: (@provider, options) ->
    deprecate """
      `Suggestion` is no longer supported. Please define your own object (a class or anonymous object)
      instead of instantiating `Suggestion`. Example
        ```
        # Example:
        testProvider =
          requestHandler: (options) =>
            # Build your suggestions here...

            # Return your suggestions as an array of anonymous objects
            [{
              provider: this,
              word: 'ohai',
              prefix: 'ohai',
              label: '<span style="color: red">ohai</span>',
              renderLabelAsHtml: true,
              className: 'ohai'
            }]
          selector: '.source.js,.source.coffee' # This provider will be run on JavaScript and Coffee files
          dispose: ->
            # Your dispose logic here
        ```
    """
    @word = options.word if options.word?
    @prefix = options.prefix if options.prefix?
    @label = options.label if options.label?
    @data = options.data if options.data?
    @renderLabelAsHtml = options.renderLabelAsHtml if options.renderLabelAsHtml?
    @className = options.className if options.className?
