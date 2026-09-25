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

The L1 row for the Gitea Actions run lands here once a push to `main` produces
one, with the runner label and the run URL it used.

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
