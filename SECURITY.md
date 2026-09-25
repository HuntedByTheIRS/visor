# Security policy

visor is pre-release. It builds and runs its command line, and it answers no
language server requests yet, so the surface below is the one it is being built
to have rather than one you can reach today.

## Supported versions

There is no release yet. Security fixes land on `main` and ship in the next
tagged release. Once v0.1.0 exists this table will name the versions that get
fixes.

| Version | Supported |
| ------- | --------- |
| none yet | no |

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: open the repository's Security tab
and pick "Report a vulnerability". The report stays private until there is a
fix.

If you cannot use that form, mail the maintainer at
`huntedbyth3irs@gmail.com`.

Do not open a public issue for a security problem.

## What to expect

- an acknowledgement within a few days
- an assessment: whether it is exploitable, and what it affects
- a fix on `main`, plus a release when a release exists
- credit in the release notes, unless you would rather stay anonymous

## What counts

visor runs the V compiler as a subprocess, reads what that process prints, and
reads the files in the workspace you opened. Anything that lets a workspace, a
file being edited, or a compiler message make visor run a command you did not
ask for is in scope.

Worth reporting, once the features exist:

- a crafted buffer or file that makes visor execute something unexpected
- a path outside the opened workspace being read or written
- a diagnostic, hover or completion result that escapes the buffer it came from

## What is not ours

- vulnerabilities in the V compiler: report those to
  [vlang/v](https://github.com/vlang/v/security)
- vulnerabilities in your editor or its LSP client: report those to the editor
- `VISOR_V_COMMAND` points visor at a binary it will run. Point it at a V
  compiler you trust; visor cannot make that choice for you.
