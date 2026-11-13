// A tap fed through Flutter's GestureBinding: a PointerDown + PointerUp pair,
// so hit testing, gesture arenas and InkWells behave as for a finger. It only
// reaches the Flutter app itself — never a system dialog, the keyboard or
// another app — so tap.sh uses it only where no OS-level touch is available.
//
//   node tap.mjs <x> <y> [--long]
//
// x/y are pixel coordinates in the last screenshot shot.sh wrote.
// --long holds the pointer down for a second, past the long-press timeout.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { QA_DIR, withVm } from './vmclient.mjs';

const [x, y, flag] = process.argv.slice(2);
if (x === undefined || y === undefined) {
  console.error('usage: node tap.mjs <x> <y> [--long]');
  process.exit(2);
}
let shotHeight;
try {
  shotHeight = Number(readFileSync(join(QA_DIR, 'shot.txt'), 'utf8').trim().split(' ')[1]);
} catch {
  console.error('Take a screenshot first (shot.sh) — coordinates are read off it.');
  process.exit(1);
}
const LIB = 'package:flutter/src/gestures/binding.dart';
const id = Date.now() % 100000000;
const point =
  `final v = GestureBinding.instance.platformDispatcher.views.first; ` +
  `final k = (v.physicalSize.height / v.devicePixelRatio) / ${shotHeight}; ` +
  `final p = Offset(${Number(x)} * k, ${Number(y)} * k); `;
const event = (type) =>
  `(() { ${point}GestureBinding.instance.handlePointerEvent(${type}(pointer: ${id}, position: p)); ` +
  `return '\${p.dx.toStringAsFixed(0)},\${p.dy.toStringAsFixed(0)}'; })()`;

withVm(async ({ libId, evaluate }) => {
  const lib = libId(LIB);
  const down = await evaluate(lib, event('PointerDownEvent'));
  if (flag === '--long') await new Promise((r) => setTimeout(r, 1000));
  await evaluate(lib, event('PointerUpEvent'));
  console.log(`${flag === '--long' ? 'long-pressed' : 'tapped'} ${x},${y} inside the Flutter app (logical ${down.valueAsString ?? down.message})`);
});
