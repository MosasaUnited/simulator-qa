#!/bin/bash
# use.sh — chooses what every other script acts on.
#
#   use.sh                       the one running Android device, else the booted simulator
#   use.sh <serial | udid>       that device
#   use.sh web [url] [--browser chromium|firefox|webkit|chrome|msedge]
#                    [--device "iPhone 15"] [--viewport 1440x900] [--locale ar-EG] [--headed]
#
# `web` starts a browser that stays open between commands (stop.sh closes it).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"

target=${1:-}
if [ "$target" = web ]; then
  shift
  command -v node > /dev/null 2>&1 || die "The browser target needs Node.js 22 or newer."
  web stop > /dev/null 2>&1
  rm -f "$QA_DIR/web.json"
  nohup node "$HERE/web.mjs" serve "$@" > "$QA_DIR/web.log" 2>&1 &
  for _ in $(seq 1 60); do
    if [ -f "$QA_DIR/web.json" ]; then
      echo web > "$QA_DIR/target.txt"
      echo 1 > "$QA_DIR/scale.txt"
      echo "using web: $(web info)"
      exit 0
    fi
    if ! kill -0 $! 2>/dev/null; then
      cat "$QA_DIR/web.log" >&2
      exit 1
    fi
    sleep 0.5
  done
  die "The browser did not start — see $QA_DIR/web.log"
fi

if [ -z "$target" ] && [ -n "$ADB" ]; then
  target=$("$ADB" devices 2>/dev/null | awk 'NR>1 && $2=="device" {print $1; exit}')
fi
if [ -z "$target" ] && command -v xcrun > /dev/null 2>&1; then
  target=$(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)
fi
[ -n "$target" ] || die "Nothing is running — see devices.sh, then boot.sh <name>."

case "$target" in
  ????????-????-????-????-????????????) platform=ios ;;
  *) platform=android ;;
esac
echo "$platform $target" > "$QA_DIR/target.txt"
rm -f "$QA_DIR/scale.txt"
echo "using $platform $target"
if [ "$platform" = ios ] && [ -z "$(ios_touch_tool)" ]; then
  echo "note: screenshots, URLs, logs and app control work; taps need a touch tool."
  echo "$IOS_TOUCH_HINT"
fi
