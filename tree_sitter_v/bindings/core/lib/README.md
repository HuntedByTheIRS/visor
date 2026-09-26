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

Re-vendoring brings both back. Visor links what is left whole and reaches it
through the V bindings in `../../bindings.v`.
