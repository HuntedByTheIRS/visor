## Subdirectories

* [`src`](./src) - C source code for the Tree-sitter library
* [`include`](./include) - C headers for the Tree-sitter library

Upstream ships Rust, JavaScript and lldb bindings beside this library. This copy
carries none of them. Visor links the C library whole and reaches it through the
V bindings in `../../bindings.v`.
