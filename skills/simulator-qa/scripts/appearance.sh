#!/bin/bash
# appearance.sh dark|light — switches the system theme (Android, iOS) or the
# page's prefers-color-scheme (browser). Put it back when the pass is over.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
need_target
mode=${1:?usage: appearance.sh dark|light}
case "$mode" in dark | light) ;; *) die "usage: appearance.sh dark|light" ;; esac

case "$QA_PLATFORM" in
  web) web appearance "$mode" ;;
  android)
    adb_dev shell cmd uimode night "$([ "$mode" = dark ] && echo yes || echo no)"
    ;;
  ios)
    xcrun simctl ui "$QA_DEVICE" appearance "$mode" && echo "appearance: $mode"
    ;;
esac
