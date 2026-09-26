# Contributing

## Build and check

```sh
v -o /tmp/visor .                    # build
v fmt -verify .                      # format gate
v test .                             # every module's tests
v test vtool/                        # one module
npx --yes markdownlint-cli2@0.23.3   # markdown gate, config in .markdownlint-cli2.jsonc
```

`v test .` recurses into the module directories, so it is the whole suite. The
markdown gate reads `.markdownlint-cli2.jsonc`, which carries the globs, the
ignored trees and the rules this project switches off with a reason for each.

`v fmt` is the only formatter here. Do not add a second one, and do not reformat
code by hand into a shape `v fmt` would undo.

## The smoke run

`tools/lsp_smoke.vsh` starts a real visor process and speaks to it over stdio,
which is the only place framing, the handshake, cancellation and the exit codes
become visible. It carries its own framer rather than importing `lsp`, because a
harness that shares framing code with the thing it tests cannot see a framing
bug.

```sh
v -o /tmp/visor .
v run tools/lsp_smoke.vsh --bin /tmp/visor --fixture testdata/smoke
```

It prints a line per check and exits non-zero when one fails. The fixture is
described in `testdata/smoke/README.md`: change `client-capabilities.json` or
`capabilities.golden.json` without the other and the comparison fails, and
`--update-golden` rewrites the golden when a change to the response was meant.

## The editor run

`tools/editor_test.vsh` runs the Neovim client in `plugins/nvim` against a real
server, in a headless editor, and reports one verdict for every editor it is
handed.

```sh
v -o /tmp/visor .
v run tools/editor_test.vsh --bin /tmp/visor
v run tools/editor_test.vsh --bin /tmp/visor --nvim /opt/nvim-0.11.7/bin/nvim
```

The floor the client states in `plugins/nvim/README.md` (0.11) is checked here
rather than trusted, so an older editor fails with that sentence instead of a
Lua error about an API that is not there. The per-script totals are added up
because the runner answers 0 or 1, which says a run failed without saying how
much of the suite ran, and a run that prints no checks at all fails.

CI pins two editors, 0.11.7 and 0.12.5. The token highlighter is started by a
different call either side of 0.12, and both branches of that check get a run.

## Installing into an editor

`tools/install_lsp.vsh` is what a user runs: it builds the server, copies the
client into a profile under a name of its own, and leaves a command on `PATH`
that starts the editor with that profile, so the configuration someone already
has keeps its own.

```sh
v run tools/install_lsp.vsh nvim          # or vim, or both
v run tools/install_lsp.vsh all -n        # print the plan, write nothing
v run tools/install_lsp.vsh vim --root /tmp/try --bin /tmp/visor
```

`--root` installs under another directory instead of `$HOME`, which is how a
throwaway profile is made and how this runs in CI without touching a runner's
home. `--name` renames the profile: it is the `NVIM_APPNAME` for Neovim and the
`vimrc` for Vim, and it is the command that gets installed.

A `--root` run is self-contained, so it writes the profile under the root even
when `XDG_CONFIG_HOME` is set and the editor would read elsewhere. The run says
so, and names the variable to start the profile with.

The Vim profile carries its own copy of vim-lsp, cloned at install time, because
Vim ships no language client. `--vim-lsp` points at a checkout instead of
cloning one.

Vim reads the generated `vimrc` *instead of* the one the user has, with `-u`, so
nothing in a user's own Vim setup has to be edited for this to work.

The one thing to know when testing a profile by hand: an install is only files
until the editor loads them, and the client only starts on events a real session
produces. In a batch editor, `User lsp_setup` has to be fired by hand (Vim
reaches it from a `VimEnter` autocmd that batch mode skips), and a buffer
rewritten by a script has had no text change, so the client asks for its
highlighting tokens on the next one.

## The version

`VERSION` holds the version and the binary embeds the file at build time, so it
is the source of truth. Other files spell the same string out: the issue
templates ask a reporter for the version they ran, and the smoke golden records
the `serverInfo` block the server sends back. `tools/update_ver.vsh` carries a
bump to all of them.

```sh
v run tools/update_ver.vsh <new-version>     # write
v run tools/update_ver.vsh <new-version> -n  # print the plan, write nothing
```

A copy is found by exact match on the previous version, with a boundary rule:
the match cannot begin or end inside a number, so `1.2.3` is not found in
`1.2.34`. Numbers that mean something else stay where they are, `0.5.2` for the
V release this tree needs and `v0.1.0` for the release `ROADMAP.md` plans. The
tool also sets the `version` in `v.mod`, which declares a version of its own and
had drifted behind `VERSION`.

A bump is a release action. It lands in its own commit, at the point the tree is
about to be tagged, rather than riding along with a feature.

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
instead, which routes them somewhere private. Questions and unshaped ideas go to
the discussions, where `DISCUSSIONS.md` sets the rules. `CODE_OF_CONDUCT.md`
covers how people treat each other in all of those places.

## Before you open a pull request

Run the checks above and fill in the template. A green build is not evidence on
its own: the pull request says which commands ran and what they printed.
