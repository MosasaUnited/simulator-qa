#!/bin/bash
# logs.sh [lines=60] — the newest log lines for the app under test.
# logs.sh --clear — discard what is there (prints nothing of it), so the next
# read holds only what the following steps produce.
#
#   Android   logcat for the app's process (QA_APP), else warnings and errors
#   iOS       the unified log for the app's process, last QA_LOG_WINDOW (2m),
#             without Apple's own subsystems unless QA_LOG_ALL=1
#   browser   console messages, uncaught errors, failed and 4xx/5xx requests
#             since the last read
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
need_target
arg=${1:-60}

case "$QA_PLATFORM" in
  web)
    web logs "$arg"
    ;;
  android)
    if [ "$arg" = --clear ]; then
      adb_dev logcat -c && echo "cleared"
      exit 0
    fi
    pid=""
    [ -n "$QA_APP" ] && pid=$(adb_dev shell pidof "$QA_APP" 2>/dev/null | tr -d '\r' | awk '{print $1}')
    if [ -n "$pid" ]; then
      adb_dev logcat -d -v brief --pid="$pid" -t "$arg" | grep -v '^-----' | cut -c1-400
    else
      [ -n "$QA_APP" ] && echo "($QA_APP is not running — showing system warnings and errors)"
      adb_dev logcat -d -v brief -t "$arg" '*:W' | grep -v '^-----' | cut -c1-400
    fi
    ;;
  ios)
    if [ "$arg" = --clear ]; then
      date +%s > "$QA_DIR/log_since.txt"
      echo "cleared"
      exit 0
    fi
    window=${QA_LOG_WINDOW:-2m}
    if [ -f "$QA_DIR/log_since.txt" ]; then
      window="$(($(date +%s) - $(cat "$QA_DIR/log_since.txt") + 1))s"
    fi
    need_app
    bundle=$(xcrun simctl get_app_container "$QA_DEVICE" "$QA_APP" app 2>/dev/null) ||
      die "$QA_APP is not installed on this simulator."
    exe=$(plutil -extract CFBundleExecutable raw "$bundle/Info.plist")
    # The system's own chatter about the process drowns the app's lines.
    predicate="process == \"$exe\""
    [ -n "${QA_LOG_ALL:-}" ] || predicate="$predicate AND NOT subsystem BEGINSWITH \"com.apple.\""
    out=$(xcrun simctl spawn "$QA_DEVICE" log show --last "$window" --style compact \
      --predicate "$predicate" 2>/dev/null | grep -v '^Timestamp' | tail -n "$arg" | cut -c1-400)
    echo "${out:-(no app log lines in the last $window — QA_LOG_ALL=1 adds system lines)}"
    ;;
esac
