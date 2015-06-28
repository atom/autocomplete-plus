isFunction = (value) ->
  isType(value, 'function')

isString = (value) ->
  isType(value, 'string')

isType = (value, typeName) ->
  t = typeof value
  return false unless t?
  t is typeName

module.exports = {isFunction, isString}
