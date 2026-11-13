#!/bin/bash
# flutter/reload.sh [--restart] — hot reload (or hot restart) the app
# flutter/launch.sh started, after a Dart change. Native code, manifests,
# plists and assets need stop.sh and a fresh launch instead.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../env.sh"
[ -p "$QA_DIR/stdin" ] && [ -f "$QA_DIR/flutter_app.txt" ] ||
  die "No app from flutter/launch.sh is running (an IDE's debug run reloads from the IDE)."
full=false
[ "${1:-}" = --restart ] && full=true
from=$(($(wc -l < "$QA_DIR/run.log") + 1))
printf '[{"id":%s,"method":"app.restart","params":{"appId":"%s","fullRestart":%s,"pause":false,"reason":"manual"}}]\n' \
  "$(date +%s)" "$(cat "$QA_DIR/flutter_app.txt")" "$full" > "$QA_DIR/stdin"
for _ in $(seq 1 60); do
  result=$(tail -n +"$from" "$QA_DIR/run.log" | grep -o '"result":{"code":[0-9]*,"message":"[^"]*"' | tail -1)
  if [ -n "$result" ]; then
    case "$result" in
      *'"code":0'*) echo "$([ $full = true ] && echo restarted || echo reloaded)" && exit 0 ;;
      *) echo "FAILED: $result" && tail -n +"$from" "$QA_DIR/run.log" | grep -v app.progress | tail -8 | cut -c1-300 && exit 1 ;;
    esac
  fi
  sleep 0.5
done
die "No answer from flutter run in 30 s — see $QA_DIR/run.log"
