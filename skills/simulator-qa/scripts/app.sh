#!/bin/bash
# app.sh — the app under test, by application id (Android) or bundle id (iOS).
#
#   app.sh install <file.apk | Some.app>
#   app.sh launch [id]     cold or warm start; remembers the id for later calls
#   app.sh stop [id]       kill the process (the next launch is a cold start)
#   app.sh clear [id]      wipe the app's data — Android only
#   app.sh uninstall [id]
#   app.sh list            installed third-party apps
#   app.sh current         what is in the foreground — Android only
#
# The id defaults to QA_APP (.simulator-qa.env) or the last one launched.
# Not for the browser target: there, open.sh navigates.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
need_target
action=${1:?usage: app.sh install|launch|stop|clear|uninstall|list|current [id | file]}
[ "$QA_PLATFORM" = web ] && die "app.sh is for devices — on the browser target use open.sh <url>."

if [ "$action" = install ]; then
  file=${2:?usage: app.sh install <file.apk | Some.app>}
  if [ "$QA_PLATFORM" = android ]; then
    adb_dev install -r "$file"
  else
    xcrun simctl install "$QA_DEVICE" "$file" && echo "installed $file"
  fi
  exit $?
fi

if [ "$action" = list ]; then
  if [ "$QA_PLATFORM" = android ]; then
    adb_dev shell pm list packages -3 | tr -d '\r' | sed 's/^package://' | sort
  else
    xcrun simctl listapps "$QA_DEVICE" | awk '
      /ApplicationType = User/ { user = 1 }
      /CFBundleIdentifier = / { gsub(/[";]/, ""); id = $3 }
      /^    };?$/ { if (user) print id; user = 0 }' | sort
  fi
  exit 0
fi

if [ "$action" = current ]; then
  [ "$QA_PLATFORM" = android ] || die "iOS does not say which app is in front — look at the screenshot."
  adb_dev shell dumpsys activity activities | grep -E 'topResumedActivity|mResumedActivity' | head -1 | grep -oE '[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+'
  exit 0
fi

[ -n "${2:-}" ] && QA_APP=$2
need_app
case "$QA_PLATFORM:$action" in
  android:launch)
    adb_dev shell monkey -p "$QA_APP" -c android.intent.category.LAUNCHER 1 2>&1 | grep -q 'Events injected: 1' ||
      die "Could not launch $QA_APP — is it installed (app.sh list) and does it have a launcher activity?"
    echo "$QA_APP" > "$QA_DIR/app.txt"
    echo "launched $QA_APP"
    ;;
  android:stop) adb_dev shell am force-stop "$QA_APP" && echo "stopped $QA_APP" ;;
  android:clear) adb_dev shell pm clear "$QA_APP" ;;
  android:uninstall) adb_dev uninstall "$QA_APP" ;;
  ios:launch)
    xcrun simctl launch "$QA_DEVICE" "$QA_APP" > /dev/null || exit 1
    echo "$QA_APP" > "$QA_DIR/app.txt"
    echo "launched $QA_APP"
    ;;
  ios:stop) xcrun simctl terminate "$QA_DEVICE" "$QA_APP" && echo "stopped $QA_APP" ;;
  ios:clear) die "The simulator has no data wipe — app.sh uninstall, then install again." ;;
  ios:uninstall) xcrun simctl uninstall "$QA_DEVICE" "$QA_APP" && echo "uninstalled $QA_APP" ;;
  *) die "unknown action: $action" ;;
esac
