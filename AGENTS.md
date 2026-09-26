# Agent guide

Rules for automated contributors. A person writing a pull request wants
`CONTRIBUTING.md` instead; this file is the same rules with the parts agents get
wrong called out.

## Commands

```sh
v -o /tmp/visor .        # build
v run tools/check_warnings.vsh   # warning gate, silent on a clean tree
v run tools/update_ver.vsh 0.0.3 # version bump, carries the copies with it
v fmt -verify .          # format gate, exit 0 or fail
v test .                 # every module's tests, recurses into module dirs
v test vtool/            # one module
npx --yes markdownlint-cli2@0.23.3   # markdown gate
```

`v test .` picks up `_test.v` files in subdirectory modules, so it is the whole
suite. There is no `v test ./...` in V 0.5.2; do not invent one.

The markdown gate reads `.markdownlint-cli2.jsonc`, which holds the globs, the
rules this tree switches off and the reason for each one. CI runs the same
command on the same pinned version.

## Where things live

`main.v` is the entry point. Modules are real subdirectories imported by name:
`vtool/`, `engine/`, `lsp/`, `tree_sitter_v/`. A whole subsystem goes in its own
directory with its own tests, and no file grows past roughly 4 kLOC.

Do not put `subdirs: [...]` in `v.mod`. In V 0.5.2 that declares a single virtual
module over those directories; v-analyzer's build fails on exactly that layout.

## Never

- import `v.ast`, `v.flat`, `v.parser`, `v.checker`, `v.pref` or `v.scanner`.
  The process boundary is the whole design.
- invoke `-vls-mode` or `-line-info`. V is deleting the V1 compatibility
  compiler; a feature that only exists there gets implemented in-process.
- copy vls source. It is GPL-2.0 and visor is MIT. Read it to learn what modern
  editor support looks like, then write your own.
- add a launcher, an updater, a second formatter, or a registry publish step.

CI greps for the first two. Review catches the rest, so do not rely on CI.

## Verify before you claim

A build that compiles is not a finished change. Run the command that covers what
you touched, and report what you ran and what came back. If something is
unverified, say so rather than leaving it implied.

`v run tools/check_warnings.vsh` is the warning gate, and it is the tool to run
on every change. It compiles every module, vets the whole tree, checks the test
files individually and builds the binary, and fails on any line any of those
prints. Do not land a change that leaves it red. The gate plants a type error
and an undocumented function on every run, so a silent run is evidence.

## Commit shape

Small commits, one logical change each, made as you go. A module that compiles,
a test that starts passing, a fix. Do not land a lane's worth of work as one
commit. The bootstrap squash was a one-off so history starts with real work;
after that every commit stays small.

## Prose

The humanizer pass applies to commit messages, docs, comments and error text.
Draft, ask what makes it read as machine written, revise. Watch for significance
inflation, `-ing` tails, three-item lists, bolded inline headers, em dashes,
`not just X, but Y`, and upbeat closing lines. Keep prose short and declarative,
and keep comments about why the code is shaped this way.
