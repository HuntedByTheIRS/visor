# Roadmap

## v0.1.0

Everything in the feature list ships in v0.1.0. Splitting the feature set across
releases would ship a server nobody can use yet, and deriving the engine from
v-analyzer is what makes the full set reachable in one release.

- diagnostics over unsaved buffers, pushed and pulled
- hover, completion, signature help
- definition, declaration, type definition, implementation, references
- rename and prepare rename
- document symbols, workspace symbols
- folding ranges, document highlight, selection range, range formatting
- semantic tokens, inlay hints
- code actions, code lens, call hierarchy
- formatting, which delegates to `v fmt`

Acceptance for the release is the criteria in the plan, each with an observed
result in the module's `VERIFICATION.md`.

## Compiler floor

The tree needs V master rather than the latest release. `lsp/` imports `json2`,
and `vlib/json2` arrived eight commits after the 0.5.2 tag (`ee3ef57ffd`,
2026-07-13), so no published release asset carries it. The older `vlib/json` is
not the way out: it is deprecated in favour of `json2`, and master's `v fmt`
rewrites one into the other, so adopting it would mean building on a module V is
deleting. CI therefore builds V master from source, which stays affordable
because V's Makefile bootstraps through the portable snapshot in `vc/v.c` rather
than through V3.

The 0.1.x series ends this arrangement by giving visor its own JSON layer. Once
the server no longer depends on a V module that is missing from the latest
release, the compiler floor drops back to the most recent release that the
tree-sitter dependency also builds on, and the release-cadence job regains its
tag leg. Until that lands, "builds against the latest V tag" is not a criterion
anyone should measure.

## Release cadence

A new V compiler release is the trigger for a matching visor release. Feature
and bugfix releases land in between. A weekly job builds visor against V master,
and its report is the signal that a matching release is due. The tag leg of that
job returns with the JSON layer described under Compiler floor.

## After v0.1.0

Windows and macOS wait for runners, which do not exist yet. The code stays
portable in the meantime, and portability is a review criterion rather than an
assumption. When a runner appears, the work is one platform lane: repeat the
process-boundary proof, repeat the release asset matrix on that OS, and answer
whether the tree-sitter C dependency builds under MSVC.

Inline completion (LSP 3.18) is deferred to v0.2.0. LSP 3.17 is the baseline and
3.18 features are negotiated, never assumed.

Debug adapter support is out of scope. visor is a language server, not a
debugger.

The grammar has a standing budget. Where the parse corpus shows a gap, the
tree-sitter grammar and its generated bindings get extended rather than the
feature being cut.
