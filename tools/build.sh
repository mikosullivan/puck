#!/usr/bin/env bash
#
# tools/build.sh — build the complete Caspian distribution at
# /home/miko/projects/puck/ecoverse/build/. Idempotent (wipes and
# recreates on every run). See requirements/core/build.md for the spec.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$HOME/projects/puck/ecoverse/build"
SYMLINK="$HOME/.local/bin/caspian"

# ------------------------------------------------------------
# Temp scratch — phase-1 fiona.lua lands here and is discarded on exit.
# ------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ------------------------------------------------------------
# Wipe and recreate the build tree.
# ------------------------------------------------------------
echo "==> Wiping and recreating $BUILD"
rm -rf "$BUILD"
mkdir -p "$BUILD/bin" "$BUILD/caspian" "$BUILD/external"

# ------------------------------------------------------------
# Compile the caspian binary.
# ------------------------------------------------------------
echo "==> Compiling bin/caspian"
gcc -O2 -o "$BUILD/bin/caspian" \
	"$REPO/src/cli/caspian.c" \
	-I/usr/include/lua5.4 \
	/usr/lib/x86_64-linux-gnu/liblua5.4.a \
	-lm -ldl

# ------------------------------------------------------------
# Phase 1: build standalone fiona.lua in the temp dir.
# tools/build-fiona.lua minifies the two .sql files and inlines them
# as string constants in fiona.lua's schema-loading block.
# ------------------------------------------------------------
echo "==> Phase 1: building standalone fiona.lua"
lua5.4 "$REPO/tools/build-fiona.lua" > "$TMP/fiona.lua"

# Sanity check: the built fiona.lua should parse.
lua5.4 -e "local f = loadfile('$TMP/fiona.lua'); assert(f, 'phase-1 fiona.lua does not parse')"

# ------------------------------------------------------------
# Phase 2: (placeholder) copy the phase-1 fiona.lua and engine sources
# into build/caspian/. When engine.lua exists as a unified thing, this
# step becomes "bundle phase-1 fiona.lua + engine sources into
# caspian.lua." For now, we just deposit them as separate files.
# ------------------------------------------------------------
echo "==> Phase 2: placing Caspian-authored code under caspian/"
cp "$TMP/fiona.lua" "$BUILD/caspian/fiona.lua"
cp "$REPO/src/engine"/*.lua "$BUILD/caspian/"

# ------------------------------------------------------------
# External libs — TODO (fetch or copy .so files + .lua wrappers into
# build/external/). Left as an empty dir for now with a placeholder
# marker so it's clearly intentional.
# ------------------------------------------------------------
echo "==> external/ left empty (fetch/copy of external libs not implemented yet)"

# ------------------------------------------------------------
# Repoint the shell symlink.
# ------------------------------------------------------------
if [ -L "$SYMLINK" ] || [ -e "$SYMLINK" ]; then
	rm "$SYMLINK"
fi
ln -s "$BUILD/bin/caspian" "$SYMLINK"
echo "==> Repointed $SYMLINK -> $BUILD/bin/caspian"

# ------------------------------------------------------------
# Size report.
# ------------------------------------------------------------
echo
echo "==> Size report"
printf '%-45s %10s\n' "path" "bytes"
printf '%-45s %10s\n' "----" "-----"

report_dir() {
	local rel="$1"
	local path="$BUILD/$rel"
	if [ -d "$path" ]; then
		find "$path" -type f | sort | while read -r f; do
			local size
			size=$(wc -c < "$f")
			printf '%-45s %10d\n' "${f#$BUILD/}" "$size"
		done
	fi
}

report_dir bin
report_dir caspian
report_dir external

TOTAL=$(find "$BUILD" -type f -exec wc -c {} + | tail -1 | awk '{print $1}')
echo
printf '%-45s %10d\n' "TOTAL" "$TOTAL"

echo
echo "Build complete: $BUILD"
