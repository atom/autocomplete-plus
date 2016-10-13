'use babel'

const isFunction = value => isType(value, 'function')

const isString = value => isType(value, 'string')

const isType = function (value, typeName) {
  let t = typeof value
  if (t == null) { return false }
  return t === typeName
}

export { isFunction, isString }
