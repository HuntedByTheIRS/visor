# visor for Neovim

The editor half of visor. It finds the server, attaches a client to a V buffer,
and leaves the answers to the server.

It needs Neovim 0.11 or later and a `visor` binary, either on `PATH` or named in
`setup()`. The 0.11 floor is `vim.lsp.get_clients` and the filter that reaches a
client whose initialize reply is still in flight.

There is no syntax file here. Neovim's own table maps `.vv` and `.vsh` to the `v`
filetype, and `.v` goes through a heuristic that reads the first 500 lines of the
buffer: a line ending in a period answers Coq, a line ending in a semicolon or a
`module name (` header answers Verilog. V shares that extension, and V source
trips the heuristic — visor's own `main.v` does, inside its usage string, so the
plugin would not attach to the source it ships with. Loading the plugin sets
`g:filetype_v` to `v` unless something already set it, which is the runtime's own
door for this and stops detection before it guesses. All three extensions then
arrive as `v` and the filetype hook is what starts the server.

## Install

The installer in the repository writes this setup for you, into a profile of its
own:

```sh
v run tools/install_lsp.vsh nvim
```

That builds the server, copies this plugin into the profile, and leaves a
command on `PATH` that starts Neovim under it.

By hand, with a plugin manager that takes a directory:

```lua
{ dir = '/path/to/visor/plugins/nvim' }
```

By hand, from this checkout:

```sh
nvim --cmd 'set runtimepath^=/path/to/visor/plugins/nvim' some_file.v
```

The server is found in this order: the `cmd` you pass to `setup()`, then
`$VISOR_BIN`, then `visor` on `PATH`. A tree that has just been built can point
at its own binary with `vim.env.VISOR_BIN = '/path/to/visor/visor'` and no
install step.

## Settings

```lua
require('visor').setup({
  cmd = nil,               -- a path, or an argv list
  autostart = true,        -- start on the filetype event
  format_on_save = false,  -- write through `v fmt` on every save
  format_timeout_ms = 10000, -- how long a formatting request may take
  semantic_tokens = true,  -- ask for highlighting tokens on attach
  root_markers = { 'v.mod', '.git' },
})
```

Calling `setup()` is optional. Without it the defaults above apply and the
server starts for the first V buffer that opens.

`format_on_save` is off because it rewrites the whole buffer through `v fmt`,
and a project whose own format gate disagrees has a reason to run
`:VisorFormat` by hand instead.

`format_timeout_ms` is ten seconds rather than Neovim's one, because a save is
not a keystroke: on a cold machine `v fmt` over a large file can take longer
than the default, and a request that times out is cancelled, so the file would
go to disk as it stands. When that happens the plugin says so rather than
letting a save pass for formatted. Nothing the plugin does during a save can
cancel the write either: a formatting failure costs a message, not the file.

`semantic_tokens` is on because the server only advertises the provider when it
can serve it. It does not decide whether highlighting happens: Neovim starts the
lane itself for any client that advertises the provider (0.11 calls
`semantic_tokens.start` from its own client attach, 0.12 has the capability on
by default), so turning the option off stops this plugin asking and nothing
more. What a server advertises is the switch. Highlighting covers what the parse
tree can name on its own:
declarations, the types they mention, literals, comments, attributes, keywords
and operators. A call to a function is not among them, because telling a call
from a field of the same name needs the index rather than the tree, so the
editor's own syntax highlighting keeps covering those.

## Commands

| Command | What it does |
| --- | --- |
| `:VisorStart` | Start the server for this buffer |
| `:VisorStop` | Stop every visor client |
| `:VisorRestart` | Stop, then start one for this buffer |
| `:VisorInfo` | Print the executable, the clients and their roots |
| `:VisorFormat` | Format this buffer through the server |

`:VisorInfo` is the answer to "is this plugged in". It prints the executable the
plugin found, and one line per client with its version and root.

## What is proven

`test/run.sh` starts a headless Neovim with this directory on the runtimepath
and a real server behind it. With no script named it runs all three:

```sh
plugins/nvim/test/run.sh --bin /tmp/visor
```

| Script | What it settles |
| --- | --- |
| `connect.lua` | a V buffer brings a client through initialize, the root search lands on the project and falls back to the buffer's directory when there is no marker, two projects are two clients, `on_attach` ran, and `:VisorInfo` and `stop()` report what happened. Every buffer in it is opened as a file, so the filetype is the editor's answer and not the script's: `.v`, `.vv` and `.vsh` each reach the hook, including a `.v` whose content is the shape the Coq heuristic claims |
| `format.lua` | `:VisorFormat` and format on save put what `v fmt` wrote into the buffer, a save with the setting off leaves it alone, a per-buffer override wins, the file on disk only changes at save, and a save the server never answers for still lands and says so |
| `highlights.lua` | tokens arrive and land as highlight: the module keyword, a comment, a struct name, a field, a const, a number and a string are each read back out of the editor with the type the walk gave them, and a const carries the read only modifier |

Nothing in them mocks the protocol.

## Diagnostics

Neovim asks for pull diagnostics when a V buffer opens, and it advertises that
it will show what the server pushes. The server does both from one report: the
pull answers about the buffer the client is holding, and a check the edits earn
is pushed as `textDocument/publishDiagnostics` once the typing stops. A buffer
that has never been saved is diagnosed like any other, because the text travels
to the compiler on stdin.
