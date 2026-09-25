# Lane L3 verification: engine

Rows for `docs/verification.md`. Whoever integrates the lanes moves them across;
two lanes never edit the same file.

Everything below ran from the worktree root, `/home/specter/visor-lane-engine`,
on branch `lane/engine`, against V 0.5.2, commit `1b68924`, which is what
`v version` answers here. The dates are UTC; the machine's own clock was still
on 2026-09-24 in the evening when the runs happened.

| ID | Command | Observed result | Date |
|---|---|---|---|
| L3 | `v -o /tmp/visor-l3 .` | exit 0, no output, binary written | 2026-09-25 |
| L3 | `/tmp/visor-l3 --version` | prints `visor 0.0.1`, exit 0 | 2026-09-25 |
| L3 | `v test engine/` | 4 test files, 10 `test_` functions, `4 passed, 4 total`, exit 0 | 2026-09-25 |
| L3 | `v test .` | `1 failed, 4 passed, 5 total`, exit 1. The one failure is the vendored `tree_sitter_v/bindings/simple_test.v`, finding V-1 below | 2026-09-25 |
| L3 | `v test tree_sitter_v/bindings/` | `1 failed, 1 total`, exit 1, finding V-1 below | 2026-09-25 |
| L3 | `v fmt -verify .` | exit 0, no file reported | 2026-09-25 |
| L3 | `grep -rnE 'import v\.(ast\|flat\|parser\|checker\|pref\|scanner)' --include='*.v' .` | no match, exit 1 | 2026-09-25 |
| L3 | `grep -rn 'vls-mode\|-line-info' --include='*.v' .` | no match, exit 1 | 2026-09-25 |
| L3 | `find . -name '*.v' -not -path './.git/*' -print0 \| xargs -0 wc -l \| awk '$2 != "total" && $1 > 4000'` | no match, 179 `.v` files, longest is `engine/psi/TypeInferer.v` at 1007 lines | 2026-09-25 |
| L3 | `v -o /tmp/visor-corpus engine/corpus_test.v && /tmp/visor-corpus` | 30 files, 31,406 lines, 379,504 nodes, 34 `ERROR` nodes, 11 `MISSING` nodes, exit 0. See `CORPUS.md` | 2026-09-25 |

The two test commands that fail are the same vendored file. `engine/` is green;
`v test .` is not, and CI's test step will fail on it until finding V-1 is
resolved. That is a finding to hand over, not something this lane hides.

## What was wrong

Five defects. The last two were only visible once the tests and the measurement
ran for real, which is the argument for running them rather than reading them.

`engine/psi/StubIndexSink.v` lost every occurrence it was given. V 0.5.2 drops
`m[k1][k2] << v` when `k1` is not in the map yet: the append lands in a
temporary map and the outer map never learns about it. Every sink this
compiler built came out empty, so every index built from a sink held nothing,
which is why `PsiFile.index_sink` answering `none` was only the visible end of
it. The append is written out now, and finding V-3 has the program that shows
what the compiler does with each spelling.

`engine/engine_test.v` built a `PsiFile` by hand and then asked it for a sink.
A sink only exists once something indexed the file, so the test panicked with
`the file has no stub sink`. It now runs an `IndexingRoot` over the fixture
directory and lets the manager publish the sinks, which is the order the server
uses, and then reads the sink back through `PsiFile.index_sink`. The assertions
are unchanged.

The same test looked the method up under `.methods` with the key `increment`.
`.methods` is keyed by the receiver's qualified name, which is what
`psi.own_methods_list` passes when it looks a method up, so the key could never
match and the test would have failed on `elements.len == 1` even with a filled
index. The key is `sample.Counter` now, the receiver in the fixture, and the
sink dump that shows it is in finding V-3.

