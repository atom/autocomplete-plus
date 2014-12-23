describe "CSS Language Support", ->
  [completionDelay, editorView, editor, autocompleteManager, mainModule, css] = []

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

      atom.config.set('autocomplete-plus.enableAutoActivation', true)

    waitsForPromise -> atom.workspace.open('css.css').then (e) ->
      editor = e

    # Activate the package
    waitsForPromise -> atom.packages.activatePackage('language-css').then (c) -> css = c

    # Activate the package
    waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
      mainModule = a.mainModule
      autocompleteManager = mainModule.autocompleteManagers[0]

  it "includes completions for the scope's completion preferences", ->
    runs ->
      editor.moveToEndOfLine()
      editor.insertText('o')
      editor.insertText('u')
      editor.insertText('t')

      advanceClock(completionDelay)
      editorView = atom.views.getView(editor)
      autocompleteView = atom.views.getView(autocompleteManager)
      items = autocompleteView.querySelectorAll('li')
      expect(editorView.querySelector('.autocomplete-plus')).toExist()
      expect(items.length).toBe(10)
      expect(items[0]).toHaveText('outline')
      expect(items[1]).toHaveText('outline-color')
      expect(items[2]).toHaveText('outline-width')
      expect(items[3]).toHaveText('outline-style')
