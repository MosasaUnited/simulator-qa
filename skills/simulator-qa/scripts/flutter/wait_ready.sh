#!/bin/bash
# Waits up to ~9.5 minutes for the app flutter/launch.sh started; on success
# writes the VM service URI to $QA_DIR/ws.txt and prints READY. Exit 3 = still
# building (run it again — the build keeps going); exit 1 = the launch failed.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../env.sh"
LOG="$QA_DIR/run.log"

for _ in $(seq 1 570); do
  if grep -q '"event":"app.started"' "$LOG" 2>/dev/null; then
    grep -o '"wsUri":"[^"]*"' "$LOG" | tail -1 | cut -d'"' -f4 > "$QA_DIR/ws.txt"
    grep -o '"appId":"[^"]*"' "$LOG" | tail -1 | cut -d'"' -f4 > "$QA_DIR/flutter_app.txt"
    echo "READY vm=$(cat "$QA_DIR/ws.txt")"
    exit 0
  fi
  if grep -q -E '"event":"app.stop"|Error launching application|Could not build the application|Error \(Xcode\)' "$LOG" 2>/dev/null ||
    ! kill -0 "$(cat "$QA_DIR/flutter.pid" 2>/dev/null)" 2>/dev/null; then
    echo "FAILED — last lines of $LOG:"
    grep -v '"event":"app.progress"' "$LOG" | tail -25 | cut -c1-300
    exit 1
  fi
  sleep 1
done
echo "Still building — run flutter/wait_ready.sh again."
exit 3
