#!/bin/sh
# Drives the plugin against a real server, in a headless editor.
#
#   plugins/nvim/test/run.sh [--bin <server>] [<script.lua>]
#
# The server comes from --bin, then $VISOR_BIN, then PATH. Each script is run in
# its own editor, so one script's clients cannot be another's.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
plugin=$(cd "$here/.." && pwd)

bin=${VISOR_BIN:-}
script="$here/connect.lua"

while [ $# -gt 0 ]; do
	case "$1" in
	--bin)
		bin=$2
		shift 2
		;;
	*)
		script=$1
		shift
		;;
	esac
done

if [ -z "$bin" ]; then
	bin=$(command -v visor || true)
fi
if [ -z "$bin" ] || [ ! -x "$bin" ]; then
	echo "visor test: no server binary. Pass --bin, set \$VISOR_BIN, or put visor on PATH." >&2
	exit 1
fi
if ! command -v nvim >/dev/null 2>&1; then
	echo "visor test: no nvim on PATH." >&2
	exit 1
fi

echo "visor test: $(nvim --version | head -1), server $bin"
# -u NONE keeps this run away from the developer's own config. With it, nothing
# sources plugin/*.lua, so the script loads the plugin file itself and the test
# sees exactly the files under plugins/nvim.
VISOR_BIN="$bin" VISOR_TEST_SCRIPT="$script" exec nvim --headless -u NONE \
	--cmd "set runtimepath^=$plugin" \
	-l "$script"
