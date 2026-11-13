#!/bin/bash
# ui.sh [filter] — what is on screen, as text: one line per element that has a
# label or can be pressed, with the point to tap in screenshot coordinates.
#
#   540,1210  Button  "Sign in"  #login_button  clickable
#
# Use it to find a tap target exactly, to check a label's wording, or to see
# what a screen reader would announce. It reads the accessibility tree, so it
# is blind to anything drawn without semantics (a canvas, a game, a custom
# view that sets no label) — the screenshot stays the source of truth.
# An optional filter keeps only lines containing that text, ignoring case.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
need_target
filter=${1:-}
[ "$QA_PLATFORM" = web ] || [ -f "$QA_DIR/scale.txt" ] || bash "$HERE/shot.sh" ui > /dev/null
scale=$(cat "$QA_DIR/scale.txt" 2>/dev/null || echo 1)
[ "$QA_PLATFORM" = ios ] && [ -z "$(ios_touch_tool)" ] && die "$IOS_TOUCH_HINT"

dump() {
  case "$QA_PLATFORM" in
    web)
      web ui 2>&1
      ;;
    android)
      # One tag per line (a literal > inside an attribute is always escaped).
      adb_dev exec-out uiautomator dump /dev/tty 2>/dev/null | tr '>' '\n' | awk -v s="$scale" '
        function attr(name,   re, v) {
          re = " " name "=\"[^\"]*\""
          if (!match($0, re)) return ""
          v = substr($0, RSTART + length(name) + 3, RLENGTH - length(name) - 4)
          gsub(/&amp;/, "\\&", v); gsub(/&lt;/, "<", v); gsub(/&gt;/, ">", v)
          gsub(/&quot;/, "\"", v); gsub(/&#10;/, " ", v)
          return v
        }
        /<node / {
          text = attr("text"); desc = attr("content-desc"); id = attr("resource-id")
          cls = attr("class"); sub(/.*\./, "", cls)
          click = attr("clickable") == "true"
          if (text == "" && desc == "" && cls != "EditText" && !(click && id != "")) next
          b = attr("bounds"); gsub(/[\[\]]/, " ", b); gsub(/,/, " ", b); split(b, p, " ")
          if (p[3] - p[1] <= 0 || p[4] - p[2] <= 0) next
          line = sprintf("%d,%d  %s", (p[1] + p[3]) / 2 / s, (p[2] + p[4]) / 2 / s, cls)
          if (text != "") line = line "  \"" text "\""
          if (desc != "") line = line "  [" desc "]"
          if (id != "") { sub(/.*:id\//, "", id); line = line "  #" id }
          if (click) line = line "  clickable"
          if (attr("checked") == "true") line = line "  checked"
          if (attr("selected") == "true") line = line "  selected"
          if (attr("focused") == "true") line = line "  focused"
          if (attr("enabled") == "false") line = line "  disabled"
          print line
        }'
      ;;
    ios)
      case "$(ios_touch_tool)" in
        axe) tree=$(axe describe-ui --udid "$QA_DEVICE" 2>/dev/null) ;;
        idb) tree=$(idb ui describe-all --udid "$QA_DEVICE" 2>/dev/null) ;;
        *) die "$IOS_TOUCH_HINT" ;;
      esac
      python3 -c '
import json, sys
scale = float(sys.argv[1])
def walk(n):
    if isinstance(n, list):
        for c in n: walk(c)
        return
    if not isinstance(n, dict): return
    f = n.get("frame") or {}
    label = n.get("AXLabel") or n.get("title") or ""
    value = n.get("AXValue") or ""
    kind = n.get("type") or n.get("role_description") or n.get("role") or "?"
    w, h = f.get("width", 0), f.get("height", 0)
    if (label or value) and w > 0 and h > 0 and kind != "Application":
        line = "%d,%d  %s" % ((f["x"] + w / 2) / scale, (f["y"] + h / 2) / scale, kind)
        if label: line += "  \"%s\"" % " ".join(str(label).split())
        if value and value != label: line += "  = %s" % " ".join(str(value).split())
        ident = n.get("AXUniqueId") or n.get("AXIdentifier")
        if ident: line += "  #%s" % ident
        if n.get("enabled") is False: line += "  disabled"
        print(line)
    walk(n.get("children") or [])
walk(json.loads(sys.stdin.read() or "[]"))
' "$scale" <<< "$tree"
      ;;
  esac
}

# A failed dump must not read as "the element is not there".
out=$(dump) || {
  echo "$out"
  exit 1
}
if [ -n "$filter" ]; then
  grep -i -F -- "$filter" <<< "$out" || echo "(nothing on screen matches '$filter')"
else
  echo "${out:-(the accessibility tree is empty — rely on the screenshot)}"
fi
