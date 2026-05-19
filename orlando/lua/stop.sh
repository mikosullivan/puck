#!/usr/bin/env bash
# Stop the Orlando background process started by start.sh.
# Usage: ./code/orlando/lua/stop.sh

set -euo pipefail

PID_FILE=/tmp/orlando.pid

if [[ ! -f "$PID_FILE" ]]; then
    echo "no pid file at $PID_FILE — nothing to stop"
    exit 0
fi

PID=$(cat "$PID_FILE")
if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    echo "orlando (pid $PID) stopped"
else
    echo "orlando (pid $PID) was already dead"
fi
rm -f "$PID_FILE"
