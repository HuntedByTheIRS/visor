# nvim plugin tests

These drive the plugin against a real server over stdio, in a headless editor.

```sh
plugins/nvim/test/run.sh --bin /tmp/visor            # every script
plugins/nvim/test/run.sh --bin /tmp/visor connect.lua
plugins/nvim/test/run.sh --bin /tmp/visor --nvim /opt/nvim-0.11.7/bin/nvim
```

The server comes from `--bin`, then `$VISOR_BIN`, then `PATH`, and the editor
from `--nvim`, then `$NVIM_BIN`, then `PATH`, so a run can name the version it
is testing rather than inherit whichever one is first. Each script runs in its
own editor, so one script's clients cannot be another's.

`tools/editor_test.vsh` is the entry point when a verdict is wanted rather than
a stream: it checks each editor against the 0.11 floor, runs this script under
every editor it is given, and adds the per-script totals into one line.

Nothing here mocks the protocol. The point of these tests is that an editor and
the binary agree, which a friendlier test would not show.
