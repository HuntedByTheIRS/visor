# Verification record

Every lane adds a row here before it closes. The command has to have been run and
the result column holds what came back, not what should have come back.

Unless a row says otherwise, the environment is V 0.5.2 (`1b68924`) on CachyOS,
x86_64.

## Bootstrap (L1)

| ID | Command | Observed result | Date |
|---|---|---|---|
| L1 | `v -o /tmp/visor .` | exit 0, no output | 2026-09-25 |
| L1 | `/tmp/visor --version` | prints `visor 0.0.1`, exit 0 | 2026-09-25 |
| L1 | `/tmp/visor --bogus` | prints the unknown-argument line, exit 2 | 2026-09-25 |
| L1 | `v fmt -verify .` | exit 0, no file reported | 2026-09-25 |
| L1 | `v test .` | exit 0, 0 tests, because no test file exists yet | 2026-09-25 |
| AC1 | `grep -rnE 'import v\.(ast\|flat\|parser\|checker\|pref\|scanner)' --include='*.v' .` | no match, exit 1 | 2026-09-25 |
| AC4 | `grep -rn 'vls-mode\|-line-info' --include='*.v' .` | no match, exit 1 | 2026-09-25 |

## The Gitea Actions run (L1)

| ID | Command | Observed result | Date |
|---|---|---|---|
| L1 | push `14717dc` to `main`, workflow `ci.yml`, runner `main` (label `ubuntu-latest`) | job `build-and-test` succeeded. V 0.5.2 `7647ce1` installed from the release asset; `v -o /tmp/visor .` exit 0; `/tmp/visor --version` printed `visor 0.0.1`; `v fmt -verify .` exit 0; `v test .` exit 0 with 0 tests; both grep gates matched nothing | 2026-09-25 |

Two earlier runs failed, and the workflow is shaped the way it is because of them.

| Run | Failure | Cause |
|---|---|---|
| 30 | job exit 127 before any build step | `actions/checkout` is a JavaScript action and the `ubuntu:24.04` image carries no `node` |
| 31 | `make` killed inside the V source build | V's own guard fired: `v3 compiler memory usage reached 9994 MiB RSS during compilation (limit: 9984 MiB)` in the `./v1 -no-parallel -o v2 -gc none cmd/v` step |

CI runs the 0.5.2 release asset (`7647ce1`). The local rows above are on the
master checkout `1b68924`, which is 1700 commits past the tag. Both report
0.5.2 and they are not the same compiler commit.

## The remote move (2026-09-25)

The canonical remote became `https://github.com/HuntedByTheIRS/visor`. The old
Gitea remote is kept as `spectoria` and still receives pushes.

The pipeline had only ever existed under `.gitea/workflows/`, so the new remote
started with no gate at all. It now lives at `.github/workflows/ci.yml`, which
GitHub Actions reads natively and the Gitea instance falls back to when
`.gitea/workflows/` is absent. Two edits make it host neutral: `sudo` only when
the job is not already root, and `actions/checkout` by name instead of by full
URL.

| ID | Host | Command | Observed result | Date |
|---|---|---|---|---|
| L1 | GitHub Actions | push `9bc4da1` to `main`, run 36087375425 | `build-and-test` concluded success, all eight steps green | 2026-09-25 |
| L1 | Gitea Actions | push `9bc4da1` to `main`, run 33 | `build-and-test` concluded success, all eight steps green | 2026-09-25 |

The Gitea run also answers the open question: this instance does resolve
`actions/checkout@v4` against its default actions URL. The full-URL form is no
longer needed.

Two plan statements are now out of date and belong to the person, not to this
document: the plan's G5 calls for Gitea CI/CD, and AC10 and AC11 name Gitea for
the release assets and the drift report. `L10` has not started, so nothing has
been built on the old assumption yet.

## Lane L2: vtool (2026-09-24)

Copied from `vtool/VERIFICATION.md` by the integrator. The lane ran in
`/home/specter/visor-lane-vtool` on branch `lane/vtool`, ending at `df00923`.

| lane | date | command | observed |
| --- | --- | --- | --- |
| L2 | 2026-09-24 | `v test vtool/` | 7 test files, 56 test functions, all passing. Per file: discovery 8, exec 8, check 15, format 6, probe 6, outline 5, version 8. |
| L2 | 2026-09-24 | `v -o /tmp/visor-l2 .` | exit 0, binary written. `/tmp/visor-l2 --version` prints `visor 0.0.1`. |
| L2 | 2026-09-24 | `v fmt -verify .` | exit 0, no file reported as unformatted. |
| L2 | 2026-09-24 | `v test .` | same 56 tests, passing. This is what CI runs. |
| L2 | 2026-09-24 | `v test vtool/` ten times in a row | 10 passing summaries, 0 failures. The count matters because this suite had a one in four failure rate before the fix noted below. |
| L2 | 2026-09-24 | a scratch program that imports `vtool`, calls `find()` then `probe()` | 289 ms for the five probe invocations, `v_version` answered `V 0.5.2 1b68924`. |

The SIGPIPE fix behind the fourth row: when a child exits without reading its
stdin, the next write raises SIGPIPE and the default action kills the writer.
The lane's `exec_test.v` carries the regression, and `exec.v` masks the signal
before writing.

### Re-run after the merge (integration branch, 2026-09-25)

