# Corpus report: how much of vlib this grammar parses

The engine owes a parse measurement. These are the numbers this grammar produces
on a pinned corpus, taken on 2026-09-25.

Environment: V 0.5.2, commit `1b68924`, the compiler `v` resolves to on PATH
(`/home/specter/v/v`), so the corpus is the vlib shipped with that commit,
`/home/specter/v/vlib`. The harness finds the vlib directory of whatever `v`
is on PATH, which is why the pinned list is relative to it.

| Command | Observed result | Date |
| --- | --- | --- |
| `v -o /tmp/visor-corpus engine/corpus_test.v && /tmp/visor-corpus` | 30 files, 31,406 lines, 379,504 nodes, 34 `ERROR` nodes, 11 `MISSING` nodes, exit 0 | 2026-09-25 |
| `v test engine/` | 4 test files, 10 test functions, `4 passed, 4 total`, exit 0 | 2026-09-25 |

## Threshold against measurement

The plan asks for a corpus that "parses with zero ERROR nodes above a stated
threshold", and leaves the number to the implementation. The threshold stated
here is zero `ERROR` nodes and zero `MISSING` nodes over the pinned list.

Measured: **34 `ERROR` nodes and 11 `MISSING` nodes**, so the threshold is not
met. Grammar work on the constructs below is what closes the gap.
`engine/corpus_test.v` asserts the measured baseline (34 and 11) rather than the
target, so the corpus cannot get worse without failing, and a change that parses
more has to lower the constants and update this table.

## The pinned list

Thirty production files, each one an absolute path under the vlib of the
measured compiler. None of them is a `_test.v` file, because the indexer skips
those.

| # | File (relative to vlib) | Lines | Nodes | ERROR | MISSING |
| --- | --- | --- | --- | --- | --- |
| 1 | `builtin/string.v` | 3246 | 32111 | 3 | 0 |
| 2 | `builtin/array.v` | 1610 | 17706 | 2 | 0 |
| 3 | `builtin/map.v` | 1032 | 12616 | 2 | 0 |
| 4 | `builtin/autostr.v` | 126 | 1084 | 0 | 0 |
| 5 | `os/os.v` | 1272 | 11661 | 0 | 0 |
| 6 | `os/process.v` | 93 | 677 | 0 | 0 |
| 7 | `strings/similarity.v` | 224 | 2522 | 0 | 0 |
| 8 | `strings/builder.c.v` | 482 | 4377 | 4 | 0 |
| 9 | `arrays/arrays.v` | 826 | 8757 | 0 | 8 |
| 10 | `maps/maps.v` | 119 | 1319 | 0 | 0 |
| 11 | `datatypes/stack.v` | 41 | 448 | 0 | 0 |
| 12 | `datatypes/fsm/fsm.v` | 103 | 1055 | 1 | 0 |
| 13 | `datatypes/bloom_filter.v` | 132 | 1569 | 0 | 0 |
| 14 | `datatypes/doubly_linked_list.v` | 364 | 3688 | 2 | 0 |
| 15 | `math/bits/bits.v` | 629 | 7106 | 0 | 0 |
| 16 | `math/big/big.v` | 40 | 527 | 0 | 0 |
| 17 | `time/time.v` | 536 | 5552 | 0 | 0 |
| 18 | `flag/flag.v` | 785 | 8728 | 0 | 0 |
| 19 | `cli/command.v` | 450 | 5651 | 1 | 0 |
| 20 | `encoding/base64/base64.v` | 70 | 1172 | 0 | 0 |
| 21 | `encoding/hex/hex.v` | 99 | 1032 | 0 | 0 |
| 22 | `crypto/sha256/sha256.v` | 251 | 3115 | 0 | 0 |
| 23 | `sync/once.v` | 71 | 555 | 0 | 0 |
| 24 | `sync/cond.v` | 87 | 763 | 0 | 0 |
| 25 | `context/context.v` | 109 | 543 | 0 | 0 |
| 26 | `io/buffered_reader.v` | 242 | 2288 | 0 | 0 |
| 27 | `v/token/token.v` | 339 | 3441 | 0 | 0 |
| 28 | `v/scanner/scanner.v` | 1175 | 14251 | 0 | 1 |
| 29 | `v/parser/parser.v` | 16620 | 222745 | 19 | 2 |
| 30 | `term/term.v` | 233 | 2445 | 0 | 0 |
| | **30 files** | **31406** | **379504** | **34** | **11** |

The absolute paths are the vlib root above joined with each name, for example
`/home/specter/v/vlib/builtin/string.v` and
`/home/specter/v/vlib/v/parser/parser.v`. The list lives in `engine/corpus_test.v`;
adding a file means adding the name there and re-measuring, and the doc and the
list have to move together.

## Where the damage sits

Every `ERROR` node was located and the text under it read, which sorts the 34
into four unsupported constructs. These are the gaps grammar work should spend
its budget on, largest first.

