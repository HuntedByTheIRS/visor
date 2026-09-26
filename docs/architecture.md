# Architecture

## Shape

```text
plugins/nvim (Lua, vim.lsp)            plugins/code, plugins/vim (later)
                 \                                    /
                  \       JSON-RPC over stdio        /
                   v                                v
+-------------------------------------------------------------------+
| visor (V binary)                                                  |
|   lsp/       initialize, capabilities, sync, routing, cancel,     |
|              progress, workspace folders, configuration           |
|   features/  hover, completion, signature help, def*, refs,       |
|              rename, symbols, folding, semantic tokens, inlay     |
|              hints, code actions and lens, call hierarchy         |
|   engine/    tree-sitter-V -> PSI -> index -> semantic layer      |
|              ported from v-analyzer (MIT)                         |
|   diag/      debounce, single-flight per module root, queue       |
|   vtool/     V binary discovery, version and capability probe,    |
|              `-check` over stdin, `fmt -`                         |
+-------------------------------------------------------------------+
                              |
                    subprocess: `v` (0.5.x and later)
```

Modules import downward only. `vtool/` and `engine/` know nothing about the
protocol, `features/` reads the engine and answers questions, and `lsp/` owns the
wire. Nothing imports `main`.

`lsp/`, `features/`, `vtool/`, `engine/`, `main.v` and the Neovim client in
`plugins/nvim` exist today. `diag/` and the other editor clients are the shape
being built toward, and the state column below says which modules have landed.

| Module | State | Owns | Imports from this tree |
| --- | --- | --- | --- |
| `vtool/` | in the tree | V binary discovery, the version and capability probe, `-check` over stdin, `fmt -` | nothing |
| `engine/` | in the tree | tree-sitter V to PSI to index, ported from v-analyzer | its own submodules and the vendored bindings |
| `features/` | in the tree | the typed answers the handlers send: the whole-buffer `v fmt` edit, and the token walk over the parse tree | `engine/`, `vtool/` |
| `lsp/` | in the tree | the wire: framing, capabilities, routing, sync, cancellation, progress, shutdown | `features/` for the answers, plus `io`, `json2` and `os` |
| `diag/` | planned | debounce, one check in flight per module root, cancellation | `vtool/` |
| `main.v` | in the tree | the entry point and the stdio loop | `lsp/` |
| `plugins/nvim/` | in the tree | the Neovim client: server search and attach | nothing, it speaks the protocol |

## Hard rules

These are the spine of the project. A change can be rejected for breaking any of
them.

1. Process boundary only. visor may run `v` and parse what it prints. It may
   not import `v.ast`, `v.flat`, `v.parser`, `v.checker`, `v.pref` or
   `v.scanner`. V deleted the V1 AST in September 2026 and the replacement is
   mid-migration, so anything coupled to compiler internals has a deadline it
   does not control.

2. No V1 compatibility dependency. Never run `-vls-mode` or `-line-info`.
   Hover, completion and go-to-definition in vls go through `-line-info`, and
   only the compatibility compiler implements it. A feature that exists only
   there gets implemented in-process here.

3. Probe, then report. At startup visor probes `v version` and each flag it
   depends on. A missing capability produces a visible message. It must never
   look like "no problems found".

4. The parser sits behind an interface. `ParserEngine` is the seam that keeps
   a V-native parser reachable as a swap-in without touching `features/*`.

5. MIT only. Ported v-analyzer code keeps its MIT notice, with provenance in
   `NOTICE`. No vls source is copied or adapted; vls is GPL-2.0 and reading it
   for behavior is not the same as shipping it.

6. Version tracking is a deliverable. The weekly V-drift job is required for
   release. A new V compiler release is the trigger for a matching visor release.

7. No monolith. Each subsystem is its own module directory with its own
   tests. A source file over roughly 4 kLOC fails review. vls keeps a 216 KB
   `handlers.v`; this rule exists so visor does not grow one.

8. Every piece of prose gets the humanizer pass. Commit messages, docs,
   comments, error text a person reads, release notes. Draft, ask what makes it
   read as machine written, revise.

9. Commit often, small. One logical change per commit, made as the work
   happens. A lane that lands as one commit was done in the wrong shape.

## Why the compiler talks back through a pipe

`v -check -nocolor -` reads a buffer on stdin, reports errors as
`file:line:col: error: message` against a synthetic filename, and writes nothing
into your workspace. That is how an editor buffer that has never been saved gets
diagnosed. `v fmt -` does the same for formatting. Both are exit-code driven, so
the diagnostics engine can stay simple: run the compiler, read the codes and the
lines it prints.

## Diagnostics scheduling

A check run starts a whole compiler. One per keystroke would be a process storm,
so `diag/` debounces per document, allows one check in flight per module root,
caps concurrent subprocesses, and cancels a check whose buffer has moved on. The
test for this asserts the process count after a hundred edit cycles, not just
that the diagnostics looked right.
