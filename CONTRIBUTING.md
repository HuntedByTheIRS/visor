# Contributing

## Build and check

    v -o /tmp/visor .
    v fmt -verify .
    v test .

`v fmt` is the only formatter here. Do not add a second one, and do not reformat
code by hand into a shape `v fmt` would undo.

## Layout

`main.v` holds the entry point. Everything else is a module in its own
subdirectory: `vtool/`, `engine/`, `lsp/`, `diag/`, `features/`. Import those by
name.

Do not add a `subdirs` list to `v.mod`. In V 0.5.2 `subdirs` declares one
virtual module spread across the directories it names, which is the layout that
broke v-analyzer's build. A real subdirectory module needs no manifest entry.

Keep a source file under roughly 4 kLOC. Past that, split the module. vls put
216 KB into one file and the shape of that file is what this rule exists to
avoid.

## Rules a change has to keep

`docs/architecture.md` has the full list with the reasoning. The short version:

- no `import v.ast`, `v.flat`, `v.parser`, `v.checker`, `v.pref` or `v.scanner`
- no `-vls-mode` and no `-line-info`
- no vls source, in any form
- no launcher binary, no updater, no publish step

CI greps for the first two on every push.

## Commits

Small commits, one logical change each, made as the work happens. A module that
compiles is a commit. A test that starts passing is a commit. Do not carry a
day's work in the tree and land it as one drop, and do not group unrelated
changes because it is convenient. If explaining why two edits share a commit
takes a paragraph, they are two commits.

## Prose

Everything a person reads gets the humanizer pass before it lands: commit
messages, `docs/**`, README, comments, error messages, pull request text. Write
the draft, ask what makes it read as machine written, then revise. The patterns
this project's prose would pick up on its own:

- significance inflation, where an ordinary change gets called pivotal
- `-ing` tails that restate the sentence (`..., highlighting the importance of`)
- lists of exactly three things
- bolded inline headers in bullet lists
- em dashes
- `not just X, but Y`
- closing lines that sound upbeat and say nothing

Comments explain why the code is the way it is. They never narrate the code.

## Filing issues and reporting problems

Bugs and feature requests go through the GitHub issue tracker; `ISSUES.md` has
the format the reports are read in. Security problems go to `SECURITY.md`
instead, which routes them somewhere private. `CODE_OF_CONDUCT.md` covers how
people treat each other in the tracker and in review.

## Before you open a pull request

Run the four checks above, add a dated row to `docs/verification.md` for what
you verified, and fill in the template. A green build on its own does not close
a lane: the lane's command has to appear in `docs/verification.md` with its
observed result.

Two lanes running at once never edit the same file. A lane working in parallel
stages its rows in `<module>/VERIFICATION.md`, and whoever integrates the lanes
moves them into `docs/verification.md`.
