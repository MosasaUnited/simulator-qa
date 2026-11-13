#!/bin/bash
# shot.sh [name] [--full] — screenshots the target and prints the path of a
# copy small enough to view. Read that file, and read tap coordinates off it:
# tap.sh, swipe.sh and ui.sh all speak ITS pixel coordinates.
#
# The long side is capped at QA_SHOT_MAX (default 1000 px). --full (browser
# only) captures the whole scrollable page: good for looking, not for tapping.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
need_target
name=${1:-shot}
out="$QA_DIR/$name.png"

if [ "$QA_PLATFORM" = web ]; then
  web shot "$out" ${2:-} || exit 1
  echo "$out"
  exit 0
fi

raw="$QA_DIR/$name.raw.png"
if [ "$QA_PLATFORM" = android ]; then
  adb_dev exec-out screencap -p > "$raw" 2>/dev/null
else
  xcrun simctl io "$QA_DEVICE" screenshot "$raw" > /dev/null 2>&1
fi
[ -s "$raw" ] || die "screenshot failed — is the device still there? (devices.sh)"

# Width and height from the PNG header, so no image tool is needed for that.
png_size() {
  od -An -tu1 -j16 -N8 "$1" | awk '{ print $1*16777216+$2*65536+$3*256+$4, $5*16777216+$6*65536+$7*256+$8 }'
}
read -r raw_w raw_h <<< "$(png_size "$raw")"
max=${QA_SHOT_MAX:-1000}

if [ "$raw_w" -le "$max" ] && [ "$raw_h" -le "$max" ]; then
  cp "$raw" "$out"
elif command -v sips > /dev/null 2>&1; then
  sips -Z "$max" "$raw" --out "$out" > /dev/null 2>&1
elif command -v magick > /dev/null 2>&1; then
  magick "$raw" -resize "${max}x${max}" "$out"
elif command -v convert > /dev/null 2>&1; then
  convert "$raw" -resize "${max}x${max}" "$out"
elif python3 -c 'import PIL' 2>/dev/null; then
  python3 -c 'import sys; from PIL import Image; i = Image.open(sys.argv[1]); i.thumbnail((int(sys.argv[3]),) * 2); i.save(sys.argv[2])' "$raw" "$out" "$max"
else
  cp "$raw" "$out"
  echo "note: no image resizer (ImageMagick or Pillow) — full-size screenshot, costs more to view." >&2
fi
[ -s "$out" ] || cp "$raw" "$out"
rm -f "$raw"
read -r w h <<< "$(png_size "$out")"
echo "$w $h" > "$QA_DIR/shot.txt"

# scale.txt: screenshot pixels → input units. Android input takes device
# pixels; iOS touch tools take points, so divide by the display scale too.
scale=$(awk -v a="$raw_w" -v b="$w" 'BEGIN { printf "%.6f", a / b }')
if [ "$QA_PLATFORM" = ios ]; then
  cache="$QA_DIR/ios_scale_$QA_DEVICE.txt"
  if [ ! -s "$cache" ]; then
    short=$((raw_w < raw_h ? raw_w : raw_h))
    case "$(ios_touch_tool)" in
      axe) frame=$(axe describe-ui --udid "$QA_DEVICE" 2>/dev/null) ;;
      idb) frame=$(idb ui describe-all --udid "$QA_DEVICE" 2>/dev/null) ;;
      *) frame="" ;;
    esac
    # The first frame in the tree is the application: the whole screen, in points.
    points=$(grep -oE '"(width|height)" *: *[0-9.]+' <<< "$frame" | head -2 | grep -oE '[0-9.]+$' | sort -n | head -1)
    if [ -n "$points" ]; then
      awk -v p="$short" -v q="$points" 'BEGIN { printf "%d", p / q + 0.5 }' > "$cache"
    fi
  fi
  if [ -s "$cache" ]; then
    scale=$(awk -v s="$scale" -v d="$(cat "$cache")" 'BEGIN { printf "%.6f", s / d }')
  fi
fi
echo "$scale" > "$QA_DIR/scale.txt"
echo "$out"
