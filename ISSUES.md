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

## The form

GitHub offers a bug form and a feature request form when you open an issue here.
The bug form asks for the fields listed above, so you do not have to assemble
them by hand. If a field does not apply, say so rather than leaving it blank.
Blank issues are turned off, which is why there is no empty text box waiting for
you.

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
