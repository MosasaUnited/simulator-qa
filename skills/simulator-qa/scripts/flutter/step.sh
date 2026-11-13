#!/bin/bash
# One scenario step: a Dart body on stdin, evaluated inside the running app —
# ON the object QA_FLUTTER_STATE names when that is set, else in main.dart's
# top-level scope.
#
#   bash step.sh <name> [waitSeconds=1] <<'EOF'
#   increment();
#   return 'done';
#   EOF
#
# Prints the body's result, any QA[...] probe lines it logged, the state dump
# (when the project's prelude defines dump(), see QA_FLUTTER_PRELUDE) and the
# screenshot path to Read.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../env.sh"
name=${1:?usage: step.sh <name> [waitSeconds] < body}
wait=${2:-1}

body="$QA_DIR/step_$name.dart"
cat > "$body"

vm_args=(--prelude "$HERE/prelude_common.dart")
has_dump=""
if [ -n "${QA_FLUTTER_PRELUDE:-}" ]; then
  [ -f "$QA_FLUTTER_PRELUDE" ] || die "QA_FLUTTER_PRELUDE points at $QA_FLUTTER_PRELUDE, which is not there (paths are relative to where you run this)."
  vm_args+=(--prelude "$QA_FLUTTER_PRELUDE")
  grep -q 'dump()' "$QA_FLUTTER_PRELUDE" && has_dump=1
fi

from=$(($(wc -l < "$QA_DIR/run.log") + 1))
echo "## $name"
node "$HERE/vm.mjs" "${vm_args[@]}" "$body"
sleep "$wait"
tail -n +"$from" "$QA_DIR/run.log" | grep -o 'QA\[[^"]*' || true
[ -n "$has_dump" ] && node "$HERE/vm.mjs" "${vm_args[@]}" -e 'return dump();'
bash "$HERE/../shot.sh" "$name"
