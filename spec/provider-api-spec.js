'use babel'
/* eslint-env jasmine */

import { waitForAutocomplete, triggerAutocompletion } from './spec-helper'

describe('Provider API', () => {
  let [completionDelay, editor, mainModule, autocompleteManager, registration, testProvider, testProvider2] = []

  beforeEach(() => {
    runs(() => {
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

    // Activate the package
    waitsForPromise(() =>
      Promise.all([
        atom.packages.activatePackage('language-javascript'),
        atom.workspace.open('sample.js').then((e) => { editor = e }),
        atom.packages.activatePackage('autocomplete-plus').then((a) => { mainModule = a.mainModule })
      ]))

    waitsFor(() => {
      autocompleteManager = mainModule.autocompleteManager
      return autocompleteManager
    })
  })

  afterEach(() => {
    if (registration && registration.dispose) {
      registration.dispose()
    }
    registration = null
    if (testProvider && testProvider.dispose) {
      testProvider.dispose()
    }
    testProvider = null
  })

  describe('Provider API v2.0.0', () => {
    it('registers the provider specified by [provider]', () => {
      testProvider = {
        scopeSelector: '.source.js,.source.coffee',
        getSuggestions (options) { return [{text: 'ohai', replacementPrefix: 'ohai'}] }
      }

      expect(autocompleteManager.providerManager.applicableProviders(['workspace-center'], '.source.js').length).toEqual(1)
      registration = atom.packages.serviceHub.provide('autocomplete.provider', '2.0.0', [testProvider])
      return expect(autocompleteManager.providerManager.applicableProviders(['workspace-center'], '.source.js').length).toEqual(2)
    })

    it('registers the provider specified by the naked provider', () => {
      testProvider = {
        scopeSelector: '.source.js,.source.coffee',
        getSuggestions (options) { return [{text: 'ohai', replacementPrefix: 'ohai'}] }
      }

      expect(autocompleteManager.providerManager.applicableProviders(['workspace-center'], '.source.js').length).toEqual(1)
      registration = atom.packages.serviceHub.provide('autocomplete.provider', '2.0.0', testProvider)
      expect(autocompleteManager.providerManager.applicableProviders(['workspace-center'], '.source.js').length).toEqual(2)
    })

    it('registers the provider under the given list of labels, the default being [\'workspace-center\']', () => {
      testProvider = {
        scopeSelector: '.source.js,.source.coffee',
        getSuggestions (options) { return [{text: 'ohai', replacementPrefix: 'ohai'}] }
      }
      testProvider2 = {
        labels: ['testProvider2'],
        scopeSelector: '.source.js,.source.coffee',
        getSuggestions (options) { return [{text: 'ohai', replacementPrefix: 'ohai'}] }
      }

      expect(autocompleteManager.providerManager.applicableProviders(['workspace-center'], '.source.js').length).toEqual(1)
      registration = atom.packages.serviceHub.provide('autocomplete.provider', '2.0.0', testProvider)
      expect(autocompleteManager.providerManager.applicableProviders(['workspace-center'], '.source.js').length).toEqual(2)
      registration = atom.packages.serviceHub.provide('autocomplete.provider', '2.0.0', testProvider2)
      expect(autocompleteManager.providerManager.applicableProviders(['testProvider2'], '.source.js').length).toEqual(1)
      expect(autocompleteManager.providerManager.applicableProviders(['testProvider2', 'workspace-center'], '.source.js').length).toEqual(3)
    })

    it('passes the correct parameters to getSuggestions for the version', () => {
      testProvider = {
        scopeSelector: '.source.js,.source.coffee',
        getSuggestions (options) { return [{text: 'ohai', replacementPrefix: 'ohai'}] }
      }

      registration = atom.packages.serviceHub.provide('autocomplete.provider', '2.0.0', testProvider)

      spyOn(testProvider, 'getSuggestions')
      triggerAutocompletion(editor, true, 'o')

      runs(() => {
        let args = testProvider.getSuggestions.mostRecentCall.args[0]
        expect(args.editor).toBeDefined()
        expect(args.bufferPosition).toBeDefined()
        expect(args.scopeDescriptor).toBeDefined()
        expect(args.prefix).toBeDefined()

        expect(args.scope).not.toBeDefined()
        expect(args.scopeChain).not.toBeDefined()
        expect(args.buffer).not.toBeDefined()
        expect(args.cursor).not.toBeDefined()
      })
    })

    it('correctly displays the suggestion options', () => {
      testProvider = {
        scopeSelector: '.source.js, .source.coffee',
        getSuggestions (options) {
          return [{
            text: 'ohai',
            replacementPrefix: 'o',
            rightLabelHTML: '<span style="color: red">ohai</span>',
            description: 'There be documentation'
          }]
        }
      }
      registration = atom.packages.serviceHub.provide('autocomplete.provider', '2.0.0', testProvider)

      triggerAutocompletion(editor, true, 'o')

      runs(() => {
        let suggestionListView = autocompleteManager.suggestionList.suggestionListElement
        expect(suggestionListView.element.querySelector('li .right-label')).toHaveHtml('<span style="color: red">ohai</span>')
        expect(suggestionListView.element.querySelector('.word')).toHaveText('ohai')
        expect(suggestionListView.element.querySelector('.suggestion-description-content')).toHaveText('There be documentation')
        expect(suggestionListView.element.querySelector('.suggestion-description-more-link').style.display).toBe('none')
      })
    })

    it('favors the `displayText` over text or snippet suggestion options', () => {
      testProvider = {
        scopeSelector: '.source.js, .source.coffee',
        getSuggestions (options) {
          return [{
            text: 'ohai',
            snippet: 'snippet',
            displayText: 'displayOHAI',
            replacementPrefix: 'o',
            rightLabelHTML: '<span style="color: red">ohai</span>',
            description: 'There be documentation'
          }]
        }
      }
      registration = atom.packages.serviceHub.provide('autocomplete.provider', '2.0.0', testProvider)

      triggerAutocompletion(editor, true, 'o')

      runs(() => {
        let suggestionListView = autocompleteManager.suggestionList.suggestionListElement
        expect(suggestionListView.element.querySelector('.word')).toHaveText('displayOHAI')
      })
    })

    it('correctly displays the suggestion description and More link', () => {
      testProvider = {
        scopeSelector: '.source.js, .source.coffee',
        getSuggestions (options) {
          return [{
            text: 'ohai',
            replacementPrefix: 'o',
            rightLabelHTML: '<span style="color: red">ohai</span>',
            description: 'There be documentation',
            descriptionMoreURL: 'http://google.com'
          }]
        }
      }
      registration = atom.packages.serviceHub.provide('autocomplete.provider', '2.0.0', testProvider)

      triggerAutocompletion(editor, true, 'o')

      runs(() => {
        let suggestionListView = autocompleteManager.suggestionList.suggestionListElement
        let content = suggestionListView.element.querySelector('.suggestion-description-content')
        let moreLink = suggestionListView.element.querySelector('.suggestion-description-more-link')
        expect(content).toHaveText('There be documentation')
        expect(moreLink).toHaveText('More..')
        expect(moreLink.style.display).toBe('inline')
        expect(moreLink.getAttribute('href')).toBe('http://google.com')
      })
    })

    describe('when the filterSuggestions option is set to true', () => {
      let getSuggestions = () => autocompleteManager.suggestionList.items.map(({text}) => ({text}))

      beforeEach(() => editor.setText(''))

      it('filters suggestions based on the default prefix', () => {
        testProvider = {
          scopeSelector: '.source.js',
          filterSuggestions: true,
          getSuggestions (options) {
            return [
              {text: 'okwow'},
              {text: 'ohai'},
              {text: 'ok'},
              {text: 'cats'},
              {text: 'something'}
            ]
          }
        }
        registration = atom.packages.serviceHub.provide('autocomplete.provider', '2.0.0', testProvider)

        editor.insertText('o')
        editor.insertText('k')
        waitForAutocomplete()

        runs(() =>
          expect(getSuggestions()).toEqual([
            {text: 'ok'},
            {text: 'okwow'}
          ])
        )
      })

      it('filters suggestions based on the specified replacementPrefix for each suggestion', () => {
        testProvider = {
          scopeSelector: '.source.js',
          filterSuggestions: true,
          getSuggestions (options) {
            return [
              {text: 'ohai'},
              {text: 'hai'},
              {text: 'okwow', replacementPrefix: 'k'},
              {text: 'ok', replacementPrefix: 'nope'},
              {text: '::cats', replacementPrefix: '::c'},
              {text: 'something', replacementPrefix: 'sm'}
            ]
          }
        }
        registration = atom.packages.serviceHub.provide('autocomplete.provider', '2.0.0', testProvider)

        editor.insertText('h')
        waitForAutocomplete()

        runs(() =>
          expect(getSuggestions()).toEqual([
            {text: '::cats'},
            {text: 'hai'},
            {text: 'something'}
          ])
        )
      })

      it('allows all suggestions when the prefix is an empty string / space', () => {
        testProvider = {
          scopeSelector: '.source.js',
          filterSuggestions: true,
          getSuggestions (options) {
            return [
              {text: 'ohai'},
              {text: 'hai'},
              {text: 'okwow', replacementPrefix: ' '},
              {text: 'ok', replacementPrefix: 'nope'}
            ]
          }
        }
        registration = atom.packages.serviceHub.provide('autocomplete.provider', '2.0.0', testProvider)

        editor.insertText('h')
        editor.insertText(' ')
        waitForAutocomplete()

        runs(() =>
          expect(getSuggestions()).toEqual([
            {text: 'ohai'},
            {text: 'hai'},
            {text: 'okwow'}
          ])
        )
      })
    })
  })
})
