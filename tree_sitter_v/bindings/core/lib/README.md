## Subdirectories

* [`src`](./src) - C source code for the Tree-sitter library
* [`include`](./include) - C headers for the Tree-sitter library

Upstream ships Rust, JavaScript and lldb bindings beside this library. This copy
carries none of them. It also carries no `src/query.c`: nothing in this tree
builds a tree-sitter query, and `bindings/bindings.v` declares no `ts_query_*`
function to call one with. Re-vendoring restores it. Visor links the rest whole
and reaches it through the V bindings in `../../bindings.v`.
