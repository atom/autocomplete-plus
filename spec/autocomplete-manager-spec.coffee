{triggerAutocompletion, buildIMECompositionEvent, buildTextInputEvent} = require('./spec-helper')
_ = require('underscore-plus')
{KeymapManager} = require('atom')
TestProvider = require('./lib/test-provider')

describe "Autocomplete Manager", ->
  [completionDelay, editorView, editor, autocompleteManager, mainModule] = []

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

  describe "when auto-activation is enabled", ->
    beforeEach ->
      runs -> atom.config.set('autocomplete-plus.enableAutoActivation', true)

      waitsForPromise -> atom.workspace.open('sample.js').then (e) ->
        editor = e

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
        mainModule = a.mainModule
        autocompleteManager = mainModule.autocompleteManagers[0]

      runs ->
        editorView = atom.views.getView(editor)


    describe "on changed events", ->
      it "should show the suggestion list when suggestions are found", ->
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        # Trigger an autocompletion
        triggerAutocompletion(editor)

        advanceClock(completionDelay)
        advanceClock(0)
        expect(editorView.querySelector('.autocomplete-plus')).toExist()

        # Check suggestions
        suggestions = ['function', 'if', 'left', 'shift']
        [].forEach.call editorView.querySelectorAll('.autocomplete-plus li span'), (item, index) ->
          expect(item.innerText).toEqual(suggestions[index])

      it "should not show the suggestion list when no suggestions are found", ->
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        # Trigger an autocompletion
        editor.moveToBottom()
        editor.insertText('x')

        advanceClock(completionDelay)
        advanceClock(0)
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

      it "should show the suggestion list when backspacing", ->
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        # Trigger an autocompletion
        editor.moveToBottom()
        editor.insertText('fu')

        advanceClock(completionDelay)
        advanceClock(0)
        key = atom.keymaps.constructor.keydownEvent('backspace', target: document.activeElement)
        atom.keymaps.handleKeyboardEvent(key)

        advanceClock(completionDelay)
        advanceClock(0)

        expect(editorView.querySelector(".autocomplete-plus")).toExist()
        expect(editor.lineTextForBufferRow(13)).toBe('f')

      it "should not update the suggestion list while composition is in progress", ->
        triggerAutocompletion(editor)

        advanceClock(completionDelay)
        advanceClock(0)

        autocompleteView = atom.views.getView(autocompleteManager)

        spyOn(autocompleteManager, 'changeItems').andCallThrough()

        document.activeElement.dispatchEvent(buildIMECompositionEvent('compositionstart', target: document.activeElement))
        document.activeElement.dispatchEvent(buildIMECompositionEvent('compositionupdate', data: "~", target: document.activeElement))

        advanceClock(completionDelay)
        advanceClock(0)

        expect(autocompleteManager.changeItems).not.toHaveBeenCalled()

        document.activeElement.dispatchEvent(buildIMECompositionEvent('compositionend', target: document.activeElement))
        document.activeElement.dispatchEvent(buildTextInputEvent(data: 'ã', target: document.activeElement))

        expect(editor.lineTextForBufferRow(13)).toBe('fã')

    describe "accepting suggestions", ->
      it "hides the suggestions list when a suggestion is confirmed", ->
        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

        # Trigger an autocompletion
        editor.moveToBottom()
        editor.moveToBeginningOfLine()
        editor.insertText('f')

        advanceClock(completionDelay)
        advanceClock(0)
        expect(editorView.querySelector('.autocomplete-plus')).toExist()

        # Accept suggestion
        autocompleteView = atom.views.getView(autocompleteManager)
        atom.commands.dispatch(autocompleteView, 'autocomplete-plus:confirm')

        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

      describe "when tab is used to accept suggestions", ->
        beforeEach ->
          atom.config.set('autocomplete-plus.confirmCompletion', 'tab')

        it "inserts the word and moves the cursor to the end of the word", ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

          # Trigger an autocompletion
          triggerAutocompletion(editor)

          advanceClock(completionDelay)
          advanceClock(0)

          autocompleteView = atom.views.getView(autocompleteManager)
          advanceClock(0)
          # Accept suggestion
          key = atom.keymaps.constructor.keydownEvent('tab', target: document.activeElement)
          atom.keymaps.handleKeyboardEvent(key)

          # Check for result
          expect(editor.getBuffer().getLastLine()).toEqual('function')

          # Check for cursor position
          bufferPosition = editor.getCursorBufferPosition()
          expect(bufferPosition.row).toEqual(13)
          expect(bufferPosition.column).toEqual(8)

        it "does not insert the word when enter completion not enabled", ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

          # Trigger an autocompletion
          triggerAutocompletion(editor)

          advanceClock(completionDelay)
          advanceClock(0)

          autocompleteView = atom.views.getView(autocompleteManager)
          # Accept suggestion
          key = atom.keymaps.constructor.keydownEvent('enter', keyCode: 13, target: document.activeElement)
          atom.keymaps.handleKeyboardEvent(key)

          # Check for result
          expect(editor.getBuffer().getLastLine()).toEqual('')

      describe "when enter is used to accept suggestions", ->
        beforeEach ->
          atom.config.set('autocomplete-plus.confirmCompletion', 'enter')

        it "inserts the word and moves the cursor to the end of the word", ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

          # Trigger an autocompletion
          triggerAutocompletion(editor)

          advanceClock(completionDelay)
          advanceClock(0)

          autocompleteView = atom.views.getView(autocompleteManager)
          advanceClock(0)
          # Accept suggestion
          key = atom.keymaps.constructor.keydownEvent('enter', target: document.activeElement)
          atom.keymaps.handleKeyboardEvent(key)

          # Check for result
          expect(editor.getBuffer().getLastLine()).toEqual('function')

          # Check for cursor position
          bufferPosition = editor.getCursorBufferPosition()
          expect(bufferPosition.row).toEqual(13)
          expect(bufferPosition.column).toEqual(8)

        it "does not insert the word when tab completion not enabled", ->
          expect(editorView.querySelector('.autocomplete-plus')).not.toExist()

          # Trigger an autocompletion
          triggerAutocompletion(editor)

          advanceClock(completionDelay)
          advanceClock(0)

          autocompleteView = atom.views.getView(autocompleteManager)
          # Accept suggestion
          key = atom.keymaps.constructor.keydownEvent('tab', target: document.activeElement)
          atom.keymaps.handleKeyboardEvent(key)

          # Check for result
          expect(editor.getBuffer().getLastLine()).toEqual('f ')

    describe "select-previous event", ->
      it "selects the previous item in the list", ->

        # Trigger an autocompletion
        triggerAutocompletion(editor)

        advanceClock(completionDelay)
        advanceClock(0)

        items = editorView.querySelectorAll('.autocomplete-plus li')
        expect(items[0]).toHaveClass('selected')
        expect(items[1]).not.toHaveClass('selected')
        expect(items[2]).not.toHaveClass('selected')
        expect(items[3]).not.toHaveClass('selected')

        autocompleteView = atom.views.getView(autocompleteManager)
        # Select previous item
        atom.commands.dispatch(autocompleteView, 'autocomplete-plus:select-previous')

        items = editorView.querySelectorAll('.autocomplete-plus li')
        expect(items[0]).not.toHaveClass('selected')
        expect(items[1]).not.toHaveClass('selected')
        expect(items[2]).not.toHaveClass('selected')
        expect(items[3]).toHaveClass('selected')

      it "closes the autocomplete when up arrow pressed when only one item displayed", ->
        # Trigger an autocompletion
        triggerAutocompletion(editor, false, 'q')

        advanceClock(completionDelay)
        advanceClock(0)

        # Accept suggestion
        key = atom.keymaps.constructor.keydownEvent('down', target: document.activeElement)
        atom.keymaps.handleKeyboardEvent(key)

        autocomplete = editorView.querySelector('.autocomplete-plus')
        expect(autocomplete).not.toExist()

      it "does not close the autocomplete when down arrow pressed when many items", ->
        # Trigger an autocompletion
        triggerAutocompletion(editor)

        advanceClock(completionDelay)
        advanceClock(0)

        # Accept suggestion
        key = atom.keymaps.constructor.keydownEvent('down', target: document.activeElement)
        atom.keymaps.handleKeyboardEvent(key)

        autocomplete = editorView.querySelector('.autocomplete-plus')
        expect(autocomplete).toExist()

      it "does close the autocomplete when down arrow while up,down navigation not selected", ->
        atom.config.set('autocomplete-plus.navigateCompletions', 'ctrl-p,ctrl-n')
        # Trigger an autocompletion
        triggerAutocompletion(editor, false)

        advanceClock(completionDelay)
        advanceClock(0)

        # Accept suggestion
        key = atom.keymaps.constructor.keydownEvent('down', target: document.activeElement)
        atom.keymaps.handleKeyboardEvent(key)

        autocomplete = editorView.querySelector('.autocomplete-plus')
        expect(autocomplete).not.toExist()

    describe "select-next event", ->
      it "selects the next item in the list", ->
        # Trigger an autocompletion
        triggerAutocompletion(editor)

        advanceClock(completionDelay)
        advanceClock(0)

        items = editorView.querySelectorAll('.autocomplete-plus li')
        expect(items[0]).toHaveClass('selected')
        expect(items[1]).not.toHaveClass('selected')
        expect(items[2]).not.toHaveClass('selected')
        expect(items[3]).not.toHaveClass('selected')

        # Select next item
        autocompleteView = atom.views.getView(autocompleteManager)
        atom.commands.dispatch(autocompleteView, 'autocomplete-plus:select-next')

        items = editorView.querySelectorAll('.autocomplete-plus li')
        expect(items[0]).not.toHaveClass('selected')
        expect(items[1]).toHaveClass('selected')
        expect(items[2]).not.toHaveClass('selected')
        expect(items[3]).not.toHaveClass('selected')

      it "closes the autocomplete when up arrow pressed when only one item displayed", ->
        # Trigger an autocompletion
        triggerAutocompletion(editor, false, 'q')

        advanceClock(completionDelay)
        advanceClock(0)

        # Accept suggestion
        key = atom.keymaps.constructor.keydownEvent('up', target: document.activeElement)
        atom.keymaps.handleKeyboardEvent(key)

        autocomplete = editorView.querySelector('.autocomplete-plus')
        expect(autocomplete).not.toExist()

      it "does not close the autocomplete when up arrow pressed when many items", ->
        # Trigger an autocompletion
        triggerAutocompletion(editor)

        advanceClock(completionDelay)
        advanceClock(0)

        # Accept suggestion
        key = atom.keymaps.constructor.keydownEvent('up', target: document.activeElement)
        atom.keymaps.handleKeyboardEvent(key)

        autocomplete = editorView.querySelector('.autocomplete-plus')
        expect(autocomplete).toExist()

      it "does close the autocomplete when up arrow while up,down navigation not selected", ->
        atom.config.set('autocomplete-plus.navigateCompletions', 'ctrl-p,ctrl-n')
        # Trigger an autocompletion
        triggerAutocompletion(editor)

        advanceClock(completionDelay)
        advanceClock(0)

        # Accept suggestion
        key = atom.keymaps.constructor.keydownEvent('up', target: document.activeElement)
        atom.keymaps.handleKeyboardEvent(key)

        autocomplete = editorView.querySelector('.autocomplete-plus')
        expect(autocomplete).not.toExist()

    describe "when a suggestion is clicked", ->
      it "should select the item and confirm the selection", ->
        # Trigger an autocompletion
        triggerAutocompletion(editor)

        advanceClock(completionDelay)
        advanceClock(0)

        # Get the second item
        item = editorView.querySelectorAll('.autocomplete-plus li')[1]

        # Click the item, expect list to be hidden and
        # text to be added
        mouse = document.createEvent('MouseEvents')
        mouse.initMouseEvent('mousedown', true, true, window)
        item.dispatchEvent mouse
        mouse = document.createEvent('MouseEvents')
        mouse.initMouseEvent('mouseup', true, true, window)
        item.dispatchEvent(mouse)

        expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
        expect(editor.getBuffer().getLastLine()).toEqual(item.innerText)

    describe ".cancel()", ->
      it "unbinds autocomplete event handlers for move-up and move-down", ->
        triggerAutocompletion(editor, false)
        autocompleteManager.cancel()
        editorView = atom.views.getView(editor)
        atom.commands.dispatch(editorView, 'core:move-down')
        expect(editor.getCursorBufferPosition().row).toBe(1)

        atom.commands.dispatch(editorView, 'core:move-up')
        expect(editor.getCursorBufferPosition().row).toBe(0)

  describe "when a long completion exists", ->
    beforeEach ->
      runs ->
        atom.config.set('autocomplete-plus.enableAutoActivation', true)

      waitsForPromise -> atom.workspace.open('samplelong.js').then (e) ->
        editor = e

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
        mainModule = a.mainModule
        autocompleteManager = mainModule.autocompleteManagers[0]

    it "sets the width of the view to be wide enough to contain the longest completion without scrolling", ->
      editor.moveToBottom()
      editor.insertNewline()
      editor.insertText('t')

      advanceClock(completionDelay)
      advanceClock(0)

      autocompleteView = atom.views.getView(autocompleteManager)
      expect(autocompleteView.scrollWidth).toBe(autocompleteView.offsetWidth)

  describe "when auto-activation is disabled", ->
    beforeEach ->
      runs ->
        atom.config.set('autocomplete-plus.enableAutoActivation', false)

      waitsForPromise -> atom.workspace.open('sample.js').then (e) ->
        editor = e

      # Activate the package
      waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
        mainModule = a.mainModule
        autocompleteManager = mainModule.autocompleteManagers[0]

      runs ->

    it "does not show suggestions after a delay", ->
      triggerAutocompletion(editor)

      advanceClock(completionDelay)
      advanceClock(0)
      expect(editorView.querySelector(".autocomplete-plus")).not.toExist()

    it "shows suggestions when explicitly triggered", =>
      triggerAutocompletion(editor)

      advanceClock(completionDelay)
      advanceClock(0)

      editorView = atom.views.getView(editor)
      expect(editorView.querySelector('.autocomplete-plus')).not.toExist()
      atom.commands.dispatch(editorView, 'autocomplete-plus:activate')
      expect(editorView.querySelector('.autocomplete-plus')).toExist()
