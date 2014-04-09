module.exports =

  ###
   * Returns a unique version of the array using ES6's Set
   * implementation
   *
   * Damn, that shit is _fast_:
   * http://jsperf.com/array-unique2/15
   *
   * @param  {Array} arr
   * @return {Array}
  ###
  unique: (arr) ->
    out = []
    seen = new Set

    i = arr.length
    while i--
      item = arr[i]
      unless seen.has item
        out.push item
        seen.add item

    return out
