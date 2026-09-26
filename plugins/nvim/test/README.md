# nvim plugin tests

These drive the plugin against a real server over stdio, in a headless editor.

```sh
plugins/nvim/test/run.sh --bin /tmp/visor            # every script
plugins/nvim/test/run.sh --bin /tmp/visor connect.lua
```

The server comes from `--bin`, then `$VISOR_BIN`, then `PATH`. Each script runs
in its own editor, so one script's clients cannot be another's.

Nothing here mocks the protocol. The point of these tests is that an editor and
the binary agree, which a friendlier test would not show.
