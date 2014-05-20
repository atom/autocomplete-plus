0.20.0 (May 20 2014)
====================

* Added an `renderLabelAsHtml` option to the `Suggestion` class that specifies whether the label for this suggestion should be rendered as HTML or not (default: false)

0.19.0 (May 10 2014)
====================

* Allow hyphens in wordlist. (#64)
* Add new words to wordlist when a special character has been entered. (#63)
* Cancel autocompletion when no suggestions are available. (#65)

0.18.0 (May 8 2014)
===================

* Refocus editor when hitting enter
* Cancel autocompletion when entering space
* Fix a bug that occurred when duplicating an editor (thanks @yosisa)

0.15.0 (Apr 25 2014)
====================

* Fix a bug that caused a stack overflow when using spanish / italian / korean keyboard layouts (Issues #22 and #40)
* `autocomplete-plus:select-next`, `autocomplete-plus:select-previous` and `autocomplete-plus:cancel` keymaps

0.14.0 (Apr 13 2014)
====================

* Fix provider unregistration API (#unregisterProviderFromEditorView(Provider, EditorView) -> #unregisterProvider(Provider))

0.13.0 (Apr 13 2014)
====================

* Fix notification for compatibility issues with autosave (@joefitzgerald)
* Fix bug where multiple calls to registerProviderForEditorView could result in the same provider being registered multiple times (@joefitzgerald)

0.12.0 (Apr 11 2014)
====================

* Other packages can now register suggestion providers, see an example here: https://github.com/saschagehlich/autocomplete-snippets
* Moved suggestion generation to FuzzyProvider class

0.11.0 (Apr 10 2014)
====================

Features
--------

* Added hotkey-activation back in (defaults to Ctrl+Shift+Space)
* Added warning when both auto-activation and the autosave package are active
* Added a delay option (integer) that defines when the autocompletion should happen after pressing a key
* Confirm button is now customizable (defaults to Tab)

Code stuff
----------

* Code has been refactored and tested
* Fixed styling
* Fixed positioning of the overlay (using CSS3 transforms)
* Scope autocompletion words are now added to the wordlist every time autocompletion happens
* Using the ES6 Set feature for unique arrays
* Using atom's keymap feature instead of handling the keyboard input manually
* Got rid of Atom's SelectListView, moved over to our own view class

0.10.0 (Apr 3 2014)
===================

* Fixing a little issue where the autocompletion would appear even though the word was already confirmed (#23, #25 - thanks to @rpg600)

0.9.0 (Mar 19 2014)
===================
* Correctly clean up registered events on the editor etc. Fixes an issue where closed tabs would result in uncaught exceptions.

0.8.0 (Mar 18 2014)
===================

* Pasting content will no longer toggle autocompletion
* Saving will cancel autocompletion

0.7.0 (Mar 9 2014)
==================

* Fixes an issue where moving the cursor is slowed down

0.6.0 (Mar 9 2014)
==================

* Fixes a bug that caused an uncaught exception when closing a tab with autosave enabled

0.5.0 (Mar 4 2014)
==================

* Added file blacklisting option (glob supported, separated by commas)
* Added TAB as a completion key
* Adds words to the wordlist as they are typed

0.4.0 (Mar 4 2014)
==================

* Only display up to 10 items
* Removed sorting from the word list generator
* Only run autocompletion when the buffer really changed
* More cancellation cases (on line switch, on tab switch)

0.1.0 - 0.3.0 (Mar 4 2014)
==========================

* Initial release
