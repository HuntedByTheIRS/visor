# L4 verification record

Protocol core: framing, routing, capability negotiation, text sync, document
store, cancellation, progress, workspace folders, shutdown.

Environment: V 0.5.2 (`1b68924`) on CachyOS, x86_64. Commands run from the
worktree root, `/home/specter/visor-lane-lsp`, on branch `lane/lsp`.

| ID | Command | Observed result | Date |
|---|---|---|---|
| L4 | `v test lsp/` | 10 test files, 111 `test_` functions, summary `10 passed, 10 total`, exit 0 | 2026-09-24 |
| L4 | `v -o /tmp/visor .` | exit 0, no output | 2026-09-24 |
| L4 | `v run tools/lsp_smoke.vsh --bin /tmp/visor --fixture testdata/smoke` | 12 checks, 0 failed, prints `smoke: ok`, exit 0 | 2026-09-24 |
| L4 | `sed -i 's/"change": 2/"change": 1/' testdata/smoke/capabilities.golden.json` then the smoke run | `FAIL initialize response matches the committed golden`, run ends with `1 failed` and exit 1 | 2026-09-24 |
| L4 | `v fmt -verify .` | exit 0, no file reported | 2026-09-24 |
| L4 | `/tmp/visor --version` | prints `visor 0.0.1`, exit 0 | 2026-09-24 |
| L4 | `/tmp/visor --help` | prints the usage text, exit 0 | 2026-09-24 |
| L4 | `/tmp/visor --bogus` | prints the unknown-argument line, exit 2 | 2026-09-24 |
| L4 | `grep -rnE 'import v\.(ast\|flat\|parser\|checker\|pref\|scanner)' --include='*.v' lsp/ tools/ main.v` | no match, exit 1 | 2026-09-24 |
| L4 | `grep -rn 'vls-mode\|-line-info' --include='*.v' lsp/ tools/ main.v` | no match, exit 1 | 2026-09-24 |
| L4 | `grep -rn 'import vtool\|import engine' lsp/` | no match, exit 1 | 2026-09-24 |

## The smoke invocation

The plan writes the run as `v run tools/lsp_smoke.vsh --bin /tmp/visor --fixture
testdata/smoke`. That is the command above and it works as written: V 0.5.2 keeps
`--bin` and `--fixture` in `os.args`, so no `--` separator is needed and the
script reads them with or without the `=` form (`--bin=/tmp/visor`).

The run covers the four checks the plan asks for, plus two more:

- initialize answers, and the response matches the committed golden
- a client that sends `initialized` and then `didOpen` gets no reply for either,
  because they are notifications
- `textDocument/hover`, which this build registers as a stub, answers
  `MethodNotFound` with code -32601
- a request and a `$/cancelRequest` for its id are written in one call, so the
  server reads them as one batch, and nothing comes back for that id
- the next request is answered, which shows the silence was the cancellation and
  not a dead server
- `shutdown` answers with a null result, `exit` ends the process with code 0,
  and a second process that gets `exit` with no `shutdown` ends with code 1

The child's stdin stays open for the whole run. That matters: an earlier build
read stdin through libc, and `fread` on a pipe keeps reading until it has the
whole requested count or the stream ends, so the first check timed out. The loop
now reads file descriptor 0 with one `read` syscall at a time. Only the POSIX
read is wired, so the module does not build for Windows yet.

## What these rows do not cover

`didOpen` acceptance is visible only as frame order, because no handler in this
lane reads the document store back out. The store itself is covered by
`lsp/documents_test.v`, including ranged edits and version numbers. The first
lane that answers a request from an open buffer will make the smoke run able to
assert the buffer's contents, and that check belongs there.

The 3.18 gate is exercised by `lsp/capabilities_test.v` against a client that
claims `workspace.textDocumentContent`. No real 3.18 client was available to run
against the binary.
