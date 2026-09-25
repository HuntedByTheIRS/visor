# visor

A language server for V.

Status: bootstrap. The repository builds, CI runs on every push, and the server
does not answer a single request yet. Everything under Features is the v0.1.0
target, not something you can install today.

## What it is meant to be

visor takes its semantic engine and its editor features from
[v-analyzer](https://github.com/vlang/v-analyzer) (MIT) and writes its own
protocol layer, diagnostics scheduling and editor plumbing. vls is read to see
what modern editor support for V looks like; none of its source is copied, and
visor stays MIT.

The server talks to the compiler through the `v` binary and never imports
compiler internals. That boundary is the point: V removed its V1 AST in
September 2026, and every feature that used to ride the V1 compatibility
compiler runs in-process here instead.

## Features, all targeted for v0.1.0

- diagnostics, pushed and pulled, including over unsaved buffers
- hover, completion, signature help
- definition, declaration, type definition, implementation, references
- rename and prepare rename
- document symbols and workspace symbols
- folding ranges, document highlight, selection range, range formatting
- semantic tokens, inlay hints
- code actions, code lens, call hierarchy
- formatting, which is `v fmt` verbatim

An inline completion provider (LSP 3.18) and anything debugger shaped are out of
scope for v0.1.0. `ROADMAP.md` has the detail.

## Requirements

Linux, amd64 or arm64, with a V compiler on `PATH`. The server probes
`v version` at startup and tells you when a flag it needs is missing instead of
returning an empty result.

Compiler discovery order: `VISOR_V_COMMAND`, then `VEXE`, then `v` on `PATH`.

## Build

    v -o visor .
    ./visor --version

## Editors

A VS Code and VSCodium extension and a Neovim config are planned for v0.1.0.
Both will find the server themselves; there is no launcher and no updater to
install.

## License

MIT. Code ported from v-analyzer keeps its MIT notice, with provenance recorded
in `NOTICE`.
