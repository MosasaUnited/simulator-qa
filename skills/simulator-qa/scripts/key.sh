#!/bin/bash
# key.sh <key> — one key or hardware button.
#
#   everywhere        enter  tab  delete  escape  up  down  left  right
#   Android + browser back
#   Android + iOS     home
#   Android           recents, or any KEYCODE_ name (key.sh VOLUME_UP)
#   iOS               lock, or a HID usage number
#   browser           forward  reload, or any Playwright key (key.sh Control+A)
#
# iOS has no back key: tap the back button, or swipe.sh from the left edge.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
need_target
key=${1:?usage: key.sh <key>}

case "$QA_PLATFORM" in
  web)
    web key "$key"
    ;;
  android)
    case "$key" in
      enter) code=KEYCODE_ENTER ;;
      tab) code=KEYCODE_TAB ;;
      delete) code=KEYCODE_DEL ;;
      escape) code=KEYCODE_ESCAPE ;;
      up | down | left | right) code=KEYCODE_DPAD_$(tr '[:lower:]' '[:upper:]' <<< "$key") ;;
      back) code=KEYCODE_BACK ;;
      home) code=KEYCODE_HOME ;;
      recents) code=KEYCODE_APP_SWITCH ;;
      KEYCODE_* | [0-9]*) code=$key ;;
      *) code=KEYCODE_$(tr '[:lower:]' '[:upper:]' <<< "$key") ;;
    esac
    adb_dev shell input keyevent "$code"
    echo "pressed $code"
    ;;
  ios)
    tool=$(ios_touch_tool)
    [ -n "$tool" ] || die "$IOS_TOUCH_HINT"
    case "$key" in
      home | lock)
        if [ "$tool" = axe ]; then
          axe button "$key" --udid "$QA_DEVICE" > /dev/null || exit 1
        else
          idb ui button "$(tr '[:lower:]' '[:upper:]' <<< "$key")" --udid "$QA_DEVICE" || exit 1
        fi
        echo "pressed $key"
        exit 0
        ;;
      back) die "iOS has no back key — tap the back button, or swipe.sh from the left edge." ;;
      enter) code=40 ;;
      escape) code=41 ;;
      delete) code=42 ;;
      tab) code=43 ;;
      right) code=79 ;;
      left) code=80 ;;
      down) code=81 ;;
      up) code=82 ;;
      [0-9]*) code=$key ;;
      *) die "unknown key for iOS: $key (pass a HID usage number)" ;;
    esac
    if [ "$tool" = axe ]; then
      axe key "$code" --udid "$QA_DEVICE" > /dev/null || exit 1
    else
      idb ui key "$code" --udid "$QA_DEVICE" || exit 1
    fi
    echo "pressed $key"
    ;;
esac
