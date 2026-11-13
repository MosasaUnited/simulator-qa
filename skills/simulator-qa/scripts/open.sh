#!/bin/bash
# open.sh <url> — opens a URL the way the platform would: a deep link or
# universal link lands in the app registered for it, an https page in the
# device's own browser (Chrome on Android, real Safari on the simulator), and
# on the browser target the page navigates.
#
# Android: add a package as the second argument to address one app and skip
# the chooser — which proves the app HANDLES the link, not that the system
# would OFFER it (references/android.md).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
need_target
url=${1:?usage: open.sh <url> [android-package]}

case "$QA_PLATFORM" in
  web) web goto "$url" ;;
  android)
    adb_dev shell "am start -W -a android.intent.action.VIEW -d $(shell_quote "$url") ${2:-}" | grep -E 'Error|Status|Activity|Warning' || true
    ;;
  ios)
    xcrun simctl openurl "$QA_DEVICE" "$url" && echo "opened $url"
    ;;
esac
