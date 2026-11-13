#!/bin/bash
# devices.sh — everything that could be a target, and which one is in use.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"

echo "## Android"
if [ -n "$ADB" ]; then
  running=$("$ADB" devices -l 2>/dev/null | awk 'NR>1 && $2=="device" {m=""; for(i=3;i<=NF;i++) if($i ~ /^model:/) m=substr($i,7); print "  running  " $1 "  " m}')
  echo "${running:-  (nothing running)}"
  if [ -n "$EMULATOR" ]; then
    "$EMULATOR" -list-avds 2>/dev/null | grep -v '^INFO' | sed 's/^/  avd      /'
  fi
else
  echo "  adb not found (install Android Studio or platform-tools)"
fi

echo "## iOS simulators"
if command -v xcrun > /dev/null 2>&1; then
  booted=$(xcrun simctl list devices booted 2>/dev/null | grep -E '\(Booted\)' | sed -E 's/^ +/  booted   /')
  echo "${booted:-  (none booted)}"
  xcrun simctl list devices available 2>/dev/null | grep -E '\(Shutdown\)' | grep -E 'iPhone' | tail -5 | sed -E 's/^ +/  off      /'
  tool=$(ios_touch_tool)
  echo "  touch tool: ${tool:-none — brew install cameroncooke/axe/axe}"
else
  echo "  needs a Mac with Xcode"
fi

echo "## Browsers"
if command -v node > /dev/null 2>&1; then
  web engines 2>/dev/null || echo "  Playwright not installed — bash $HERE/setup-web.sh"
  echo "  (--browser chrome | msedge uses the browser installed on this machine)"
else
  echo "  needs Node.js 22 or newer"
fi

echo "## In use"
if [ -n "$QA_PLATFORM" ]; then
  echo "  $QA_PLATFORM $QA_DEVICE"
else
  echo "  (none — use.sh <serial | udid | web>)"
fi
