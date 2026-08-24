#!/usr/bin/env bash
# Start Orlando in the background. No logging — output goes to /dev/null.
# PID written to /tmp/orlando.pid so stop.sh can find it.
#
# Usage:  ./orlando/lua/start.sh [port]
# Default port: 8181.  Binds 127.0.0.1 only — nginx is the public face.

set -euo pipefail

PORT="${1:-8181}"
PID_FILE=/tmp/orlando.pid

# Refuse to start if a previous instance looks alive.
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "orlando already running (pid $(cat "$PID_FILE")). Use stop.sh first."
    exit 1
fi

# Run from project root so package.path resolves correctly.
# Script lives at orlando/lua/start.sh, so two ups gets us to the root.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# serve.lua adds ~/.luarocks/lib/lua/5.1/ and ~/.luarocks/share/lua/5.1/
# to package.{c,}path — those rocks (cjson, lunamark, luasocket) were
# installed for 5.1 and its cjson.so has undefined `lua_pcall` under 5.4.
# Invoke lua5.1 explicitly so the interpreter matches those rocks.
nohup lua5.1 orlando/lua/serve.lua "$PORT" \
    > /dev/null 2>&1 < /dev/null &
echo $! > "$PID_FILE"

echo "orlando started on 127.0.0.1:$PORT (pid $(cat "$PID_FILE"))"
