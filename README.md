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
to `main`, and the protocol core answers `initialize`, `shutdown` and `exit`
over stdio. Requests that need semantics still come back as `MethodNotFound`,
because wiring the engine to the features is the work in progress. Everything
under Features is the v0.1.0 target rather than something you can install
today.

## Features, targeted for v0.1.0

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
scope for v0.1.0. `ROADMAP.md` carries the detail and the release cadence.

## Requirements

Linux on amd64 or arm64, with a V compiler on `PATH`. The server probes
`v version` at startup and tells you when a flag it depends on is missing,
rather than quietly returning an empty result.

The protocol layer imports `json2`, which V added after the 0.5.2 release, so the
tree needs a current V master: a 0.5.2 release asset cannot build it, and CI
builds V master from source for that reason. `vlib/json` is not an alternative,
being deprecated in favour of `json2` ("`json` will be removed soon; use the pure
V `json2` module instead"). The 0.1.x series gives visor its own JSON layer and
lowers this floor again; `ROADMAP.md` carries the reasoning.

Compiler discovery order: `VISOR_V_COMMAND`, then `VEXE`, then `v` on `PATH`.

## Build

    v -o visor .
    ./visor --version

## Editors

A VS Code and VSCodium extension and a Neovim configuration are planned for
v0.1.0. Both will find the server themselves.

## Contributing

`CONTRIBUTING.md` has the build, the test and the review rules. Bugs and feature
requests go through the issue tracker, whose format lives in `ISSUES.md`;
questions go to the discussions, governed by `DISCUSSIONS.md`; security reports
go through `SECURITY.md`; `CODE_OF_CONDUCT.md` covers how people treat each
other in all three places.

The internals are in `docs/architecture.md`. `AGENTS.md` carries the rules for
automated contributors.

## License

MIT. Code ported from v-analyzer keeps its MIT notice, with provenance recorded
in `NOTICE`.
