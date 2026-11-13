#!/bin/bash
# swipe.sh <x1> <y1> <x2> <y2> [ms=300] — drags a finger between two points
# of the last screenshot. Swiping UP (y2 < y1) scrolls the content down.
#
# Browser: scrolls by the same distance with the wheel at x1,y1, which is what
# a desktop user does; add --drag as the sixth argument for a real mouse drag.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
need_target
usage="usage: swipe.sh <x1> <y1> <x2> <y2> [ms]"
x1=${1:?$usage}
y1=${2:?$usage}
x2=${3:?$usage}
y2=${4:?$usage}
ms=${5:-300}

case "$QA_PLATFORM" in
  web)
    web swipe "$x1" "$y1" "$x2" "$y2" "$ms" ${6:-}
    ;;
  android)
    adb_dev shell input swipe "$(to_device "$x1")" "$(to_device "$y1")" "$(to_device "$x2")" "$(to_device "$y2")" "$ms"
    echo "swiped $x1,$y1 → $x2,$y2"
    ;;
  ios)
    secs=$(awk -v m="$ms" 'BEGIN { printf "%.2f", m / 1000 }')
    case "$(ios_touch_tool)" in
      axe)
        axe swipe --start-x "$(to_device "$x1")" --start-y "$(to_device "$y1")" \
          --end-x "$(to_device "$x2")" --end-y "$(to_device "$y2")" --duration "$secs" --udid "$QA_DEVICE" > /dev/null || exit 1
        ;;
      idb)
        idb ui swipe "$(to_device "$x1")" "$(to_device "$y1")" "$(to_device "$x2")" "$(to_device "$y2")" \
          --duration "$secs" --udid "$QA_DEVICE" || exit 1
        ;;
      *) die "$IOS_TOUCH_HINT" ;;
    esac
    echo "swiped $x1,$y1 → $x2,$y2"
    ;;
esac
