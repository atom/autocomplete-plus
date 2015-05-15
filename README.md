# autocomplete+ package [![OS X Build Status](https://travis-ci.org/atom/autocomplete-plus.svg?branch=master)](https://travis-ci.org/atom/autocomplete-plus) [![Windows Build Status](https://ci.appveyor.com/api/projects/status/4faqdkcw2d0ybgiv/branch/master?svg=true)](https://ci.appveyor.com/project/joefitzgerald/autocomplete-plus/branch/master) [![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/atom/autocomplete-plus)

Displays possible autocomplete suggestions on keystroke (or manually by typing `ctrl-space`) and inserts a suggestion in the editor if confirmed.

[Changelog](https://github.com/atom/autocomplete-plus/releases)

## Installation

autocomplete+ is bundled with Atom. You don't have to do anything to install it.

## Providers

`autocomplete+` has a powerful autocomplete provider API, allowing provider authors to add language-specific behavior to this package.

You should *definitely* install additional providers (the default provider bundled with this package is somewhat crude): https://github.com/atom/autocomplete-plus/wiki/Autocomplete-Providers

## Usage

Just type some stuff, and autocomplete+ will automatically show you some suggestions.
Press `UP` and `DOWN` to select another suggestion, press `TAB` or `ENTER` to confirm your selection. You can change the default keymap in `Preferences`:

* Keymap For Confirming A Suggestion
* Keymap For Navigating The Suggestion List

Additionally, the keymap can be customized in your keymap.cson:

```coffeescript
'atom-text-editor:not(mini).autocomplete-active':
  'tab': 'unset!'
  'enter': 'autocomplete-plus:confirm'
  'up': 'unset!'
  'down': 'unset!'
  'ctrl-p': 'core:move-up'
  'ctrl-n': 'core:move-down'
```

## Features

* Shows suggestions while typing
* Includes a default provider (`SymbolProvider`):
  * Wordlist generation happens when you open a file, while editing the file, and on save
  * Suggestions are calculated using `fuzzaldrin`
* Exposes a provider API which can be used to extend the functionality of the package and provide targeted / contextually correct suggestions
* Disable autocomplete for file(s) via blacklisting
* Disable autocomplete for editor scope(s) via blacklisting
* Expands a snippet if an autocomplete+ provider includes one in a suggestion

## Provider API

Great autocomplete depends on having great autocomplete providers. If there is not already a great provider for the language / grammar that you are working in, please consider creating a provider.

[Read the `Provider API` documentation](https://github.com/atom/autocomplete-plus/wiki/Provider-API) to learn how to create a new autocomplete provider.

## `SymbolProvider` Configuration

If the default `SymbolProvider` is missing useful information for the language / grammar you're working with, please take a look at the [`SymbolProvider` Config API](https://github.com/atom/autocomplete-plus/wiki/SymbolProvider-Config-API).
