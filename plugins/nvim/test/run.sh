#!/bin/sh
# Drives the plugin against a real server, in a headless editor.
#
#   plugins/nvim/test/run.sh [--bin <server>] [<script.lua> ...]
#
# With no script named, every .lua beside this one runs. The server comes from
# --bin, then $VISOR_BIN, then PATH. Each script gets its own editor, so one
# script's clients cannot be another's.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
plugin=$(cd "$here/.." && pwd)

bin=${VISOR_BIN:-}
scripts=

while [ $# -gt 0 ]; do
	case "$1" in
	--bin)
		bin=$2
		shift 2
		;;
	*)
		scripts="$scripts $1"
		shift
		;;
	esac
done

if [ -z "$scripts" ]; then
	for candidate in "$here"/*.lua; do
		scripts="$scripts $candidate"
	done
fi

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
status=0
# -u NONE keeps each run away from the developer's own config. With it, nothing
# sources plugin/*.lua, so a script loads the plugin file itself and the test
# sees exactly the files under plugins/nvim.
for script in $scripts; do
	echo "--- $(basename "$script")"
	if ! VISOR_BIN="$bin" nvim --headless -u NONE \
		--cmd "set runtimepath^=$plugin" \
		-l "$script"; then
		status=1
	fi
done

exit $status
