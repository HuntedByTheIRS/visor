# Lane L2 verification: vtool

Rows for `docs/verification.md`. Whoever integrates the lanes moves them across;
two lanes never edit the same file.

Everything below ran from the worktree root on 2026-09-24, against V 0.5.2,
commit `1b68924`, which is what `v version` answers on this machine.

| lane | date | command | observed |
| --- | --- | --- | --- |
| L2 | 2026-09-24 | `v test vtool/` | 7 test files, 56 test functions, all passing. Per file: discovery 8, exec 8, check 15, format 6, probe 6, outline 5, version 8. |
| L2 | 2026-09-24 | `v -o /tmp/visor-l2 .` | exit 0, binary written. `/tmp/visor-l2 --version` prints `visor 0.0.1`. |
| L2 | 2026-09-24 | `v fmt -verify .` | exit 0, no file reported as unformatted. |
| L2 | 2026-09-24 | `v test .` | same 56 tests, passing. This is what CI runs. |
| L2 | 2026-09-24 | `v test vtool/` ten times in a row | 10 passing summaries, 0 failures. The count matters because this suite had a one in four failure rate before the fix noted below. |
| L2 | 2026-09-24 | a scratch program that imports `vtool`, calls `find()` then `probe()` | 289 ms for the five probe invocations, `v_version` answered `V 0.5.2 1b68924`. |

## What the tests assert against real compiler runs

These are not stubs. Each of the behaviours the module parses was reproduced by
hand first, and the tests drive the same compiler through the same pipe.

A buffer whose third line cannot parse produces exactly one error, and the file
name in it belongs to the compiler's own temporary source:

    $ printf 'fn main() {\n\tx := \n}\n' | v -check -nocolor -
    Compiler output from the default V compiler:
    .v3_stdin_354510_354510.3686521410338.140328376115264.v:3:1: error: invalid expression: unexpected token `}`
        1 | fn main() {
        2 |     x := 
        3 | }
          | ^
    exit=1

`vtool.check` returns that as one diagnostic at line 3, column 1, severity
error, with the caller's path in `file` and `has_error` set from the exit code.
The test also asserts the raw output still holds `.v3_stdin_`, so the rewrite is
shown to have done something rather than to have passed by luck.

A buffer with nothing wrong prints nothing, so a clean file and a compiler that
did nothing would look identical if the exit code were the only thing read:

    $ printf 'fn main() {}\n' | v -check -nocolor -
    exit=0

A warning-only buffer is not reachable over stdin. The compiler prints warnings
and notices only on runs that also have an error, and it does not warn about an
unused import inside `module main`. The test therefore uses a `module foo` buffer
with an unused import, which earns both:

    $ printf 'module foo\n\nimport os\n\npub fn f() int {\n\treturn 1\n}\n' | v -check -nocolor -
    Compiler output from the default V compiler:
    .v3_stdin_354543_...v:3:8: warning: module 'os' is imported but never used. ...
    .v3_stdin_354543_...v:1:1: error: project must include a `main` module or be a shared library ...
    exit=1

The test asserts both diagnostics come back, with the warning at 3:8 and the
error at 1:1. The mapping from a `notice:` line to `Severity.notice` is covered
by a separate buffer that produces a notice and a redefinition error together.

`format` is asserted byte for byte against the literal V produces, tabs and
single quotes included:

    $ printf 'fn   main(){\nprintln("x")\n}\n' | v fmt -
    fn main() {
    	println('x')
    }

`v ast -p` is asserted to return JSON holding byte offsets and no `line` or
`col` keys at all. That assertion is deliberate: it is the evidence behind the
comment saying no feature may depend on the outline path.

## The failure that took the longest to find

The probe tests died occasionally with no output when the whole suite ran on four
jobs. The runner reported `r.exit_code: 13 ; trimmed_output.len: 0`, which is a
dead process rather than a failed assertion, and nothing was coredumped.

The cause was in `vtool.exec`. When a child exits before reading the whole
buffer, the pipe has no reader, and the next write raises SIGPIPE, whose default
action kills the writer. `echo` never reads its stdin, so the probe tests walked
into it by chance:

    $ v run sigpipe2.v
    round 0: child status exited, code 0
    exit=141           # 128 + 13, killed by SIGPIPE

`vtool.exec` now masks SIGPIPE before it writes, so the write reports a broken
pipe that `os.fd_write` already drops, and the compiler's exit code remains the
only thing that says what happened. `test_a_child_that_exits_without_reading_does_not_kill_us`
in `exec_test.v` is that regression: with the mask removed, the test file dies
with the same `exit_code: 13 ; trimmed_output.len: 0` signature and no output.

## Superseded or wrong starts

The first version of the drain loop called `p.stdout_read()` once per pass. Each
call returns at most 4 KB, so a run with a large output spent its time in the
2 ms pause rather than in the read, and a 300 KB reply took about 800 ms. The
loop now reads until the pipe is empty, which brought the same test to 8 ms. The
`strings.Builder` in that test was a second fix: `+=` on a growing string copies
everything written so far, and building the 300 KB fixture that way cost 785 ms
of the 800 ms.

## What is not verified here

The end of a check run is not tested against a compiler that hangs. `diag/` owns
cancellation and timeouts by the architecture document, so `vtool` waits for the
child without a deadline, and a compiler that never exits would hang the caller.

`v -check` is the only diagnostic mode wired up. `-check-syntax` is probed and
reported, and a test covers the probe, but no `check_syntax` call exists yet
because nothing depends on the parser-only mode.

The ast path is exercised against a file in this repository. Files with build
tags, `.vsh` scripts and paths outside the worktree have not been tried.

The probe reads its findings one invocation at a time, which costs around 300 ms
at startup on this machine. That is acceptable for a language server and was left
alone rather than parallelised without a measurement to justify it.