`engine/engine.v` named an unparseable region `error`. `Node.kind` came from
`NodeType.str()`, and the enum member behind the grammar's `ERROR` node is
`error`, so a caller comparing against the grammar's name saw nothing. The
corpus measurement is what surfaced it, because the whole pinned corpus counted
zero `ERROR` nodes through the seam while the binding behind it counted 34.
Finding V-4 has the numbers and `CORPUS.md` has the story.

`tree_sitter_v/bindings/generate_types.vsh` was the one file `v fmt -verify .`
reported, so the format gate could not pass. It is formatted now, and the
formatter's own `json` to `json2` migration came with that, which makes the
vendored script differ from upstream by two lines. `v -check` on the migrated
script exits 0; it was not run, because it writes `node_types.v` and its output
order comes from map iteration.

## Finding V-1: the vendored bindings test cannot build on this V

`v test tree_sitter_v/bindings/` fails, and it failed before this lane started,
against any file on either compiler this V ships. The default compiler generates
C that `cc` rejects; the compiler V falls back to rejects the same line as a
type error.

    $ v test tree_sitter_v/bindings/
    tree_sitter_v/bindings/simple_test.v:5:17: error: cannot use `&C.TSLanguage` as `&bindings.TSLanguage` in argument 1 to `tree_sitter_v.bindings.Parser[tree_sitter_v.bindings.NodeType].set_language`
    tree_sitter_v/bindings/bindings.v:24:41: error: cannot use `&bindings.TSLanguage` as `&C.TSLanguage` in argument 2 to `C.ts_parser_set_language`
    Compiler output from the default V compiler:
    C compilation error (from cc):
    src.c: In function 'bindings__test_simple':
    src.c:6327:73: error: array type has incomplete element type 'TSLanguage'
    src.c:6327:77: error: invalid use of incomplete typedef 'TSLanguage'
    Summary for all V _test.v files: 1 failed, 1 total. Elapsed time: 41657 ms, on 1 job. Comptime: 41568 ms. Runtime: 0 ms.

The generated C for the failing line, from `v -o /tmp/btest.c
tree_sitter_v/bindings/simple_test.v`:

    bindings__Parser_bindings__NodeType__set_language(p, (TSLanguage[]){*bindings__language});

