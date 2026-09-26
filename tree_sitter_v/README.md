# tree-sitter-v

V language grammar for [tree-sitter](https://github.com/tree-sitter/tree-sitter)

This grammar is heavily derived from the following language grammars:

- [tree-sitter-go](https://github.com/tree-sitter/tree-sitter-go)
- [tree-sitter-ruby](https://github.com/tree-sitter/tree-sitter-ruby/)
- [tree-sitter-c](https://github.com/tree-sitter/tree-sitter-c/)

## What this copy carries

This is a trimmed copy of [tree-sitter-v](https://github.com/vlang/v-analyzer) as
v-analyzer shipped it.

Kept for the build:

* `src/` - the generated C parser and the headers it needs
* `bindings/core/lib/` - the tree-sitter C library
* `bindings/` - the V bindings, and the generator that turns node type data
  into the `NodeType` enum

Kept for readers:

* `test/corpus/` - the grammar's parse fixtures

Dropped, because visor is a C and V tree: the Rust, JavaScript and lldb
bindings, the npm and Nix packaging, and the editor and pkg-config files that
served those bindings.

## Limitations

1. It does not support all deprecated/outdated syntaxes to avoid any ambiguities and to enforce the
   one-way philosophy as much as possible.
2. Assembly/SQL code in ASM/SQL block nodes are loosely checked and parsed immediately regardless of
   the content.

## Authors

This project initially started by
[nedpals](https://github.com/nedpals)
and after that, till July 2023, it was heavily modified by the
[VOSCA](https://github.com/vlang-association).

The project is now developed by *all interested contributors*,
just like [V itself](https://github.com/vlang/v).

## License

This project is under the **MIT License**. See the
[LICENSE](https://github.com/vlang/v-analyzer/blob/main/LICENSE)
file for the full license text.
