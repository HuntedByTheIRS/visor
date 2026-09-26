# Roadmap

The server is pre-release: `--version` prints what `VERSION` holds, and this
file is what comes next.

| Release | State | Carries |
| --- | --- | --- |
| 0.0.x | in the tree | the protocol core: `initialize`, `shutdown`, `exit`, text sync, cancellation, progress |
| v0.1.0 | in progress | every feature in the README table, on Linux |
| 0.1.x | planned | visor's own JSON layer, which lowers the compiler floor |
| v0.2.0 | planned | inline completion, LSP 3.18 |

## v0.1.0

Everything in the feature list ships in v0.1.0. Splitting the feature set across
releases would ship a server nobody can use yet, and deriving the engine from
v-analyzer is what makes the full set reachable in one release. The list itself
is the table in `README.md`.

Acceptance for the release is a row-by-row pass over the feature table, each row
shown by a command and the result it printed.

## Compiler floor

The tree needs V master rather than the latest release. `lsp/` imports `json2`,
and `vlib/json2` arrived eight commits after the 0.5.2 tag (`ee3ef57ffd`,
2026-07-13), so no published release asset carries it.

```text
  0.5.2 tag
      |
      |  8 commits, 2026-07-13
      v
  vlib/json2 lands at ee3ef57ffd
      |
      |  no published V release carries it
      v
  CI builds V master from source
```

The older `vlib/json` is not the way out: it is deprecated in favour of `json2`,
and master's `v fmt` rewrites one into the other, so adopting it would mean
building on a module V is deleting. CI therefore builds V master from source,
which stays affordable because V's Makefile bootstraps through the portable
snapshot in `vc/v.c` rather than through V3.

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
