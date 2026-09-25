# Filing an issue

Bug reports are the most useful thing you can send. A report someone can
reproduce in two minutes gets fixed. One that cannot gets a question mark and
then silence.

## Before you file

Search the open and closed issues. Read `ROADMAP.md` first: if the thing you
want is listed as out of scope for v0.1.0, the issue will be closed and pointed
at the roadmap.

## What every report needs

- the output of `visor --version`
- the output of `v version`
- the editor and client version: VS Code or VSCodium with the visor extension,
  Neovim, coc.nvim, or Vim with vim-lsp
- the smallest V file or project that shows the problem
- what you expected, and what happened instead
- the server log, when the failure is not visible in the editor

## Bug report template

    visor version:   (paste the output of `visor --version`)
    V version:       (paste the output of `v version`)
    editor:          (name and version)
    platform:        (Linux distribution and architecture)

    Steps to reproduce:
    1.
    2.

    Expected:

    Actual:

    Server log:
    (paste or attach)

    Does it still happen with visor.vExecutablePath unset?:

## Feature requests

Say what you are trying to do, not only what you want added. A request shaped
around a workflow gets an answer about design. One shaped around a missing
button gets filed as a preference.

## Security problems

Those do not go here. `SECURITY.md` has the reporting route, and it is private.

## Out of scope for v0.1.0

- debugger and DAP support
- macOS and Windows builds, until runners exist for them
- Marketplace and Open VSX publishing

## Labels

Issues carry GitHub's default labels. Area labels will be worth adding once the
feature modules exist and it is clear which areas people file against.
