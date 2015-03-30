{triggerAutocompletion, waitForAutocomplete, buildIMECompositionEvent, buildTextInputEvent} = require './spec-helper'
_ = require 'underscore-plus'
{KeymapManager} = require 'atom'

NodeTypeText = 3

describe 'Autocomplete Manager', ->
  [workspaceElement, completionDelay, editorView, editor, mainModule, autocompleteManager, mainModule] = []

  beforeEach ->
    runs ->
      # Set to live completion
      atom.config.set('autocomplete-plus.enableAutoActivation', true)
      atom.config.set('editor.fontSize', '16')

      # Set the completion delay
      completionDelay = 100
      atom.config.set('autocomplete-plus.autoActivationDelay', completionDelay)
      completionDelay += 100 # Rendering

      workspaceElement = atom.views.getView(atom.workspace)
      jasmine.attachToDOM(workspaceElement)

      atom.config.set('autocomplete-plus.maxVisibleSuggestions', 10)

  describe "when an external provider is registered", ->
    [provider] = []

    beforeEach ->
      waitsForPromise ->
        Promise.all [
          atom.workspace.open('').then (e) ->
            editor = e
            editorView = atom.views.getView(editor)
          atom.packages.activatePackage('autocomplete-plus').then (a) ->
            mainModule = a.mainModule
        ]

      runs ->
        provider =
          selector: '*'
          getSuggestions: ({prefix}) ->
            list = ['ab', 'abc', 'abcd', 'abcde']
            ({text, replacementPrefix: prefix} for text in list)
        mainModule.consumeProvider(provider)

    it "calls the provider's onDidInsertSuggestion method when it exists", ->
      provider.onDidInsertSuggestion = jasmine.createSpy()

      triggerAutocompletion(editor, true, 'a')

      runs ->
        suggestionListView = editorView.querySelector('.autocomplete-plus autocomplete-suggestion-list')
        atom.commands.dispatch(suggestionListView, 'autocomplete-plus:confirm')

        expect(provider.onDidInsertSuggestion).toHaveBeenCalled()

        {editor, triggerPosition, suggestion} = provider.onDidInsertSuggestion.mostRecentCall.args[0]
        expect(editor).toBe editor
        expect(triggerPosition).toEqual [0, 1]
        expect(suggestion.text).toBe 'ab'

    fdescribe "suppression for editorView classes", ->
      beforeEach ->
        atom.config.set('autocomplete-plus.suppressActivationForEditorClasses', ['vim-mode.command-mode', 'vim-mode . visual-mode', ' vim-mode.operator-pending-mode ', ' '])

      it 'should show the suggestion list when the suppression list does not match', ->
        runs ->
          editorView.classList.add('vim-mode')
          editorView.classList.add('insert-mode')

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          triggerAutocompletion(editor)

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

      it 'should not show the suggestion list when the suppression list does match', ->
        runs ->
          editorView.classList.add('vim-mode')
          editorView.classList.add('command-mode')

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          triggerAutocompletion(editor)

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

      it 'should not show the suggestion list when the suppression list does match', ->
        runs ->
          editorView.classList.add('vim-mode')
          editorView.classList.add('operator-pending-mode')

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          triggerAutocompletion(editor)

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

      it 'should not show the suggestion list when the suppression list does match', ->
        runs ->
          editorView.classList.add('vim-mode')
          editorView.classList.add('visual-mode')

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          triggerAutocompletion(editor)

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

      it 'should show the suggestion list when the suppression list does not match', ->
        runs ->
          editorView.classList.add('vim-mode')
          editorView.classList.add('some-unforeseen-mode')

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          triggerAutocompletion(editor)

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

      it 'should show the suggestion list when the suppression list does not match', ->
        runs ->
          editorView.classList.add('command-mode')

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          triggerAutocompletion(editor)

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

    describe "prefix passed to getSuggestions", ->
      prefix = null
      beforeEach ->
        editor.setText('var something = abc')
        editor.setCursorBufferPosition([0, 10000])
        spyOn(provider, 'getSuggestions').andCallFake (options) ->
          prefix = options.prefix
          []

      it "calls with word prefix", ->
        editor.insertText('d')
        waitForAutocomplete()
        runs ->
          expect(prefix).toBe 'abcd'

      it "calls with word prefix after punctuation", ->
        editor.insertText('d.okyea')
        editor.insertText('h')
        waitForAutocomplete()
        runs ->
          expect(prefix).toBe 'okyeah'

      it "calls with word prefix containing a dash", ->
        editor.insertText('-okyea')
        editor.insertText('h')
        waitForAutocomplete()
        runs ->
          expect(prefix).toBe 'abc-okyeah'

      it "calls with space character", ->
        editor.insertText(' ')
        waitForAutocomplete()
        runs ->
          expect(prefix).toBe ' '

      it "calls with non-word prefix", ->
        editor.insertText(':')
        editor.insertText(':')
        waitForAutocomplete()
        runs ->
          expect(prefix).toBe '::'

      it "calls with non-word bracket", ->
        editor.insertText('[')
        waitForAutocomplete()
        runs ->
          expect(prefix).toBe '['

      it "calls with dot prefix", ->
        editor.insertText('.')
        waitForAutocomplete()
        runs ->
          expect(prefix).toBe '.'

    describe "when number of suggestions > maxVisibleSuggestions", ->
      beforeEach ->
        atom.config.set('autocomplete-plus.maxVisibleSuggestions', 2)

      it "only shows the maxVisibleSuggestions in the suggestion popup", ->
        triggerAutocompletion(editor, true, 'a')

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()
          expect(editorView.querySelectorAll('.autocomplete-plus li')).toHaveLength 4
          expect(editorView.querySelector('.autocomplete-plus .list-group').style['max-height']).toBe("#{2 * 25}px")

    describe "when match.snippet is used", ->
      beforeEach ->
        spyOn(provider, 'getSuggestions').andCallFake ({prefix}) ->
          list = ['method(${1:something})', 'method2(${1:something})', 'method3(${1:something})']
          ({snippet, replacementPrefix: prefix} for snippet in list)

      describe "when the snippets package is enabled", ->
        beforeEach ->
          waitsForPromise ->
            atom.packages.activatePackage('snippets')

        it "displays the snippet without the `${1:}` in its own class", ->
          triggerAutocompletion(editor, true, 'm')

          runs ->
            wordElement = editorView.querySelector('.autocomplete-plus span.word')
            expect(wordElement.textContent).toBe 'method(something)'
            expect(wordElement.querySelector('.snippet-completion').textContent).toBe 'something'

            wordElements = editorView.querySelectorAll('.autocomplete-plus span.word')
            expect(wordElements).toHaveLength 3

        it "accepts the snippet when autocomplete-plus:confirm is triggered", ->
          triggerAutocompletion(editor, true, 'm')

          runs ->
            suggestionListView = editorView.querySelector('.autocomplete-plus autocomplete-suggestion-list')
            atom.commands.dispatch(suggestionListView, 'autocomplete-plus:confirm')
            expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
            expect(editor.getSelectedText()).toBe 'something'

    describe "when the matched prefix is highlighted", ->
      it 'highlights the prefix of the word in the suggestion list', ->
        spyOn(provider, 'getSuggestions').andCallFake ({prefix}) ->
          [{text: 'items', replacementPrefix: prefix}]

        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        editor.moveToBottom()
        editor.insertText('i')
        editor.insertText('e')
        editor.insertText('m')

        waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

          word = editorView.querySelector('.autocomplete-plus li span.word')
          expect(word.childNodes).toHaveLength 5
          expect(word.childNodes[0]).toHaveClass 'character-match'
          expect(word.childNodes[1].nodeType).toBe NodeTypeText
          expect(word.childNodes[2]).toHaveClass 'character-match'
          expect(word.childNodes[3]).toHaveClass 'character-match'
          expect(word.childNodes[4].nodeType).toBe NodeTypeText

      it 'highlights repeated characters in the prefix', ->
        spyOn(provider, 'getSuggestions').andCallFake ({prefix}) ->
          [{text: 'apply', replacementPrefix: prefix}]

        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        editor.moveToBottom()
        editor.insertText('a')
        editor.insertText('p')
        editor.insertText('p')

        waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

          word = editorView.querySelector('.autocomplete-plus li span.word')
          expect(word.childNodes).toHaveLength 4
          expect(word.childNodes[0]).toHaveClass 'character-match'
          expect(word.childNodes[1]).toHaveClass 'character-match'
          expect(word.childNodes[2]).toHaveClass 'character-match'
          expect(word.childNodes[3].nodeType).toBe 3 # text
          expect(word.childNodes[3].textContent).toBe 'ly'

      describe "when the prefix does not match the word", ->
        it "does not render any character-match spans", ->
          spyOn(provider, 'getSuggestions').andCallFake ({prefix}) ->
            [{text: 'omgnope', replacementPrefix: prefix}]

          editor.moveToBottom()
          editor.insertText('x')
          editor.insertText('y')
          editor.insertText('z')

          waitForAutocomplete()

          runs ->
            expect(editorView.querySelector('.autocomplete-plus')).toExist()

            characterMatches = editorView.querySelectorAll('.autocomplete-plus li span.word .character-match')
            text = editorView.querySelector('.autocomplete-plus li span.word').textContent
            console.log characterMatches
            expect(characterMatches).toHaveLength 0
            expect(text).toBe 'omgnope'

        describe "when the snippets package is enabled", ->
          beforeEach ->
            waitsForPromise -> atom.packages.activatePackage('snippets')

          it "does not highlight the snippet html; ref issue 301", ->
            spyOn(provider, 'getSuggestions').andCallFake ->
              [{snippet: 'ab(${1:c})c'}]

            editor.moveToBottom()
            editor.insertText('c')
            waitForAutocomplete()

            runs ->
              word = editorView.querySelector('.autocomplete-plus li span.word')
              charMatch = editorView.querySelector('.autocomplete-plus li span.word .character-match')
              expect(word.textContent).toBe 'ab(c)c'
              expect(charMatch.textContent).toBe 'c'
              expect(charMatch.parentNode).toHaveClass 'word'

          it "does not highlight the snippet html when highlight beginning of the word", ->
            spyOn(provider, 'getSuggestions').andCallFake ->
              [{snippet: 'abcde(${1:e}, ${1:f})f'}]

            editor.moveToBottom()
            editor.insertText('c')
            editor.insertText('e')
            editor.insertText('f')
            waitForAutocomplete()

            runs ->
              word = editorView.querySelector('.autocomplete-plus li span.word')
              expect(word.textContent).toBe 'abcde(e, f)f'

              charMatches = editorView.querySelectorAll('.autocomplete-plus li span.word .character-match')
              expect(charMatches[0].textContent).toBe 'c'
              expect(charMatches[0].parentNode).toHaveClass 'word'
              expect(charMatches[1].textContent).toBe 'e'
              expect(charMatches[1].parentNode).toHaveClass 'word'
              expect(charMatches[2].textContent).toBe 'f'
              expect(charMatches[2].parentNode).toHaveClass 'word'

    describe "when a replacementPrefix is not specified", ->
      beforeEach ->
        spyOn(provider, 'getSuggestions').andCallFake ->
          [text: 'something']

      it "replaces with the default input prefix", ->
        editor.insertText('abc')
        triggerAutocompletion(editor, false, 'm')

        expect(editor.getText()).toBe 'abcm'

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()
          suggestionListView = editorView.querySelector('.autocomplete-plus autocomplete-suggestion-list')
          atom.commands.dispatch(suggestionListView, 'autocomplete-plus:confirm')
          expect(editor.getText()).toBe 'something'

    describe "when autocomplete-plus.suggestionListFollows is 'Word'", ->
      beforeEach ->
        atom.config.set('autocomplete-plus.suggestionListFollows', 'Word')

      afterEach ->
        atom.config.set('autocomplete-plus.suggestionListFollows', 'Cursor')

      it "opens to the correct position, and correctly closes on cancel", ->
        editor.insertText('x ab')
        triggerAutocompletion(editor, false, 'c')

        runs ->
          overlayElement = editorView.querySelector('.autocomplete-plus')

          expect(overlayElement).toExist()

          left = editorView.pixelPositionForBufferPosition([0, 2]).left
          expect(overlayElement.style.left).toBe "#{left}px"

          atom.commands.dispatch(editorView, 'autocomplete-plus:cancel')
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

    describe 'accepting suggestions', ->
      beforeEach ->
        editor.setText('ok then ')
        editor.setCursorBufferPosition([0, 20])

      it 'hides the suggestions list when a suggestion is confirmed', ->
        triggerAutocompletion(editor, false, 'a')

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

          # Accept suggestion
          suggestionListView = editorView.querySelector('.autocomplete-plus autocomplete-suggestion-list')
          atom.commands.dispatch(suggestionListView, 'autocomplete-plus:confirm')

          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

      describe "when the replacementPrefix is empty", ->
        beforeEach ->
          spyOn(provider, 'getSuggestions').andCallFake ->
            [text: 'someMethod()', replacementPrefix: '']

        it "will insert the text without replacing anything", ->
          editor.insertText('a')
          triggerAutocompletion(editor, false, '.')

          runs ->
            suggestionListView = editorView.querySelector('.autocomplete-plus autocomplete-suggestion-list')
            atom.commands.dispatch(suggestionListView, 'autocomplete-plus:confirm')

            expect(editor.getText()).toBe 'ok then a.someMethod()'

      describe 'when tab is used to accept suggestions', ->
        beforeEach ->
          atom.config.set('autocomplete-plus.confirmCompletion', 'tab')

        it 'inserts the word and moves the cursor to the end of the word', ->
          triggerAutocompletion(editor, false, 'a')

          runs ->
            key = atom.keymaps.constructor.buildKeydownEvent('tab', {target: document.activeElement})
            atom.keymaps.handleKeyboardEvent(key)

            expect(editor.getText()).toBe 'ok then ab'

            bufferPosition = editor.getCursorBufferPosition()
            expect(bufferPosition.row).toEqual(0)
            expect(bufferPosition.column).toEqual(10)

        it 'does not insert the word when enter completion not enabled', ->
          triggerAutocompletion(editor, false, 'a')

          runs ->
            key = atom.keymaps.constructor.buildKeydownEvent('enter', {keyCode: 13, target: document.activeElement})
            atom.keymaps.handleKeyboardEvent(key)
            expect(editor.getText()).toBe 'ok then a\n'

      describe 'when enter is used to accept suggestions', ->
        beforeEach ->
          atom.config.set('autocomplete-plus.confirmCompletion', 'enter')

        it 'inserts the word and moves the cursor to the end of the word', ->
          triggerAutocompletion(editor, false, 'a')

          runs ->
            key = atom.keymaps.constructor.buildKeydownEvent('enter', {target: document.activeElement})
            atom.keymaps.handleKeyboardEvent(key)

            expect(editor.getText()).toBe 'ok then ab'

            bufferPosition = editor.getCursorBufferPosition()
            expect(bufferPosition.row).toEqual(0)
            expect(bufferPosition.column).toEqual(10)

        it 'does not insert the word when tab completion not enabled', ->
          triggerAutocompletion(editor, false, 'a')

          runs ->
            key = atom.keymaps.constructor.buildKeydownEvent('tab', {keyCode: 13, target: document.activeElement})
            atom.keymaps.handleKeyboardEvent(key)
            expect(editor.getText()).toBe 'ok then a '

      describe "when the cursor suffix matches the replacement", ->
        beforeEach ->
          spyOn(provider, 'getSuggestions').andCallFake ->
            [text: 'oneomgtwo', replacementPrefix: 'one']

        it 'replaces the suffix with the replacement', ->
          editor.setText('ontwothree')
          editor.setCursorBufferPosition([0, 2])
          triggerAutocompletion(editor, false, 'e')

          runs ->
            suggestionListView = editorView.querySelector('.autocomplete-plus autocomplete-suggestion-list')
            atom.commands.dispatch(suggestionListView, 'autocomplete-plus:confirm')

            expect(editor.getText()).toBe 'oneomgtwothree'

      describe "when the cursor suffix does not match the replacement", ->
        beforeEach ->
          spyOn(provider, 'getSuggestions').andCallFake ->
            [text: 'oneomgTwo', replacementPrefix: 'one']

        it 'replaces the suffix with the replacement', ->
          editor.setText('ontwothree')
          editor.setCursorBufferPosition([0, 2])
          triggerAutocompletion(editor, false, 'e')

          runs ->
            suggestionListView = editorView.querySelector('.autocomplete-plus autocomplete-suggestion-list')
            atom.commands.dispatch(suggestionListView, 'autocomplete-plus:confirm')

            expect(editor.getText()).toBe 'oneomgTwotwothree'

    describe 'when auto-activation is disabled', ->
      beforeEach ->
        atom.config.set('autocomplete-plus.enableAutoActivation', false)

      it 'does not show suggestions after a delay', ->
        triggerAutocompletion(editor)

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

      it 'shows suggestions when explicitly triggered', ->
        triggerAutocompletion(editor)

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          atom.commands.dispatch(editorView, 'autocomplete-plus:activate')
          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

      it "stays open when typing", ->
        triggerAutocompletion(editor, false, 'a')

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          atom.commands.dispatch(editorView, 'autocomplete-plus:activate')
          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

          editor.insertText('b')
          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

      it 'accepts the suggestion if there is one', ->
        spyOn(provider, 'getSuggestions').andCallFake (options) ->
          [text: 'omgok']

        triggerAutocompletion(editor)

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          atom.commands.dispatch(editorView, 'autocomplete-plus:activate')
          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          expect(editor.getText()).toBe 'omgok'

      it 'does not auto-accept a single suggestion when filtering', ->
        spyOn(provider, 'getSuggestions').andCallFake ({prefix}) ->
          list = _.filter ['a', 'abc'], (word) -> word.indexOf(prefix) is 0
          ({text: t} for t in list)

        editor.insertText('a')
        atom.commands.dispatch(editorView, 'autocomplete-plus:activate')
        waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()
          expect(editorView.querySelectorAll('.autocomplete-plus li')).toHaveLength 2

          editor.insertText('b')
          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()
          expect(editorView.querySelectorAll('.autocomplete-plus li')).toHaveLength 1

      describe "strict matching of prefix when explicitly triggered", ->
        beforeEach ->
          spyOn(provider, 'getSuggestions').andCallFake ({prefix}) ->
            [{text: 'abcOk'}, {text: 'aabcOk'}]

        it 'strict matches, and confirms the suggestion with the strict match', ->
          editor.insertText 'ok ab'
          editor.setCursorBufferPosition([0, 1000])
          triggerAutocompletion(editor, false, 'c')

          runs ->
            expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
            atom.commands.dispatch(editorView, 'autocomplete-plus:activate')
            waitForAutocomplete()

          runs ->
            expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
            expect(editor.getText()).toBe 'ok abcOk'

        describe "when a provider uses its own prefix scheme", ->
          beforeEach ->
            specialProvider =
              selector: '*'
              getSuggestions: ({prefix}) ->
                replacementPrefix = "self #{prefix}"
                [{text: '[self abcOk]', replacementPrefix}, {text: '[self aabcOk]', replacementPrefix}]
            mainModule.consumeProvider(specialProvider)

          it 'ignores the suggestions with their own prefix scheme', ->
            editor.insertText 'yeah ab'
            editor.setCursorBufferPosition([0, 1000])
            triggerAutocompletion(editor, false, 'c')

            runs ->
              expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
              atom.commands.dispatch(editorView, 'autocomplete-plus:activate')
              waitForAutocomplete()

            runs ->
              expect(editorView.querySelector('.autocomplete-plus')).toExist()

              items = editorView.querySelectorAll('.autocomplete-plus li')
              expect(items).toHaveLength 3
              expect(items[0].textContent).toBe 'abcOk'
              expect(items[1].textContent).toBe '[self abcOk]'
              expect(items[2].textContent).toBe '[self aabcOk]'

          it 'resets the strict match on subsequent opens', ->
            editor.insertText 'yeah ab'
            editor.setCursorBufferPosition([0, 1000])
            triggerAutocompletion(editor, false, 'c')

            runs ->
              atom.commands.dispatch(editorView, 'autocomplete-plus:activate')
              waitForAutocomplete()

            runs ->
              expect(editorView.querySelector('.autocomplete-plus')).toExist()
              expect(editorView.querySelectorAll('.autocomplete-plus li')).toHaveLength 3

              editor.setText 'yeah '
              editor.setCursorBufferPosition([0, 1000])
              triggerAutocompletion(editor, false, 'a')

            runs ->
              atom.commands.dispatch(editorView, 'autocomplete-plus:activate')
              waitForAutocomplete()

            runs ->
              expect(editorView.querySelector('.autocomplete-plus')).toExist()
              expect(editorView.querySelectorAll('.autocomplete-plus li')).toHaveLength 4

    describe "when the replacementPrefix doesnt match the actual prefix", ->
      describe "when snippets are not used", ->
        beforeEach ->
          spyOn(provider, 'getSuggestions').andCallFake ->
            [text: 'something', replacementPrefix: 'bcm']

        it "only replaces the suggestion at cursors whos prefix matches the replacementPrefix", ->
          editor.setText """
          abc abc
          def
          """
          editor.setCursorBufferPosition([0, 3])
          editor.addCursorAtBufferPosition([0, 7])
          editor.addCursorAtBufferPosition([1, 3])
          triggerAutocompletion(editor, false, 'm')

          runs ->
            expect(editorView.querySelector('.autocomplete-plus')).toExist()
            suggestionListView = editorView.querySelector('.autocomplete-plus autocomplete-suggestion-list')
            atom.commands.dispatch(suggestionListView, 'autocomplete-plus:confirm')
            expect(editor.getText()).toBe """
            asomething asomething
            defm
            """

      describe "when snippets are used", ->
        beforeEach ->
          spyOn(provider, 'getSuggestions').andCallFake ->
            [snippet: 'ok(${1:omg})', replacementPrefix: 'bcm']
          waitsForPromise -> atom.packages.activatePackage('snippets')

        it "only replaces the suggestion at cursors whos prefix matches the replacementPrefix", ->
          editor.setText """
          abc abc
          def
          """
          editor.setCursorBufferPosition([0, 3])
          editor.addCursorAtBufferPosition([0, 7])
          editor.addCursorAtBufferPosition([1, 3])
          triggerAutocompletion(editor, false, 'm')

          runs ->
            expect(editorView.querySelector('.autocomplete-plus')).toExist()
            suggestionListView = editorView.querySelector('.autocomplete-plus autocomplete-suggestion-list')
            atom.commands.dispatch(suggestionListView, 'autocomplete-plus:confirm')
            expect(editor.getText()).toBe """
            aok(omg) aok(omg)
            defm
            """

  describe 'when opening a file without a path', ->
    beforeEach ->
      waitsForPromise ->
        atom.workspace.open('').then (e) ->
          editor = e
          editorView = atom.views.getView(editor)

      waitsForPromise ->
        atom.packages.activatePackage('language-text')

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
        mainModule = a.mainModule

      waitsFor ->
        mainModule.autocompleteManager?.ready

      runs ->
        autocompleteManager = mainModule.autocompleteManager
        spyOn(autocompleteManager, 'findSuggestions').andCallThrough()
        spyOn(autocompleteManager, 'displaySuggestions').andCallThrough()

    describe "when strict matching is used", ->
      beforeEach ->
        atom.config.set('autocomplete-plus.strictMatching', true)

      it 'using strict matching does not cause issues when typing', ->
        # FIXME: WTF does this test even test?
        runs ->
          editor.moveToBottom()
          editor.insertText('h')
          editor.insertText('e')
          editor.insertText('l')
          editor.insertText('l')
          editor.insertText('o')
          advanceClock(completionDelay + 1000)

        waitsFor ->
          autocompleteManager.findSuggestions.calls.length is 1

  describe 'when opening a javascript file', ->
    beforeEach ->
      runs ->
        atom.config.set('autocomplete-plus.enableAutoActivation', true)

      waitsForPromise -> atom.workspace.open('sample.js').then (e) ->
        editor = e
        editorView = atom.views.getView(editor)

      waitsForPromise ->
        atom.packages.activatePackage('language-javascript')

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
        mainModule = a.mainModule
        autocompleteManager = mainModule.autocompleteManager

      runs ->
        advanceClock(autocompleteManager.providerManager.fuzzyProvider.deferBuildWordListInterval)

    describe 'when fuzzyProvider is disabled', ->
      it 'should not show the suggestion list', ->
        atom.config.set('autocomplete-plus.enableBuiltinProvider', false)
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
        triggerAutocompletion(editor)

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

    describe 'when the buffer changes', ->
      it 'should show the suggestion list when suggestions are found', ->
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
        triggerAutocompletion(editor)

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

          # Check suggestions
          suggestions = ['function', 'if', 'left', 'shift']
          for item, index in editorView.querySelectorAll('.autocomplete-plus li span.word')
            expect(item.innerText).toEqual(suggestions[index])

      it 'should not show the suggestion list when no suggestions are found', ->
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        editor.moveToBottom()
        editor.insertText('x')

        waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

      it 'shows the suggestion list on backspace if allowed', ->
        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

          editor.moveToBottom()
          editor.insertText('f')
          editor.insertText('u')

          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()
          editor.insertText('\r')
          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          key = atom.keymaps.constructor.buildKeydownEvent('backspace', {target: document.activeElement})
          atom.keymaps.handleKeyboardEvent(key)

          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          key = atom.keymaps.constructor.buildKeydownEvent('backspace', {target: document.activeElement})
          atom.keymaps.handleKeyboardEvent(key)

          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()
          expect(editor.lineTextForBufferRow(13)).toBe('f')

      it 'does not shows the suggestion list on backspace if disallowed', ->
        runs ->
          atom.config.set('autocomplete-plus.backspaceTriggersAutocomplete', false)
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

          editor.moveToBottom()
          editor.insertText('f')
          editor.insertText('u')

          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()
          editor.insertText('\r')
          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          key = atom.keymaps.constructor.buildKeydownEvent('backspace', {target: document.activeElement})
          atom.keymaps.handleKeyboardEvent(key)

          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          key = atom.keymaps.constructor.buildKeydownEvent('backspace', {target: document.activeElement})
          atom.keymaps.handleKeyboardEvent(key)

          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          expect(editor.lineTextForBufferRow(13)).toBe('f')

      it "keeps the suggestion list open when it's already open on backspace", ->
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        editor.moveToBottom()
        editor.insertText('f')
        editor.insertText('u')

        waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()

          key = atom.keymaps.constructor.buildKeydownEvent('backspace', {target: document.activeElement})
          atom.keymaps.handleKeyboardEvent(key)

          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).toExist()
          expect(editor.lineTextForBufferRow(13)).toBe('f')

      it "does not open the suggestion on backspace when it's closed", ->
        atom.config.set('autocomplete-plus.backspaceTriggersAutocomplete', false)
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        editor.setCursorBufferPosition([2, 39]) # at the end of `items`

        runs ->
          key = atom.keymaps.constructor.buildKeydownEvent('backspace', {target: document.activeElement})
          atom.keymaps.handleKeyboardEvent(key)

          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

      # TODO: Pretty Sure This Test Will Not Catch A Regression In Behavior Due To The Way It Is Written
      it 'should not update the suggestion list while composition is in progress', ->
        triggerAutocompletion(editor)

        # unfortunately, we need to fire IME events from the editor's input node so the editor picks them up
        activeElement = editorView.rootElement.querySelector('input')

        runs ->
          spyOn(autocompleteManager.suggestionList, 'changeItems').andCallThrough()
          expect(autocompleteManager.suggestionList.changeItems).not.toHaveBeenCalled()

          activeElement.dispatchEvent(buildIMECompositionEvent('compositionstart', {target: activeElement}))
          activeElement.dispatchEvent(buildIMECompositionEvent('compositionupdate', {data: '~', target: activeElement}))

          waitForAutocomplete()

        runs ->
          expect(autocompleteManager.suggestionList.changeItems).not.toHaveBeenCalled()

          activeElement.dispatchEvent(buildIMECompositionEvent('compositionend', {target: activeElement}))
          activeElement.dispatchEvent(buildTextInputEvent({data: 'ã', target: activeElement}))

          expect(editor.lineTextForBufferRow(13)).toBe('fã')

      it 'does not show the suggestion list when it is triggered then no longer needed', ->
        runs ->
          editor.moveToBottom()
          editor.insertText('f')
          editor.insertText('u')
          editor.insertText('\r')

          waitForAutocomplete()

        runs ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

    describe 'select-previous event', ->
      it 'selects the previous item in the list', ->

        triggerAutocompletion(editor, false, 'a')

        runs ->
          items = editorView.querySelectorAll('.autocomplete-plus li')
          expect(items[0]).toHaveClass('selected')
          expect(items[1]).not.toHaveClass('selected')
          expect(items[2]).not.toHaveClass('selected')

          # Select previous item
          suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
          atom.commands.dispatch(suggestionListView, 'autocomplete-plus:select-previous')

          items = editorView.querySelectorAll('.autocomplete-plus li')
          expect(items[0]).not.toHaveClass('selected')
          expect(items[1]).not.toHaveClass('selected')
          expect(items[2]).toHaveClass('selected')

      it 'closes the autocomplete when up arrow pressed when only one item displayed', ->
        triggerAutocompletion(editor, false, 'q')

        runs ->
          # Accept suggestion
          key = atom.keymaps.constructor.buildKeydownEvent('down', {target: document.activeElement})
          atom.keymaps.handleKeyboardEvent(key)
          advanceClock(1)

          autocomplete = editorView.querySelector('.autocomplete-plus')
          expect(autocomplete).not.toExist()

      it 'does not close the autocomplete when down arrow pressed when many items', ->
        triggerAutocompletion(editor)

        runs ->
          # Accept suggestion
          key = atom.keymaps.constructor.buildKeydownEvent('down', {target: document.activeElement})
          atom.keymaps.handleKeyboardEvent(key)

          autocomplete = editorView.querySelector('.autocomplete-plus')
          expect(autocomplete).toExist()

      it 'does close the autocomplete when down arrow while up,down navigation not selected', ->
        atom.config.set('autocomplete-plus.navigateCompletions', 'ctrl-p,ctrl-n')
        triggerAutocompletion(editor, false)

        runs ->
          # Accept suggestion
          key = atom.keymaps.constructor.buildKeydownEvent('down', {target: document.activeElement})
          atom.keymaps.handleKeyboardEvent(key)
          advanceClock(1)

          autocomplete = editorView.querySelector('.autocomplete-plus')
          expect(autocomplete).not.toExist()

    describe 'select-next event', ->
      it 'selects the next item in the list', ->
        triggerAutocompletion(editor, false, 'a')

        runs ->
          items = editorView.querySelectorAll('.autocomplete-plus li')
          expect(items[0]).toHaveClass('selected')
          expect(items[1]).not.toHaveClass('selected')
          expect(items[2]).not.toHaveClass('selected')

          # Select next item

          suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
          atom.commands.dispatch(suggestionListView, 'autocomplete-plus:select-next')

          items = editorView.querySelectorAll('.autocomplete-plus li')
          expect(items[0]).not.toHaveClass('selected')
          expect(items[1]).toHaveClass('selected')
          expect(items[2]).not.toHaveClass('selected')

      it 'closes the autocomplete when up arrow pressed when only one item displayed', ->
        triggerAutocompletion(editor, false, 'q')

        runs ->
          # Accept suggestion
          key = atom.keymaps.constructor.buildKeydownEvent('up', {target: document.activeElement})
          atom.keymaps.handleKeyboardEvent(key)
          advanceClock(1)

          autocomplete = editorView.querySelector('.autocomplete-plus')
          expect(autocomplete).not.toExist()

      it 'does not close the autocomplete when up arrow pressed when many items', ->
        triggerAutocompletion(editor)

        runs ->
          # Accept suggestion
          key = atom.keymaps.constructor.buildKeydownEvent('up', {target: document.activeElement})
          atom.keymaps.handleKeyboardEvent(key)

          autocomplete = editorView.querySelector('.autocomplete-plus')
          expect(autocomplete).toExist()

      it 'does close the autocomplete when up arrow while up,down navigation not selected', ->
        atom.config.set('autocomplete-plus.navigateCompletions', 'ctrl-p,ctrl-n')
        triggerAutocompletion(editor)

        runs ->
          # Accept suggestion
          key = atom.keymaps.constructor.buildKeydownEvent('up', {target: document.activeElement})
          atom.keymaps.handleKeyboardEvent(key)
          advanceClock(1)

          autocomplete = editorView.querySelector('.autocomplete-plus')
          expect(autocomplete).not.toExist()

    describe 'when a suggestion is clicked', ->
      it 'should select the item and confirm the selection', ->
        triggerAutocompletion(editor, true, 'a')

        runs ->
          # Get the second item
          item = editorView.querySelectorAll('.autocomplete-plus li')[1]

          # Click the item, expect list to be hidden and
          # text to be added
          mouse = document.createEvent('MouseEvents')
          mouse.initMouseEvent('mousedown', true, true, window)
          item.dispatchEvent(mouse)
          mouse = document.createEvent('MouseEvents')
          mouse.initMouseEvent('mouseup', true, true, window)
          item.dispatchEvent(mouse)

          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
          expect(editor.getBuffer().getLastLine()).toEqual(item.innerText)

    describe '.cancel()', ->
      it 'unbinds autocomplete event handlers for move-up and move-down', ->
        triggerAutocompletion(editor, false)

        autocompleteManager.hideSuggestionList()
        editorView = atom.views.getView(editor)
        atom.commands.dispatch(editorView, 'core:move-down')
        expect(editor.getCursorBufferPosition().row).toBe(1)

        atom.commands.dispatch(editorView, 'core:move-up')
        expect(editor.getCursorBufferPosition().row).toBe(0)

  describe 'when a long completion exists', ->
    beforeEach ->
      runs ->
        atom.config.set('autocomplete-plus.enableAutoActivation', true)

      waitsForPromise -> atom.workspace.open('samplelong.js').then (e) ->
        editor = e

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
        mainModule = a.mainModule
        autocompleteManager = mainModule.autocompleteManager

    it 'sets the width of the view to be wide enough to contain the longest completion without scrolling', ->
      editor.moveToBottom()
      editor.insertNewline()
      editor.insertText('t')

      waitForAutocomplete()

      runs ->
        suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
        expect(suggestionListView.scrollWidth).toBe(suggestionListView.offsetWidth)
