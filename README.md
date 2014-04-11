# autocomplete+ package

[View the changelog](https://github.com/saschagehlich/autocomplete-plus/blob/master/CHANGELOG.md)

View and insert possible completions in the editor while typing

![Autocomplete+](http://s14.directupload.net/images/140304/y7r7g5df.gif)

**Please note:** In the example above I have "Live completion" enabled.

## Installation

You can install autocomplete+ using the Preferences pane.

## Plugins

Also grab one of these awesome additions for autocomplete+:

* [autocomplete-snippets](https://atom.io/packages/autocomplete-snippets)
* [autocomplete-paths](https://atom.io/packages/autocomplete-paths)

## Usage

Just type some stuff, autocomplete+ will automatically show you some suggestions.
Press UP and DOWN to select another suggestion, press ENTER or TAB to confirm your selection.

## Features

* Shows autocompletion suggestions while typing
* Two modes: Live and delayed autocompletion (instant might slow down performance)
* Wordlist generation happens initially and on save (saves performance)
* Suggestions are calculated using `fuzzaldrin` (better results)
* File blacklisting
* Automatic wordlist expansion while typing

## Geeky Stuff: Adding Suggestion Providers

Since version 0.12.0, other packages are able to register suggestion providers to the autocomplete-plus package.

[See the tutorial on how to create and register suggestion providers](https://github.com/saschagehlich/autocomplete-plus/wiki/Tutorial:-Registering-and-creating-a-suggestion-provider)
