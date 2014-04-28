# require "../spec-helper"
# {$, EditorView, WorkspaceView} = require 'atom'
# AutocompleteView = require '../../lib/autocomplete-view'
# Autocomplete = require '../../lib/autocomplete'

# describe "Autocomplete", ->
#   [activationPromise, autocomplete, completionDelay] = []
#   [leftPaneView, rightPaneView] = []
#   [leftEditor, rightEditor] = []
#   [leftEditorView, rightEditorView] = []
#   [leftAutocomplete, rightAutocomplete] = []

#   describe "Issue 50", ->
#     beforeEach ->
#       # Create a fake workspace and open a sample file
#       atom.workspaceView = new WorkspaceView
#       atom.workspaceView.openSync "sample.js"
#       atom.workspaceView.simulateDomAttachment()

#       # Set to live completion
#       atom.config.set "autocomplete-plus.enableAutoActivation", true

#       # Set the completion delay
#       completionDelay = 100
#       atom.config.set "autocomplete-plus.autoActivationDelay", completionDelay
#       completionDelay += 100 # Rendering delay

#       # Activate the package
#       activationPromise = atom.packages.activatePackage "autocomplete-plus"

#       leftPaneView = atom.workspaceView.getActivePaneView()
#       rightPaneView = leftPaneView.splitRight(leftPaneView.copyActiveItem())

#       [leftEditorView, rightEditorView] = atom.workspaceView.getEditorViews()
#       leftEditor = leftEditorView.editor
#       rightEditor = rightEditorView.editor

#       leftAutocomplete = new AutocompleteView leftEditorView
#       rightAutocomplete = new AutocompleteView rightEditorView

#     describe "when splitting the view and closing it", ->
#       it "does not throw an error when triggering autocompletion", ->
#         waitsForPromise ->
#           activationPromise

#         runs ->
#           leftEditorView.attachToDom()
#           rightEditorView.attachToDom()

#           leftEditor.moveCursorToBottom()
#           leftEditor.insertText "c"

#           advanceClock completionDelay

#           expect(leftEditorView.find(".autocomplete-plus")).toExist()

#           # This fails, even though in atom, it works...
#           expect(rightEditorView.find(".autocomplete-plus")).toExist()