Run by the integrator in a separate worktree rather than reused from the lane's
report.

| ID | Command | Observed result | Date |
|---|---|---|---|
| L2 | `git merge --no-ff lane/vtool` into `integration` | merged clean, 16 files added | 2026-09-25 |
| L2 | `v -o /tmp/visor-int .` | exit 0 | 2026-09-25 |
| L2 | `/tmp/visor-int --version` | prints `visor 0.0.1` | 2026-09-25 |
| L2 | `v fmt -verify .` | exit 0 | 2026-09-25 |
| L2 | `v test .` | 7 files, 56 tests, all passing, exit 0 | 2026-09-25 |
| AC1 | compiler-internals grep after the merge | no match | 2026-09-25 |
| AC4 | vls-mode grep after the merge | no match | 2026-09-25 |
| L2 | file-length rule over the merged tree | no `.v` file over 4 kLOC, 1373 lines total | 2026-09-25 |
| L2 | a buffer whose third line cannot parse, fed to `v -check -nocolor -` on stdin | exit 1, `.v3_stdin_…v:3:1: error: invalid expression: unexpected token` — the lane's central compiler claim reproduced by hand | 2026-09-25 |
| L2 | `v ast -p vtool/discovery.v` | 230 `"offset"` keys and 0 `"line"` keys, which is the evidence behind the rule that no feature may depend on the outline path | 2026-09-25 |

## Lane L4: lsp (2026-09-24)

Copied from `lsp/VERIFICATION.md` by the integrator. The lane ran in
`/home/specter/visor-lane-lsp` on branch `lane/lsp`, ending at 15 commits.

| ID | Command | Observed result | Date |
|---|---|---|---|
| L4 | `v test lsp/` | 10 test files, 111 `test_` functions, `10 passed, 10 total`, exit 0 | 2026-09-24 |
| L4 | `v -o /tmp/visor .` | exit 0, no output | 2026-09-24 |
| L4 | `v run tools/lsp_smoke.vsh --bin /tmp/visor --fixture testdata/smoke` | 12 checks, 0 failed, prints `smoke: ok`, exit 0 | 2026-09-24 |
| L4 | mutate `testdata/smoke/capabilities.golden.json`, then the smoke run | `FAIL initialize response matches the committed golden`, run ends with `1 failed` and exit 1 | 2026-09-24 |
| L4 | `v fmt -verify .` | exit 0, no file reported | 2026-09-24 |
| L4 | `/tmp/visor --version`, `--help`, `--bogus` | `visor 0.0.1` exit 0; usage text exit 0; unknown-argument line exit 2 | 2026-09-24 |
| AC1 | forbidden-import grep over `lsp/ tools/ main.v` | no match, exit 1 | 2026-09-24 |
| AC4 | vls-mode grep over the same paths | no match, exit 1 | 2026-09-24 |
| L4 | `grep -rn 'import vtool\|import engine' lsp/` | no match, so the protocol core depends on neither | 2026-09-24 |

The smoke invocation works exactly as the plan writes it: V 0.5.2 keeps `--bin`
and `--fixture` in `os.args`, so no `--` separator is needed. The run covers the
plan's four checks plus two: the request after a cancelled one is still answered,
which is what shows the silence was the cancellation rather than a dead server,
and a child that gets `exit` without `shutdown` ends with code 1.

### Re-run after the merge (integration branch, 2026-09-25)

| ID | Command | Observed result | Date |
|---|---|---|---|
| L4 | `git merge --no-ff lane/lsp` into `integration` | merged clean; `main.v` took the stdio loop with no conflict | 2026-09-25 |
| L4 | `v -o /tmp/visor-int .` | exit 0 | 2026-09-25 |
| L4 | `v test .` over the merged tree | 17 files, `17 passed, 17 total`, exit 0 | 2026-09-25 |
| L4 | `v fmt -verify .` | exit 0 | 2026-09-25 |
| L4 | smoke against `/tmp/visor-int`, the integrated binary | 12 checks, 0 failed, `smoke: ok`, exit 0 | 2026-09-25 |
| AC1, AC4 | both grep gates over the merged tree | no match | 2026-09-25 |
| L4 | file-length rule over the merged tree | no file over 4 kLOC; 4 864 lines across 40 files | 2026-09-25 |

The integrator reproduced the golden mutation rather than trusting the row, and
re-measured the two exit codes that a piped first attempt reported wrongly:
`--bogus` exits 2 and the mutated golden run exits 1.

## What the CI runner turned out to be

Recorded because a job asking for a label no runner registered queues forever
without posting a status, which is indistinguishable from a workflow that never
fired.

| Question | Observed |
|---|---|
| Registered labels | `ubuntu-latest`, `arch-latest`, `fedora-latest` on runner `main` |
| Runner | act_runner 0.6.1, docker mode, online, 8 cores |
| Container | `ubuntu:24.04`, running as root |
| Tools present in that image | `apt-get` only. No `git`, `curl`, `make`, `gcc` or `node` |
| Outbound network | reaches github.com, codeload.github.com and codeberg.org |
| `ubuntu-latest:docker://node:24-bookworm` | queues forever, that label is not registered |

So the workflow installs its toolchain with `apt-get` at the top of the job. The
install is what the V build needs; there is no image with it already in place.
