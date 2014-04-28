module.exports =

  # Internal: De-duplicate an array
  #
  # arr - The {Array} to de-depulicate
  #
  # Returns {Array} that has no duplicate elements
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
