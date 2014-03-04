class Perf
  constructor: (@name, @options={}) ->
    @options.good  ?= 100
    @options.bad   ?= 500
    @options.debug ?= true

    @started = false

  start: ->
    return if @started or !@options.debug
    @start = +new Date()
    @started = true

  stop: (printLine) ->
    return if !@started or !@options.debug
    end = +new Date()
    duration = end - @start

    if @name?
      message = @name + ' took'
    else
      message = 'Code execution time:'

    if window?
      if duration < @options.good
        background = 'darkgreen'
        color = 'white'
      else if duration > @options.good and duration < @options.bad
        background = 'orange'
        color = 'black'
      else
        background = 'darkred'
        color = 'white'

      console.log '%c perf %c ' + message + ' %c ' + duration.toFixed(2) + 'ms ', 'background: #222; color: #bada55', '', 'background: ' + background + '; color: ' + color
    else
      console.log '[perf] ' + message + ' ' + duration.toFixed(2) + 'ms'

    @started = false

    if printLine and window?
      console.log '%c perf %c -- END --                                                                          ', 'background: #222; color: #bada55', 'background: #222; color: #ffffff'

module.exports = Perf
