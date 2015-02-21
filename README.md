# autocomplete+ package [![OS X Build Status](https://travis-ci.org/atom-community/autocomplete-plus.svg?branch=master)](https://travis-ci.org/atom-community/autocomplete-plus) [![Windows Build Status](https://ci.appveyor.com/api/projects/status/4faqdkcw2d0ybgiv/branch/master?svg=true)](https://ci.appveyor.com/project/joefitzgerald/autocomplete-plus/branch/master)
[![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/atom-community/autocomplete-plus)


[View the changelog](https://github.com/atom-community/autocomplete-plus/releases)

View and insert possible completions in the editor while typing

![Autocomplete+](http://s14.directupload.net/images/140304/y7r7g5df.gif)

**Note:** In the example above, `Show Suggestions On Keystroke` is enabled.

![The Show Suggestions On Keystroke Setting](https://cloud.githubusercontent.com/assets/744740/5886909/a7071c2a-a372-11e4-9894-f12db4e8a1ae.png)

## Installation

* APM: `apm install autocomplete-plus`
* Preferences: Open Atom and go to `Preferences > Packages`, search for `autocomplete-plus`, and install it

## Providers

`autocomplete+` has a powerful autocomplete provider API, allowing provider authors to add language-specific behavior to this package.

You should *definitely* install additional providers (the default provider bundled with this package is somewhat crude): https://github.com/atom-community/autocomplete-plus/wiki/Autocomplete-Providers

## Usage

Just type some stuff, and autocomplete+ will automatically show you some suggestions.
Press `UP` and `DOWN` to select another suggestion, press `TAB` to confirm your selection. You can change the default keymap in `Preferences`:

* Keymap For Confirming A Suggestion
* Keymap For Navigating The Suggestion List

Additionally, the keymap can be customized in your keymap.cson:

```coffeescript
'atom-text-editor:not(mini).autocomplete-active':
  'tab': 'unset!'
  'enter': 'autocomplete-plus:confirm'
  'up': 'unset!'
  'down': 'unset!'
  'ctrl-p': 'autocomplete-plus:select-previous'
  'ctrl-n': 'autocomplete-plus:select-next'
```

## Features

* Shows suggestions while typing
* Includes a default provider (`FuzzyProvider`):
  * Wordlist generation happens when you open a file, while editing the file, and on save
  * Suggestions are calculated using `fuzzaldrin`
* Exposes a provider API which can be used to extend the functionality of the package and provide targeted / contextually correct suggestions
* Disable autocomplete for file(s) via blacklisting
* Disable autocomplete for editor scope(s) via blacklisting

## Provider API

Great autocomplete depends on having great autocomplete providers. If there is not already a great provider for the language / grammar that you are working in, please consider creating a provider.

[Read the `Provider API` documentation](https://github.com/atom-community/autocomplete-plus/wiki/Provider-API) to learn how to create a new autocomplete provider.
