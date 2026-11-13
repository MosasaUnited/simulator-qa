#!/bin/bash
# stop.sh — ends what this session started: the browser (use.sh web) and a
# `flutter run` (flutter/launch.sh). Devices and installed apps are left alone.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"

if [ -f "$QA_DIR/web.json" ]; then
  pid=$(grep -oE '"pid":[0-9]+' "$QA_DIR/web.json" | grep -oE '[0-9]+')
  web stop > /dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.3
  done
  rm -f "$QA_DIR/web.json"
  echo "browser closed"
fi
for f in flutter.pid stdin.pid; do
  if [ -f "$QA_DIR/$f" ]; then
    kill "$(cat "$QA_DIR/$f")" 2>/dev/null && [ "$f" = flutter.pid ] && echo "flutter run stopped"
    rm -f "$QA_DIR/$f"
  fi
done
rm -f "$QA_DIR/stdin" "$QA_DIR/ws.txt" "$QA_DIR/flutter_app.txt"
[ "$QA_PLATFORM" = web ] && rm -f "$QA_DIR/target.txt"
echo "done"
