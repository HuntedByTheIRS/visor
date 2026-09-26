<p align="center">
  <img src="LOGO.png" alt="visor" width="320">
</p>

<h1 align="center">visor</h1>

<p align="center">
  A language server for V, written from the protocol up.
</p>

<p align="center">
  <a href="https://github.com/HuntedByTheIRS/visor/actions/workflows/ci.yml"><img src="https://github.com/HuntedByTheIRS/visor/actions/workflows/ci.yml/badge.svg" alt="ci"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT"></a>
  <img src="https://img.shields.io/badge/status-pre--release-orange.svg" alt="pre-release">
  <img src="https://img.shields.io/badge/LSP-3.17-blueviolet.svg" alt="LSP 3.17">
  <img src="https://img.shields.io/badge/compiler-V%20master%20(0.5.x)-grey.svg" alt="V master">
  <img src="https://img.shields.io/badge/platform-linux%20amd64%20%7C%20arm64-lightgrey.svg" alt="linux amd64 and arm64">
</p>

## What it does

visor gives V the editing that other languages stopped noticing they had:
diagnostics that arrive while you type, including in buffers you have never
saved; a definition that lands on the right declaration when three modules
declare the same name; completion, signature help, references, and a rename that
reaches every file it should.

It speaks LSP, so any editor with a client can use it. There is no launcher to
install and no daemon to keep alive.

## How it works

visor never links the compiler. It runs `v` as a subprocess and reads what that
process prints, which is why the server keeps working across compiler releases
that reshuffle everything underneath the language: V removed its V1 AST in
September 2026, and every feature that used to ride the V1 compatibility
compiler runs in-process here instead.

```text
  editor
  VS Code, VSCodium, Neovim, Vim
        |
        |  JSON-RPC over stdio
        v
  +---------------------------+
  |           visor           |
  |    lsp/        features/  |
  |    engine/     diag/      |
  |    vtool/                 |
  +---------------------------+
        |
        |  runs `v`, reads what it prints
        v
  +---------------------------+
  |        v compiler         |
  +---------------------------+
```

The cost of that boundary is one process per check. The gain is a server that
does not break when the compiler is refactored, and the trade is deliberate.

## The engine

Parsing and indexing come from [v-analyzer](https://github.com/vlang/v-analyzer)
(MIT), which already turns V source into a tree-sitter AST, a PSI tree and a
project-wide stub index. visor keeps that engine behind a `ParserEngine`
interface and writes its own protocol layer, diagnostics scheduling and editor
plumbing around it. [vls](https://github.com/vlang/vls) is read to see what
modern editor support for V looks like; none of its source is copied, and visor
stays MIT.

## Status

Pre-release, and honest about it. The repository builds, CI runs on every push
to `main`, and the protocol core serves the session over stdio: `initialize`,
`initialized`, `shutdown`, `exit`, the four document sync notifications, and the
two workspace notifications for folders and configuration.

`textDocument/diagnostic` is the one method the server knows and cannot answer.
It comes back as a request-failed error naming the diagnostics lane rather than
as an empty diagnostic list, because an empty list reads as a file with no
problems.

Formatting and semantic tokens are the two lanes that answer today. Both are
advertised only where they can be served: formatting when the startup probe
found a compiler that rewrites a buffer, tokens when the client named token
types this server emits and asked for whole-document requests. The providers
that have no handlers yet (hover, completion, definition and the rest) are left
unadvertised so they answer `MethodNotFound` instead of something empty, and
wiring the engine to them is the work in progress. Everything else under
Features is the v0.1.0 target rather than something you can install today.

## Features, targeted for v0.1.0

| Area | What ships | Status |
| --- | --- | --- |
| Diagnostics | pushed and pulled, including over unsaved buffers | N/A |
| Hover and completion | hover, completion, signature help | N/A |
| Navigation | definition, declaration, type definition, implementation, references | N/A |
| Rename | rename and prepare rename | N/A |
| Symbols | document symbols and workspace symbols | N/A |
| Selection and view | folding ranges, document highlight, selection range, range formatting | N/A |
| Semantic tokens | declarations, types, literals, comments, keywords and operators, read from the parse tree | in the tree |
| Code actions | code actions, code lens, call hierarchy | N/A |
| Formatting | `v fmt` over the whole buffer, on request or on save | in the tree |

An inline completion provider (LSP 3.18) and anything debugger shaped are out of
scope for v0.1.0. `ROADMAP.md` carries the detail and the release cadence.

## Requirements

Linux on amd64 or arm64, with a V compiler on `PATH`. The server probes
`v version` at startup and tells you when a flag it depends on is missing,
rather than quietly returning an empty result.

> The protocol layer imports `json2`, which V added after the 0.5.2 release, so
> the tree needs a current V master. A 0.5.2 release asset cannot build it, and
> CI builds V master from source for that reason. `vlib/json` is not the way
> out: it is deprecated in favour of `json2` in V's own words, "`json` will be
> removed soon; use the pure V `json2` module instead". The 0.1.x series gives
> visor its own JSON layer and lowers this floor again, and `ROADMAP.md` carries
> the reasoning. `NOTICE` has the route to a master build.

Compiler discovery order, first match wins:

| Order | Source |
| --- | --- |
| 1 | `VISOR_V_COMMAND` |
| 2 | `VEXE` |
| 3 | `v` on `PATH` |

## Build

```sh
v -o visor .
./visor --version
```

## Editors

Everything an editor needs is the protocol, so this repository ships one client
and the rest of the protocol. [`plugins/nvim`](plugins/nvim) is the Neovim
plugin: it finds the server on `PATH` or through `$VISOR_BIN`, attaches a client
to a V buffer, and starts no process until a V buffer opens. Its README carries
the settings and the commands.

A VS Code and VSCodium extension and a Vim configuration are planned after
v0.1.0. Both will find the server themselves.

## Contributing

Bugs and feature requests go through the issue tracker, whose format lives in
`ISSUES.md`; questions go to the discussions, governed by `DISCUSSIONS.md`;
security reports go through `SECURITY.md`; `CODE_OF_CONDUCT.md` covers how
people treat each other in all three places.

| Document | What it covers |
| --- | --- |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | the build, the test and the review rules |
| [`docs/architecture.md`](docs/architecture.md) | the modules, the hard rules, diagnostics scheduling |
| [`ROADMAP.md`](ROADMAP.md) | what ships when, and the compiler floor |
| [`ISSUES.md`](ISSUES.md) | what a bug report has to carry |
| [`DISCUSSIONS.md`](DISCUSSIONS.md) | the categories and the house rules |
| [`SECURITY.md`](SECURITY.md) | the private reporting route |
| [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) | how people treat each other in every space above |
| [`AGENTS.md`](AGENTS.md) | the rules for automated contributors |
| [`NOTICE`](NOTICE) | where the ported code came from, and the compiler the tree needs |

## License

MIT. Code ported from v-analyzer keeps its MIT notice, with provenance recorded
in `NOTICE`.
