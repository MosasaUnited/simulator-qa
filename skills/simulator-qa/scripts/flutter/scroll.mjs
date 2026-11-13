// Scrolls the innermost laid-out vertical scrollable by dy logical pixels
// (positive = down; a big negative number jumps back to the top).
//
//   node scroll.mjs <dy>
//
// jumpTo, not a fling — it lands in the same place every time, which a swipe
// does not. Prints "at <offset>/<maxExtent>". For a real gesture use swipe.sh.
import { rootLibrary, withVm } from './vmclient.mjs';

const dy = Number(process.argv[2]);
if (Number.isNaN(dy)) {
  console.error('usage: node scroll.mjs <dy>');
  process.exit(2);
}
const expression =
  `(() { ScrollPosition? best; void visit(Element e) { ` +
  `if (e is StatefulElement && e.state is ScrollableState) { ` +
  `final p = (e.state as ScrollableState).position; ` +
  `if (p.hasContentDimensions && p.axis == Axis.vertical && p.maxScrollExtent > 0) best = p; } ` +
  `e.visitChildren(visit); } ` +
  `WidgetsBinding.instance.rootElement!.visitChildren(visit); ` +
  `if (best == null) return 'no scrollable content'; ` +
  `best!.jumpTo((best!.pixels + ${dy}).clamp(0.0, best!.maxScrollExtent)); ` +
  `return 'at \${best!.pixels.toStringAsFixed(0)}/\${best!.maxScrollExtent.toStringAsFixed(0)}'; })()`;

withVm(async ({ libId, evaluate }) => {
  const r = await evaluate(libId(rootLibrary()), expression);
  console.log(r.valueAsString ?? r.message);
});