`TSLanguage` is opaque by design (`typedef struct TSLanguage TSLanguage;` in
tree-sitter's api.h), so `(TSLanguage[]){...}` cannot compile: an array of an
incomplete type. The compound literal is there because the code generator
decided the argument is a value of type `TSLanguage` and took its address. The
same call written in `engine/parser/parser.v`, which is a different module from
the const, comes out as the pointer it is:

    bindings__Parser_bindings__NodeType__set_language(bp, bindings__language);

Six candidate fixes were measured, and five of them do not work:

| Change | Result |
|---|---|
| `pub const language &TSLanguage = C.tree_sitter_v()` | same C error, plus `'language' undeclared` |
| `pub const language = unsafe { &TSLanguage(C.tree_sitter_v()) }` (upstream form) | same C error, plus a type error on `bindings.v:23` |
| `pub const language &C.TSLanguage = C.tree_sitter_v()` | same C error, plus `'language' undeclared` |
| `set_language(language voidptr)` in `bindings.v` | `(void*[]){*...}`, new C error `declaration of type name as array of voids` |
| `p.set_language(bindings.language)` in the test (self-qualified) | emitted as literal text, `'bindings' undeclared` |
| `p.set_language(C.tree_sitter_v())` in the test | **passes**: `1 passed, 1 total`, and the generated call is `set_language(p, tree_sitter_v())` |

So the one line that fixes it sits in the test file, and the hard rules say a
test is never edited to make it pass, including a vendored one. It was not
applied. That is the whole of the finding, and the smallest next action.

Smallest next action, for whoever owns the grammar and bindings budget
(decision 9): either apply that one line to
`tree_sitter_v/bindings/simple_test.v` and record it as a vendored deviation,
or write the call through a wrapper in `bindings.c.v` that does not take an
opaque C pointer as a parameter. Both need the same re-measurement, which is
`v test tree_sitter_v/bindings/` and then `v test .`.

## Finding V-2: V 0.5.2 miscompiles a fixed array of maps in a struct literal

`engine/psi/StubIndex.v` cannot write its fixed arrays of maps the way upstream
does, because the C that comes out is not C. Reproduction, 36 lines, measured
with `v run repro4_fixed.v`, exit 1:

```v
module main

const n = 5

interface Elem {
	text() string
}

struct Impl {
	s string
}

fn (i Impl) text() string {
	return i.s
}

struct Holder {
mut:
	by_name map[string][]int
	elems   [n]map[string][]Elem
	types   [n]map[string][]Elem
}

fn new_holder() &Holder {
	mut idx := &Holder{
		by_name: map[string][]int{}
		elems:   unsafe { [n]map[string][]Elem{} }
		types:   unsafe { [n]map[string][]Elem{} }
	}
	return idx
}

fn main() {
	h := new_holder()
	println(h.elems.len)
}
```

Observed, with the long line kept to its first 120 characters:

    $ v run repro4_fixed.v
    C compiler output from the default V compiler:
    src.c: In function 'new_holder':
    src.c:5321:217: error: expected expression before '{' token
    src.c:5321:199: error: too few arguments to function 'memcpy'; expected 3, have 2
    src.c:5321:792: error: expected expression before '{' token
    src.c:5321:774: error: too few arguments to function 'memcpy'; expected 3, have 2
    V compilation failed (c_compilation_error); retrying with `/home/specter/.cache/v/v1-fallback/0.5.2/v`.
    exit=1

The generated statement, one line, abbreviated where it repeats the same seven
argument `new_map` call:

    main__Holder* idx = (main__Holder*)({main__Holder _t1 = (main__Holder){.by_name = new_map(...)};
    memcpy(_t1.elems, {new_map(...), new_map(...), new_map(...), new_map(...), new_map(...)}, sizeof(_t1.elems));
    memcpy(_t1.types, {...}, sizeof(_t1.types)); memdup(&_t1, sizeof(main__Holder));});

The `unsafe` block is what selects that path. Dropping it compiles, at the cost
of a warning on each field, which is why the engine fills the arrays with a loop
instead:

    $ v run repro4_nounsafe.v
    repro4_nounsafe.v:30:12: warning: fixed arrays of interfaces need to be initialized right away (unless inside `unsafe`)
    repro4_nounsafe.v:31:12: warning: fixed arrays of interfaces need to be initialized right away (unless inside `unsafe`)
    5
    exit=0

The earlier copy of this reproduction at
`/home/specter/.hermes/cache/scratch/vcodegen/repro4.v` is 39 lines and
reproduces the same defect, but its struct is called `S`, which draws an
unrelated second error from the fallback compiler (`single letter capital names
are reserved for generic template types`) that hides the one that matters. The
copy above renames it, which is the only change.

## Finding V-3: V 0.5.2 drops a nested map append

Measured with `v run nestedmap2.v`:

```v
module main

fn main() {
	mut m := map[int]map[string][]int{}

	// 1. nested set on a missing outer key
	m[3]['a'] = [1]
	println('1 nested set: ${m}')

	// 2. nested append on a missing outer key
	m[4]['b'] << 5
	println('2 nested append: ${m}')

	// 3. clone, fill, write back
	mut by_name := (m[7] or { map[string][]int{} }).clone()
	mut ids := by_name['c'] or { []int{} }
	ids << 9
	by_name['c'] = ids
	m[7] = by_name
	println('3 clone/fill/write: ${m}')

	// 4. clone of an existing entry, then append through it
	mut by_name2 := (m[3] or { map[string][]int{} }).clone()
	mut ids2 := by_name2['a'] or { []int{} }
	ids2 << 2
	by_name2['a'] = ids2
	m[3] = by_name2
	println('4 append to existing: ${m}')
}
```

Observed:

    1 nested set: {3: {'a': [1]}}
    2 nested append: {3: {'a': [1]}}
    3 clone/fill/write: {3: {'a': [1]}, 7: {'c': [9]}}
    4 append to existing: {3: {'a': [1, 2]}, 7: {'c': [9]}}

Case 2 is the one the sink hit: the append is silently discarded. Case 1 shows a
nested *set* on a missing outer key does work, and case 4 shows an append to an
inner entry that is already there works too, which is the shape
`StubIndexSink.occurrence` is written in now: read the ids out, append, set them
back. The sink dump that proves the sink records anything, from the fixture in
`engine/testdata/counter.v`:

    sink key 0:  name="sample.main" ids=[21]
    sink key 1:  name="sample.Counter" ids=[8]
    sink key 3:  name="sample.Counter" ids=[2]
    sink key 10: name="increment:0:true" ids=[8]
    sink key 11: name="value" ids=[5]
    sink key 14: name="sample" ids=[1]
    get_elements_by_name(methods, "sample.Counter") -> 1 ['increment']

Key 1 is `.methods`, keyed by the receiver, which is what the corrected test
lookup uses.

## Finding V-4: the grammar's ERROR node arrived under another name

Counting `Node.kind == 'ERROR'` through `TreeSitterParser` reported zero damage
on every file of the corpus. Counting through the binding reported 34. The tree
was the same, node for node (379,504 both ways), and the name was not:
`NodeType.error` stringifies to `error`, so the kind a caller saw was lower
case. `engine.v` maps that one node type back to the grammar's spelling and
`engine/corpus_test.v` asserts the seam and the binding agree on the count for
every file. The measurement itself, and what the 34 turned out to be, is in
`CORPUS.md`.

This also means the claim "the corpus parses cleanly" was never true, and that
the seam cannot express the weaker claim either: `Node` has no way to say a
token was inserted. The 11 inserted tokens in the corpus are counted against the
binding for that reason.

## Deviations from upstream and from other lanes

`tree_sitter_v/` is a vendored snapshot and three of its files differ from what
was vendored. `bindings.v` and `bindings.c.v` changed in the port fix that
predates this lane, which is also why `bindings.v` no longer declares the
language const in upstream's form. `generate_types.vsh` changed here, by the
formatter. `NOTICE` and `LICENSES/` hold the provenance. `CORPUS.md` and this
file are the engine lane's, and `docs/verification.md` is not edited here.

## What is not verified

`v test .` is not green, and the single failing file is vendored and is not this
lane's to change. CI runs the same command, so the CI test step fails until
finding V-1 is resolved. No CI run was observed from this worktree: the runner
belongs to the push pipeline and this lane does not push. The L1 row for the
Gitea run is still the only evidence that the workflow fires.

The corpus is a measurement, not a proof, and `CORPUS.md` has its own list of
what it does not cover. The short version: 30 files, chosen by hand, no sampling
method, no comparison against the compiler's own parser, and a gap of 34 `ERROR`
nodes and 11 inserted tokens against a stated threshold of zero.

The engine port is much larger than its tests. Four test files cover the tree
through the seam, a PSI lookup, the index test helpers and the corpus; the
type inferer, the reference resolver, the search provider, the serializers and
the logger have no test that runs them, only compilation. Nothing in this lane
exercised them.

The `index_file` path was exercised only through `IndexingRoot.index()`, which
walks one small directory. `ensure_indexed`, `mark_as_dirty`, `add_file`, the
rename and remove paths, the on-disk index format and the deserializer were not
run at all. A sink read back from a saved index is therefore unverified.

Nothing was measured on a platform other than this Linux x86_64 machine, and the
vendored bindings, the grammar and the V codegen findings are all specific to
V 0.5.2 build `1b68924`. Whether the weekly drift job sees the same failures on
a newer V is exactly what it is for, and it has not been observed here.
