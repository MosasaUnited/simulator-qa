#!/bin/bash
# boot.sh <avd-name | simulator-name | simulator-udid> — starts an Android
# emulator or an iOS simulator, waits until it has booted, and selects it.
#
# An emulator keeps running after this returns; close its window (or
# `adb emu kill`) when the session is over. Add --headless for no window.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
name=${1:?usage: boot.sh <avd-name | simulator-name | udid> [--headless]}
headless=${2:-}

if [ -n "$EMULATOR" ] && "$EMULATOR" -list-avds 2>/dev/null | grep -qx "$name"; then
  before=$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}' | sort)
  flags=(-avd "$name" -no-snapshot-save -no-boot-anim)
  [ "$headless" = --headless ] && flags+=(-no-window)
  nohup "$EMULATOR" "${flags[@]}" > "$QA_DIR/emulator.log" 2>&1 &
  echo "starting $name (log $QA_DIR/emulator.log)"
  for _ in $(seq 1 180); do
    for serial in $("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}'); do
      if ! grep -qx "$serial" <<< "$before" &&
        [ "$("$ADB" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
        exec bash "$HERE/use.sh" "$serial"
      fi
    done
    sleep 1
  done
  die "The emulator did not finish booting in 3 minutes — see $QA_DIR/emulator.log"
fi

if command -v xcrun > /dev/null 2>&1; then
  udid=$(xcrun simctl list devices available | grep -F "$name (" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)
  if [ -n "$udid" ]; then
    xcrun simctl boot "$udid" 2>/dev/null
    xcrun simctl bootstatus "$udid" > /dev/null 2>&1
    [ "$headless" = --headless ] || open -a Simulator
    exec bash "$HERE/use.sh" "$udid"
  fi
fi
die "No AVD or simulator called '$name' — see devices.sh."
