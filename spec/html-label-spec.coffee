TestProvider = require('./lib/test-provider')

describe "HTML labels", ->
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

    waitsForPromise -> atom.workspace.open('sample.js').then (e) ->
      editor = e

    # Activate the package
    waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
      mainModule = a.mainModule
      autocompleteManager = mainModule.autocompleteManagers[0]

  it "should allow HTML in labels for suggestions in the suggestion list", ->
    runs ->
      # Register the test provider
      testProvider = new TestProvider(editor)
      mainModule.registerProviderForEditor(testProvider, editor)

      editor.moveToBottom()
      editor.insertText('o')

      advanceClock(completionDelay)

      autocompleteView = atom.views.getView(autocompleteManager)

      expect(autocompleteView.querySelector('li .label')).toHaveHtml('<span style="color: red">ohai</span>')
      expect(autocompleteView.querySelector('li')).toHaveClass('ohai')