**A boolean expression continued on a new line with a leading `||`** (19 of 34,
all in `v/parser/parser.v`). These are the ones that did not recover:

    v/parser/parser.v:3313    || (!is_name_char(signature[i + 1]) && signature[i + 1] != `.`)
    v/parser/parser.v:5626    || p.eval_comptime_cond_with_target_override(right_or, disable_target_arch)
    v/parser/parser.v:6741    || prev_tok in [.lcbr, .semicolon, .comma, .colon, .lpar, .lsbr, .key_return]

The file contains 77 lines that start with `||`. Most of them recover as part
of the expression above; 19 leave a one or two byte `ERROR` where the operator
should be.

**A cast to a pointer to an array** (4 of 34, `strings/builder.c.v`):

    strings/builder.c.v:141    return unsafe { (&[]u8(b))[n] }
    strings/builder.c.v:269    mut arr := unsafe { &[]u8(b) }
    strings/builder.c.v:292    mut arr := unsafe { &[]u8(b) }

**A `type` alias whose right side is a function type** (4 of 34, three files).
The expression is only partly consumed, so what lands is a one byte `ERROR`:

    builtin/map.v:188               type MapHashFn = fn (voidptr) u64
    builtin/map.v:190               type MapEqFn = fn (voidptr, voidptr) bool
    datatypes/fsm/fsm.v:5           pub type ConditionFn = fn (receiver voidptr, from string, to string) bool
    cli/command.v:5                 type FnCommandCallback = fn (cmd Command) !

**A unary `!` inside an attribute condition** (2 of 34, `builtin/array.v`):

    builtin/array.v:1598    @[if !no_bounds_checking ?; inline]
    builtin/array.v:1605    @[if !no_bounds_checking ?; inline]

Two constructs account for the rest and are not in the table because each
lands inside a larger `ERROR`: a cast to an option, `return ?string(a.clone())`
at `builtin/string.v:340`, and a multi declaration whose right side starts with
a literal, `for h, t := 0, list.len - 1; h <= t;` at
`datatypes/doubly_linked_list.v:241`.

The 11 `MISSING` nodes are concentrated in `arrays/arrays.v` (8), with two in
`v/parser/parser.v`, one in `v/scanner/scanner.v`. A missing node is a token the
grammar inserted to recover rather than a region it gave up on, so those three
files parse into a usable tree with tokens that are not in the source. Nothing
in `engine/` reads that distinction today.

## How to re-measure

    v -o /tmp/visor-corpus engine/corpus_test.v && /tmp/visor-corpus

prints the table above. `v test engine/corpus_test.v` runs the same measurement
as an assertion, which is what `v test .` and CI do; that run prints the table
only when the assertion fails, so the binary form is the one to use for the
numbers.

The counters are exercised first on damaged buffers in the same test file, since
a corpus of clean files proves nothing if the counter never fires:
`@#$%^&*` produces 2 `ERROR` nodes, `if x { }\n}\n` produces 1, and
`fn main() {\n\tx := \n}\n` produces a `MISSING` node rather than an `ERROR`
one. That last buffer is what the vtool module feeds the compiler to get an error
diagnostic, and this grammar recovers from it without an `ERROR` node, so an
`ERROR` count alone is not the same thing as "this file is damaged".

## Why the first count read zero

The first pass counted `Node.kind == 'ERROR'` through `TreeSitterParser` and got
0 on all 30 files. The tree was fine and the name was not. `Node.kind` came from
`NodeType.str()`, and the enum member behind the grammar's `ERROR` node is
`error`, so every unparseable region arrived in lower case and nothing matched
it. Counting `kind == 'error'` gave 34, and counting through the binding
(`type_name == .error`) gave the same 34 on the same files, which is what tied
the two together. `engine.v` now names that node type `ERROR`, the way the
grammar does, and the test asserts the seam and the binding agree on every file
so the two counts cannot drift apart again.

## What is not verified

The corpus is 30 files from three of vlib's directories, chosen for the
constructs they contain. It is not a sample of vlib by line count and no
sampling method was used, so the percentages a reader could compute from it are
not vlib's. Nothing under `vlib/v/gen`, `vlib/v/checker` or `vlib/orm` is in it,
and `vlib/v/checker` has no `.v` files in this V version at all.

No file with a build tag, a `.vsh` script or a generated `.js.v` file was
parsed. Nothing was measured on Windows, macOS or a non-x86_64 target, and the
grammar is exercised against one tree-sitter parser instance reused across
files, not one per file.

Only two things are counted: the nodes whose kind is `ERROR`, and the nodes the
grammar inserted. A file can hold an `ERROR` node and still produce the symbols
a feature needs, and a file with neither can still hold a tree that disagrees
with the compiler. Neither was checked. The parse was not compared against `v`
itself for these files, so nothing here says which parser is right, only what
this grammar produces.

`engine.Node` carries a kind and a span, so a `ParsedFile` cannot tell a caller
that a region failed to parse once the region is gone from the tree, and it
cannot see an inserted token at all. The `MISSING` column is measured against
the binding for that reason, not through the seam.
