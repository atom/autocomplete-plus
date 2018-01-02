const POSSIBLE_WORD_CHARACTERS = '/\\()"\':,.;<>~!@#$%^&*|+=[]{}`?_-…'.split('')

module.exports =
function getAdditionalWordCharacters (scopeDescriptor) {
  const nonWordCharacters = atom.config.get('editor.nonWordCharacters', {scope: scopeDescriptor})
  let additionalWordCharacters = ''
  POSSIBLE_WORD_CHARACTERS.forEach(character => {
    if (!nonWordCharacters.includes(character)) {
      additionalWordCharacters += character
    }
  })

  return additionalWordCharacters
}
