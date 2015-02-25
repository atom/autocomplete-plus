{waitForAutocomplete} = require './spec-helper'

describe 'HTML labels', ->
  [completionDelay, editorView, editor, mainModule, autocompleteManager, registration] = []

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

    waitsForPromise ->
      atom.packages.activatePackage('language-javascript')

    # Activate the package
    waitsForPromise -> atom.packages.activatePackage('autocomplete-plus').then (a) ->
      mainModule = a.mainModule

    waitsFor ->
      mainModule.autocompleteManager?.ready

    runs ->
      autocompleteManager = mainModule.autocompleteManager

  afterEach ->
    registration?.dispose()

  it 'should allow HTML in labels for suggestions in the suggestion list', ->
    runs ->
      testProvider =
        requestHandler: (options) ->
          [{
            word: 'ohai',
            prefix: 'ohai',
            label: '<span style="color: red">ohai</span>',
            renderLabelAsHtml: true,
            className: 'ohai'
          }]
        selector: '.source.js'
      registration = atom.packages.serviceHub.provide('autocomplete.provider', '1.0.0', {provider: testProvider})

      editor.moveToBottom()
      editor.insertText('o')

      waitForAutocomplete()

      runs ->
        suggestionListView = atom.views.getView(autocompleteManager.suggestionList)
        expect(suggestionListView.querySelector('li .completion-label')).toHaveHtml('<span style="color: red">ohai</span>')
        expect(suggestionListView.querySelector('li')).toHaveClass('ohai')
