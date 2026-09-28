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
| `features/` | in the tree | the typed answers the handlers send: the whole-buffer `v fmt` edit, the token walk over the parse tree, the inlay hint walk over an open buffer and the workspace index, the outline of a buffer's own parse, the workspace search over the index, and the rename plan | `engine/`, `vtool/` |
| `lsp/` | in the tree | the wire: framing, capabilities, routing, sync, cancellation, progress, shutdown, and the diagnostics, inlay hint, symbol and rename lanes | `features/` for the answers, `diag/` for the checks, plus `io`, `json2`, `os` and `vtool` |
| `diag/` | in the tree | debounce per document, one check in flight per module root, the last report per buffer | `vtool/` |
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

`lsp/diagnostics.v` is where a report meets the wire, and both halves of the
lane come from one report. A finished check is kept per buffer version: a pull
about text already checked is answered from it, a pull that echoes the
`resultId` it holds comes back `unchanged`, and only an edit earns another
compiler run. The serving loop wakes for a scheduled check, not only for the
client, which is what lets a pushed report arrive while the editor is quiet:
`poll` on the client's descriptor for as long as the earliest check may wait,
then the checks run and the loop looks at the client again.

Positions are recomputed rather than adjusted. The compiler counts lines from
one and its column is a byte offset into the line, while the protocol counts
lines from zero and characters in UTF-16 code units, so a line holding an
astral character would otherwise be placed short by one unit per character
before the finding.

## Inlay hints, and the index they read

The hint lane answers from the parse tree, not from a compiler run. `v ast -p`
was measured first and it fills only the types written in the source, which
leaves a `:=` with nothing to show, so the types come from the ported engine
instead: `engine/` parses a buffer into a PSI and `engine/session.v` stands up
the stub index the inferer reads.

A session owns two things. One is the workspace index, built in `initialized`
from the folders the client named, because the reply to `initialize` is what the
client is waiting on. The other is the parse of every open buffer, replaced on
`didOpen`, `didChange` and `didSave` and dropped on `didClose`. A buffer's stubs
go into the index in place of the file's, and nothing is written to disk, so an
unsaved buffer is described as it stands. The measured cost is 143 ms and 15 ms
of stub index for this tree, and 8.2 s and 645 ms for vlib, which is why the
index is built once and the buffers are what change.

Two caches sit under the inference and both were keyed by a path, a node kind
and a range with no text in the key, so an edit that left every offset where it
was could read back the previous text's answer. `psi.forget_answers()` drops
both, and the session calls it whenever a buffer changes.

The walk itself is in `features/inlay_hints.v` and hands back labels with byte
offsets. Five families are in it: the parameter name an argument lands on, the
field name a positional struct literal initializes, the type a `:=` infers,
the code a `defer` places, shown whole up to two lines and as a snippet past
that, and the names of the attributes a function or a module carries, drawn
after the declaration they belong to. The wire half is `lsp/inlay_hints.v`. A
request the index cannot answer is refused in words, because an empty list
reads to a client as a buffer with nothing worth saying in it.

## Symbols and rename, and the two places they read

An outline and a search answer one question from two different places, and the
difference is the shape of each lane. `features/symbols.v` walks a buffer's
own parse, so the outline names what the file in front of the person declares,
including a file outside every indexed folder and a buffer nobody has saved.
`features/workspace_symbols.v` reads the stub index instead, so a search
reaches files nobody has opened, and describes those files as the disk has
them. Both answer a query with the closest names first: an exact name, then a
name that starts with the query, then one that contains it, then one whose
letters appear in order.

A method hangs under the type its receiver names, and the receiver is read as
text: the parser reports `fn Greeting.new()` with an empty receiver name and
the type in the receiver's own text, so the name of the enclosing type comes
from there. A method whose type the file does not declare stays where it is
written, with the receiver spelled out in its detail.

Rename is one resolution and one walk per file. `features/rename.v` resolves
the position through the parse the session holds, which is what tells two
same-named locals apart: a reference resolves to a declaration, and a
candidate is kept only when it resolves to that same one. Reach is read off
the declaration rather than guessed from the text: a local lives in one file,
a private name in every file of its module, and a public one also in the files
of the modules that import it, which is the whole of a public name's reach
because V has no re-export. The walk is therefore bounded by the index.

Candidates are matched by the place a name is declared rather than by its
text, because the two elements being compared can come from different parses
of the same file. An element the index built for a file this process has not
read carries no text while the same declaration parsed out of the file carries
all of it, and the kind an element reports is read off the node it was built
from, which a stub and a parse spell differently. The path and the place
identify a declaration without either.

The answer is a set of edits and not a write. The client applies them, which
is what makes one rename one undo in the editor, and it means a refused rename
left nothing behind to clean up. A proposed name is checked before anything is
planned, and a module clause or an import is refused in words because
rewriting either moves nothing.
