# Agent guide

Rules for automated contributors. A person writing a pull request wants
`CONTRIBUTING.md` instead; this file is the same rules with the parts agents get
wrong called out.

## Commands

    v -o /tmp/visor .        # build
    v fmt -verify .          # format gate, exit 0 or fail
    v test .                 # every lane's tests, recurses into module dirs
    v test vtool/            # one module

`v test .` picks up `_test.v` files in subdirectory modules, so it is the whole
suite. There is no `v test ./...` in V 0.5.2; do not invent one.

## Where things live

`main.v` is the entry point. Modules are real subdirectories imported by name:
`vtool/`, `engine/`, `lsp/`, `diag/`, `features/`. A whole subsystem goes in its
own directory with its own tests, and no file grows past roughly 4 kLOC.

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

A build that compiles is not a finished lane. Each lane ends with its own
command plus a dated row in `docs/verification.md`. Report what you ran and what
came back. If something is unverified, say so rather than leaving it implied.

A lane running beside other lanes writes that row to `<module>/VERIFICATION.md`
instead, and the person integrating the lanes copies it across. Two lanes never
edit the same file.

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
