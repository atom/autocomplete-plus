'use babel'
/* eslint-env jasmine */

let temp = require('temp').track()
import path from 'path'
import fs from 'fs-plus'

describe('Autocomplete Manager', () => {
  let [directory, filePath, completionDelay, editorView, editor, mainModule, autocompleteManager, didAutocomplete] = []

  beforeEach(() => {
    runs(() => {
      directory = temp.mkdirSync()
      let sample = `var quicksort = function () {
  var sort = function(items) {
    if (items.length <= 1) return items;
    var pivot = items.shift(), current, left = [], right = [];
    while(items.length > 0) {
      current = items.shift();
      current < pivot ? left.push(current) : right.push(current);
    }
    return sort(left).concat(pivot).concat(sort(right));
  };

  return sort(Array.apply(this, arguments));
};
`
      filePath = path.join(directory, 'sample.js')
      fs.writeFileSync(filePath, sample)

      // Enable autosave
      atom.config.set('autosave.enabled', true)

      // Set to live completion
      atom.config.set('autocomplete-plus.enableAutoActivation', true)
      atom.config.set('editor.fontSize', '16')

      // Set the completion delay
      completionDelay = 100
      atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
      completionDelay += 100 // Rendering

      let workspaceElement = atom.views.getView(atom.workspace)
      jasmine.attachToDOM(workspaceElement)
    })

    waitsForPromise(() => atom.packages.activatePackage('autosave'))

    waitsForPromise(() => atom.workspace.open(filePath).then((e) => {
      editor = e
      editorView = atom.views.getView(editor)
    }))

    waitsForPromise(() => atom.packages.activatePackage('language-javascript'))

    // Activate the package
    waitsForPromise(() => atom.packages.activatePackage('autocomplete-plus').then((a) => {
      mainModule = a.mainModule
    }))

    waitsFor(() => {
      if (!mainModule || !mainModule.autocompleteManager) {
        return false
      }
      return mainModule.autocompleteManager.ready
    })

    runs(() => {
      advanceClock(mainModule.autocompleteManager.providerManager.defaultProvider.deferBuildWordListInterval)
      autocompleteManager = mainModule.autocompleteManager
      let { displaySuggestions } = autocompleteManager
      spyOn(autocompleteManager, 'displaySuggestions').andCallFake((suggestions, options) => {
        displaySuggestions(suggestions, options)
        didAutocomplete = true
      })
    })
  })

  afterEach(() => {
    didAutocomplete = false
  })

  describe('autosave compatibility', () =>
    it('keeps the suggestion list open while saving', () => {
      runs(() => {
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
        // Trigger an autocompletion
        editor.moveToBottom()
        editor.moveToBeginningOfLine()
        editor.insertText('f')
        advanceClock(completionDelay)
      })

      waitsFor(() => didAutocomplete === true)

      runs(() => {
        editor.save()
        didAutocomplete = false
        expect(editorView.querySelector('.autocomplete-plus')).toExist()
        editor.insertText('u')
        advanceClock(completionDelay)
      })

      waitsFor(() => didAutocomplete === true)

      runs(() => {
        editor.save()
        didAutocomplete = false
        expect(editorView.querySelector('.autocomplete-plus')).toExist()
        // Accept suggestion
        let suggestionListView = autocompleteManager.suggestionList.suggestionListElement
        atom.commands.dispatch(suggestionListView.element, 'autocomplete-plus:confirm')
        expect(editor.getBuffer().getLastLine()).toEqual('function')
      })
    })
  )
})
