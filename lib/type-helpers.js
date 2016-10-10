'use babel'

let isFunction = value => isType(value, 'function')

let isString = value => isType(value, 'string')

var isType = function (value, typeName) {
  let t = typeof value
  if (t == null) { return false }
  return t === typeName
}

export { isFunction, isString }
