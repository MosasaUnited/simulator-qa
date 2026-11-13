#!/bin/bash
# flutter/launch.sh [extra flutter-run arguments] — starts the app in debug on
# the chosen device (use.sh), detached, then waits for the Dart VM service.
# Run it from the Flutter project. Arguments the project always needs
# (--flavor dev, --dart-define=…, -t lib/main_dev.dart) go in QA_FLUTTER_ARGS.
#
# Log: $QA_DIR/run.log   PID: $QA_DIR/flutter.pid   VM URI: $QA_DIR/ws.txt
# Exit 3 = still building: run flutter/wait_ready.sh until it prints READY.
# stop.sh ends it, and the sleeper that holds its stdin open.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../env.sh"
need_target
[ "$QA_PLATFORM" = web ] && die "The Flutter add-on drives a device build. For Flutter web, run the app yourself and point use.sh web at its URL."
[ -f pubspec.yaml ] || die "Run this from the Flutter project (no pubspec.yaml in $PWD)."

if [ -f "$QA_DIR/flutter.pid" ] && kill -0 "$(cat "$QA_DIR/flutter.pid")" 2>/dev/null; then
  echo "A flutter run from an earlier launch is still alive (pid $(cat "$QA_DIR/flutter.pid")) — reusing it."
  exec bash "$HERE/wait_ready.sh"
fi

: > "$QA_DIR/run.log"
rm -f "$QA_DIR/ws.txt"
# stdin must stay OPEN and silent. `--machine` reads commands from it: closed,
# `flutter run` can sit idle without ever starting the build; at end-of-file
# (/dev/null) it takes that as "the client left" and quits. A sleeper holding a
# fifo's write end gives it a stdin that never says either.
rm -f "$QA_DIR/stdin"
mkfifo "$QA_DIR/stdin"
nohup sleep 86400 > "$QA_DIR/stdin" 2>/dev/null &
echo $! > "$QA_DIR/stdin.pid"
# shellcheck disable=SC2086 — QA_FLUTTER_ARGS is a list of arguments.
nohup flutter run -d "$QA_DEVICE" ${QA_FLUTTER_ARGS:-} "$@" --machine \
  > "$QA_DIR/run.log" 2>&1 < "$QA_DIR/stdin" &
echo $! > "$QA_DIR/flutter.pid"
echo "flutter run pid $(cat "$QA_DIR/flutter.pid") → $QA_PLATFORM $QA_DEVICE, log $QA_DIR/run.log"
exec bash "$HERE/wait_ready.sh"
