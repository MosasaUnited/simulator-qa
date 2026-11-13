#!/bin/bash
# locale.sh <tag> | reset — runs the app under test in another language
# (ar, he, de, ja, pt-BR …) without changing the device's own language.
#
#   Android   the per-app language (Android 13+); the app restarts itself
#   iOS       relaunches the app with that language and region
#   browser   reopens the page with that locale (navigator.language,
#             Accept-Language, date and number formats); the session is kept
#
# Text the SYSTEM draws for the app (launcher label, widgets, share-sheet
# entries, permission prompts) follows the device language instead — see the
# platform reference for changing that. `reset` puts the app back.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
need_target
tag=${1:?usage: locale.sh <tag> | reset}

case "$QA_PLATFORM" in
  web)
    web locale "$tag"
    ;;
  android)
    need_app
    [ "$tag" = reset ] && tag=""
    adb_dev shell cmd locale set-app-locales "$QA_APP" --locales "'$tag'" ||
      die "Per-app languages need Android 13 or newer — change the system language instead (references/android.md)."
    echo "$QA_APP locale: ${tag:-system default}"
    ;;
  ios)
    need_app
    xcrun simctl terminate "$QA_DEVICE" "$QA_APP" > /dev/null 2>&1
    if [ "$tag" = reset ]; then
      xcrun simctl launch "$QA_DEVICE" "$QA_APP" > /dev/null || exit 1
      echo "$QA_APP relaunched in the simulator's language"
    else
      xcrun simctl launch "$QA_DEVICE" "$QA_APP" -AppleLanguages "($tag)" -AppleLocale "${tag//-/_}" > /dev/null || exit 1
      echo "$QA_APP relaunched in $tag (this launch only)"
    fi
    ;;
esac
