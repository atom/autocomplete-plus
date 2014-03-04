# autocomplete+ package

View and insert possible completions in the editor while typing

## Installation

Since this is still in beta, you'll have to install it manually (I'll add it to apm later):

```
$ cd ~/.atom/packages
$ git clone https://github.com/saschagehlich/autocomplete-plus.git
$ cd autocomplete-plus
$ npm install
```

## Known bugs

* Sometimes double completions appear (e.g. `DispDisplayObject` when entering `Disp` and selecting `DisplayObject`)
* `Uncaught TypeError: Object #<AutocompleteView> has no method 'getModel'` when confirming selection
