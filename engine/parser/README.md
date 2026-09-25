# parser

Turns V source into a tree-sitter syntax tree. Callers reach it through
`ParserEngine` in `engine/engine.v`, the seam that keeps a V-native parser
reachable as a swap-in without touching the feature handlers.

| Entry point | What it does |
| --- | --- |
| `Parser.parse_file` | parses a file from disk |
| `Parser.parse_code` | parses a string rather than a path |
| `Parser.parse_code_with_tree` | re-parses against the tree from the previous run |
| `parse_batch_files` | parses a list of files across worker threads |

`ParseResult` is what comes back. The grammar accepts a larger language than the
V spec permits, for simplicity and for robustness in the presence of syntax
errors, which keeps a half-typed buffer parseable.

The node types come from the grammar vendored in `tree_sitter_v/`. `NOTICE`
carries the provenance, and `docs/architecture.md` has the module map.
