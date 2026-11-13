#!/bin/bash
# Sourced by every script: where the session's files live, which target is in
# use, project settings, and tool lookups that work when nothing is on PATH.

QA_DIR=${QA_DIR:-${TMPDIR:-/tmp}/simulator-qa}
QA_DIR=${QA_DIR%/}
QA_DIR=${QA_DIR//\/\//\/}
mkdir -p "$QA_DIR"
export QA_DIR
QA_SCRIPTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

die() {
  echo "$*" >&2
  exit 1
}

# Project settings: QA_* lines from .simulator-qa.env in the current directory
# or the repository root. Parsed, never executed. The environment wins.
_qa_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
for _f in "$PWD/.simulator-qa.env" "$_qa_root/.simulator-qa.env"; do
  [ -f "$_f" ] || continue
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in
      QA_[A-Z_]*=*)
        _k=${_line%%=*}
        _v=${_line#*=}
        _v=${_v%\"}
        _v=${_v#\"}
        [ -z "${!_k:-}" ] && export "$_k=$_v"
        ;;
    esac
  done < "$_f"
  break
done

# The app under test: QA_APP, else whatever app.sh launched last.
if [ -z "${QA_APP:-}" ] && [ -f "$QA_DIR/app.txt" ]; then
  QA_APP=$(cat "$QA_DIR/app.txt")
fi
QA_APP=${QA_APP:-}

# Android SDK tools, on PATH or in the usual install locations.
_sdk_tool() {
  local name=$1 sub=$2 base
  command -v "$name" 2>/dev/null && return
  for base in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" \
    "$HOME/Android/Sdk" "${LOCALAPPDATA:-}/Android/Sdk"; do
    [ -n "$base" ] || continue
    for exe in "$base/$sub/$name" "$base/$sub/$name.exe"; do
      if [ -x "$exe" ]; then
        echo "$exe"
        return
      fi
    done
  done
}
ADB=$(_sdk_tool adb platform-tools)
EMULATOR=$(_sdk_tool emulator emulator)

# "android <serial>", "ios <udid>" or "web", written by use.sh.
QA_PLATFORM=""
QA_DEVICE=""
if [ -f "$QA_DIR/target.txt" ]; then
  read -r QA_PLATFORM QA_DEVICE < "$QA_DIR/target.txt"
fi

adb_dev() {
  [ -n "$ADB" ] || die "adb not found — install Android platform-tools or set ANDROID_HOME."
  "$ADB" -s "$QA_DEVICE" "$@"
}

# One argument, quoted for the DEVICE's shell (adb shell re-parses its command).
shell_quote() {
  local q="'" r="'\\''"
  printf "'%s'" "${1//$q/$r}"
}

need_target() {
  [ -n "$QA_PLATFORM" ] || die "No target chosen — run devices.sh, then use.sh."
}

need_app() {
  [ -n "$QA_APP" ] || die "No app id — pass one, or set QA_APP in .simulator-qa.env."
}

web() { node "$QA_SCRIPTS/web.mjs" "$@"; }

# Which tool can touch an iOS simulator: axe, idb, or nothing.
ios_touch_tool() {
  if command -v axe > /dev/null 2>&1; then
    echo axe
  elif command -v idb > /dev/null 2>&1; then
    echo idb
  fi
}

IOS_TOUCH_HINT="No iOS touch tool. simctl cannot tap; install one:
  brew install cameroncooke/axe/axe
(or idb: brew install idb-companion && pip3 install fb-idb)"

# Screenshot pixels → the units the target's input takes (see shot.sh).
to_device() {
  local scale
  scale=$(cat "$QA_DIR/scale.txt" 2>/dev/null || echo 1)
  awk -v v="$1" -v s="$scale" 'BEGIN { printf "%d", v * s + 0.5 }'
}
