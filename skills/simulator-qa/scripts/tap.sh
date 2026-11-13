#!/bin/bash
# tap.sh <x> <y> [--long] — a tap, or a one-second long press, at coordinates
# read off the last screenshot shot.sh printed.
#
# Android and iOS: an OS-level touch, so it reaches anything on screen — the
# app, the home screen, a system dialog, another app. Browser: a click (a touch
# when a phone preset is in use) in the page.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
need_target
usage="usage: tap.sh <x> <y> [--long]"
x=${1:?$usage}
y=${2:?$usage}
long=${3:-}

case "$QA_PLATFORM" in
  web)
    web tap "$x" "$y" $long
    ;;
  android)
    [ -f "$QA_DIR/scale.txt" ] || die "Take a screenshot first (shot.sh) — coordinates are read off it."
    px=$(to_device "$x")
    py=$(to_device "$y")
    if [ "$long" = --long ]; then
      adb_dev shell input swipe "$px" "$py" "$px" "$py" 1000
    else
      adb_dev shell input tap "$px" "$py"
    fi
    echo "${long:+long-}tapped $x,$y (device $px,$py)"
    ;;
  ios)
    [ -f "$QA_DIR/scale.txt" ] || die "Take a screenshot first (shot.sh) — coordinates are read off it."
    px=$(to_device "$x")
    py=$(to_device "$y")
    case "$(ios_touch_tool)" in
      axe)
        if [ "$long" = --long ]; then
          axe touch -x "$px" -y "$py" --down --up --delay 1.0 --udid "$QA_DEVICE" > /dev/null || exit 1
        else
          axe tap -x "$px" -y "$py" --udid "$QA_DEVICE" > /dev/null || exit 1
        fi
        ;;
      idb)
        if [ "$long" = --long ]; then
          idb ui tap "$px" "$py" --duration 1.0 --udid "$QA_DEVICE" || exit 1
        else
          idb ui tap "$px" "$py" --udid "$QA_DEVICE" || exit 1
        fi
        ;;
      *)
        # A Flutter app attached through the add-on can still be tapped from inside.
        if [ -f "$QA_DIR/ws.txt" ]; then
          exec node "$HERE/flutter/tap.mjs" "$x" "$y" $long
        fi
        die "$IOS_TOUCH_HINT"
        ;;
    esac
    echo "${long:+long-}tapped $x,$y (point $px,$py)"
    ;;
esac
