#!/bin/bash
# setup-web.sh [chromium] [firefox] [webkit] — one-time install for the
# browser target: Playwright into ~/.cache/simulator-qa (never into the
# project), plus the engines named (default: chromium). Each engine is a
# download of roughly 100–200 MB. Skip this if the project already depends on
# Playwright: its copy is used first.
set -uo pipefail
QA_HOME=${QA_HOME:-$HOME/.cache/simulator-qa}
command -v npm > /dev/null 2>&1 || {
  echo "npm not found — install Node.js 22 or newer." >&2
  exit 1
}
mkdir -p "$QA_HOME"
[ -f "$QA_HOME/package.json" ] || echo '{"private": true}' > "$QA_HOME/package.json"
npm install --prefix "$QA_HOME" --no-fund --no-audit --silent playwright || exit 1
engines=("$@")
[ ${#engines[@]} -eq 0 ] && engines=(chromium)
"$QA_HOME/node_modules/.bin/playwright" install "${engines[@]}"
