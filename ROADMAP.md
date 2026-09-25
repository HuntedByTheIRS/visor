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
result in `docs/verification.md`.

## Release cadence

A new V compiler release is the trigger for a matching visor release. Feature
and bugfix releases land in between. A weekly job builds visor against V master
and against the latest V tag, and its report is the signal that a matching
release is due.

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
