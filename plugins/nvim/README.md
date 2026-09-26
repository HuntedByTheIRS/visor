# visor for Neovim

The editor half of visor. It finds the server, attaches a client to a V buffer,
and leaves the answers to the server.

It needs Neovim 0.10 or later and a `visor` binary, either on `PATH` or named in
`setup()`. There is no ftdetect file here and no syntax file: Neovim already
maps `.v` to the `v` filetype by itself, which the test checks rather than
assumes.

## Install

With a plugin manager that takes a directory:

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
  semantic_tokens = true,  -- ask for highlighting tokens on attach
  root_markers = { 'v.mod', '.git' },
})
```

Calling `setup()` is optional. Without it the defaults above apply and the
server starts for the first V buffer that opens.

`format_on_save` is off because it rewrites the whole buffer through `v fmt`,
and a project whose own format gate disagrees has a reason to run
`:VisorFormat` by hand instead.

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
and a real server behind it:

```sh
plugins/nvim/test/run.sh --bin /tmp/visor
```

It checks that a V buffer brings a client through initialize, that the root
search lands on the project and falls back to the buffer's directory when there
is no marker, that two projects are two clients, that `on_attach` ran, and that
`:VisorInfo` and `stop()` report what actually happened. Nothing in it mocks the
protocol.

## Known noise

Neovim asks for pull diagnostics when a V buffer opens. The server answers that
request with an error naming the diagnostics lane, because an empty list would
read as a file with no problems, so the editor shows that message. It goes away
when the diagnostics lane lands.
