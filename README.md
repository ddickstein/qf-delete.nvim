Simple plugin that lets the `d` operator delete quickfix entries and `u` /
`<C-r>` undo and redo those deletions. Undos are tracked linearly rather than
in a tree. They are also tracked outside the quickfix lists, so each list has
its own history (meaning `:colder` or `:cnewer` will move you to a different
list, with its own history).

This plugin also provides its own implementation of `:Cfilter` and `:Lfilter`
from the runtime's cfilter plugin so that filters are also tracked in the undo
state.

### Related plugins
The following plugins improve the quickfix list in various ways. They may not
interact well with this plugin or with each other:
* https://github.com/kevinhwang91/nvim-bqf
* https://github.com/itchyny/vim-qfedit
* https://github.com/stevearc/quicker.nvim
* https://github.com/stefandtw/quickfix-reflector.vim
* https://github.com/romainl/vim-qf
