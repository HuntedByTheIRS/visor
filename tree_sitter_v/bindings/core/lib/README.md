## Subdirectories

* [`src`](./src) - C source code for the Tree-sitter library
* [`include`](./include) - C headers for the Tree-sitter library

Upstream ships Rust, JavaScript and lldb bindings beside this library, and this
copy carries none of them. Two more parts of the C library are not here:

* `src/query.c`, the S-expression query engine. Nothing in this tree builds a
  query, and `bindings/bindings.v` declares no `ts_query_*` function to call one
  with.
* the Wasmtime backend of `src/wasm_store.c`, with `src/wasm/`. It sits behind
  `TREE_SITTER_FEATURE_WASM`, which this build never defines, and the V grammar
  is native C. The file keeps the stand-ins upstream compiles in its place.

Re-vendoring brings both back, and it undoes the split described below.

## The split of `src`

Five files here had grown past 700 lines, so each is cut where one job ends and
the next begins, and the pieces are named for their jobs: `parser.c` with its
seven `parser_*` companions, `subtree.c` with `subtree_*`, `stack.c` with
`stack_*`, `node.c` with `node_*`, `tree_cursor.c` with `cursor_*`. That is 21
files, 150 to 460 lines each. The code in them is upstream's, moved rather than
rewritten.

`src/lib.c` includes them in dependency order and is the manifest for the
library: what it does not include is not compiled. A new file has to be added
there, and its static helpers have to be defined no later than the file that
calls them.

Visor reaches the library through the V bindings in `../../bindings.v`.
