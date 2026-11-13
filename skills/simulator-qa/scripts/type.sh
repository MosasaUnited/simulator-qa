#!/bin/bash
# type.sh '<text>' — types into whatever has focus (tap the field first).
#
# Android's `input text` only takes ASCII; for other scripts paste instead
# (references/android.md). The browser takes any text. On iOS, text beyond the
# US keyboard is pasted in, which replaces the simulator's clipboard.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
need_target
text=${1:?usage: type.sh '<text>'}

case "$QA_PLATFORM" in
  web)
    web type "$text"
    ;;
  android)
    if LC_ALL=C grep -q '[^ -~]' <<< "$text"; then
      die "Android's input command only types ASCII — paste instead (references/android.md, 'Text that is not ASCII')."
    fi
    # %s is `input`'s space; the single quotes are for the device's shell.
    adb_dev shell "input text $(shell_quote "${text// /%s}")"
    echo "typed ${#text} characters"
    ;;
  ios)
    case "$(ios_touch_tool)" in
      axe)
        if LC_ALL=C grep -q '[^ -~]' <<< "$text"; then
          # AXe types US-keyboard characters only: paste the rest (Cmd+V).
          # This replaces the simulator's clipboard.
          printf '%s' "$text" | xcrun simctl pbcopy "$QA_DEVICE"
          axe key-combo --modifiers 227 --key 25 --udid "$QA_DEVICE" > /dev/null || exit 1
        else
          printf '%s' "$text" | axe type --stdin --udid "$QA_DEVICE" > /dev/null || exit 1
        fi
        ;;
      idb) idb ui text "$text" --udid "$QA_DEVICE" || exit 1 ;;
      *) die "$IOS_TOUCH_HINT" ;;
    esac
    echo "typed ${#text} characters"
    ;;
esac
