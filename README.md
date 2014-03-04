# autocomplete+ package

View and insert possible completions in the editor while typing

## Installation

Since this is still in beta, you'll have to install it manually (I'll add it to apm later):

```
$ cd ~/.atom/packages
$ git clone git@github.com:saschagehlich/autocomplete-plus.git
```

## Known bugs

* `Uncaught TypeError: Object #<AutocompleteView> has no method 'getModel'` when confirming selection
* `Uncaught TypeError: Cannot call method 'invert' of null` when confirming selection
