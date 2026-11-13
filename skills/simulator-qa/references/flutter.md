# Flutter add-on — read and seed live state

A Flutter debug build exposes the Dart VM service, and through it any Dart
expression can be evaluated *inside the running app*. That gives a QA pass a
second kind of evidence next to the screenshot: the state the screen was built
from. It also lets you put the app into states that are slow or impossible to
reach by hand on an emulator.

Use it only in a Flutter project. Everything in SKILL.md still applies — taps,
screenshots and intents are the test; evaluation is for *evidence and setup*.
Calling a controller method to "perform" a scenario skips the widget, the
gesture and the validation a user goes through, so say so in the report when
you did.

Scripts are in `scripts/flutter/` (below `$S/flutter`). Needs Node.js 22+.

## Contents

- Launch
- Evaluate
- A project prelude: dump() and seed()
- Steps
- Reload after a fix
- Attaching to a run the user started
- Settings
- Traps

## Launch

From the Flutter project, with a device chosen (`use.sh`):

```bash
bash $S/flutter/launch.sh                 # Bash timeout 600000; prints READY vm=ws://…
bash $S/flutter/launch.sh --flavor dev    # extra `flutter run` arguments pass through
bash $S/flutter/wait_ready.sh             # after exit 3 ("still building"); repeat until READY
```

A warm launch takes about a minute. The first build after a Flutter upgrade
downloads the engine and can take much longer; exit 3 means "still going", not
"failed". Arguments the project always needs belong in `QA_FLUTTER_ARGS`.

`flutter run` on iOS can add Swift Package Manager integration to `ios/`. Do
not commit that; list it in the report.

## Evaluate

```bash
node $S/flutter/vm.mjs -e 'return WidgetsBinding.instance.platformDispatcher.locale.toString();'
node $S/flutter/vm.mjs --on _CounterPageState -e 'return _counter;'
node $S/flutter/vm.mjs --on CartScreen.controller -e 'return items.length;'
```

- With no target, the body is compiled in `main.dart`'s top-level scope: its
  imports and globals are visible.
- `--on <Type>` finds the first widget, or `State`, of that class in the live
  tree and evaluates **on it**: `this` is that object, its private members are
  in scope by bare name, and so is everything its library imports. On a
  `State`, `context` and `widget` are there too — so with provider or
  flutter_bloc imported in that file, `context.read<CartCubit>().state` works.
- `--on <Type>.<field>` evaluates on that member instead — the controller,
  bloc, notifier or view model the widget holds.

The body is wrapped in a closure and must `return` something. Find the class
names by reading the screen's source; a `State` class is usually private
(`_HomePageState`), and that is fine.

## A project prelude: dump() and seed()

Two helpers make a session far cheaper. Copy
`references/state_prelude.example.dart` into the project, rewrite it for the
project's own state object, and point `QA_FLUTTER_PRELUDE` at it:

- `dump()` — one line with everything the screen is built from. Printed after
  every step, it lets most scenarios be checked without reading pixels.
- `seed(…)` — puts the app in a state by calling the same methods the UI
  would, so persisted data and the screen stay consistent.

Offer to write this prelude when a session will run more than a few scenarios.

## Steps

```bash
bash $S/flutter/step.sh add_three <<'EOF'
qa('seed', seed(3));
return 'seeding';
EOF
```

`step.sh` evaluates the body on `QA_FLUTTER_STATE`, waits, then prints the
result, any `QA[tag] => …` lines, `dump()`, and a screenshot path to Read. An
optional second argument is the wait in seconds for slow work.

`node $S/flutter/scroll.mjs <dy>` jumps the innermost vertical scrollable by
`dy` logical pixels and prints where it landed — repeatable where a swipe is
not. Use `swipe.sh` when the gesture itself is under test.

## Reload after a fix

```bash
bash $S/flutter/reload.sh             # hot reload: Dart changes, state kept
bash $S/flutter/reload.sh --restart   # hot restart: state reset
```

Native code, `AndroidManifest.xml`, `Info.plist`, Gradle files, assets and
plugins need `stop.sh` and a fresh `launch.sh`. After a reload, replay the
failing scenario and the ones next to it.

## Attaching to a run the user started

If the app is already running under the user's IDE, do not start a second one
and do not kill theirs. Take the "Dart VM Service" address their console
printed (`http://127.0.0.1:<port>/<token>=/`) and:

```bash
node $S/flutter/logtap.mjs <that address>     # run in the background; writes ws.txt, mirrors the console
bash $S/use.sh <serial or udid>               # the device their app is on
```

Reload from their IDE, not from `reload.sh`.

## Settings

In `.simulator-qa.env` at the project root (or as environment variables):

```
QA_APP=com.example.shop.dev
QA_FLUTTER_ARGS=--flavor dev --dart-define=ENV=staging
QA_FLUTTER_STATE=CartScreen.controller
QA_FLUTTER_PRELUDE=tool/qa_prelude.dart
QA_FLUTTER_ROOT_LIB=package:shop/app/app.dart
```

`QA_FLUTTER_ROOT_LIB` is only needed when `lib/main.dart` does not import
Flutter's widgets library; it must be a library the app loads that does.

## Traps

- **Expressions are one line.** Files are flattened and whole-line `//`
  comments dropped. A comment *after code* swallows the rest of the expression.
- **Futures cannot be awaited.** Fire the call and read the next `dump()`, or
  wrap it: `qa('tag', someFuture)` logs `QA[tag] => result` when it completes.
  It prints to the device log — test data only.
- **`--on` finds what is in the tree now.** If the screen is not showing, there
  is nothing to find. Navigate there first.
- **Quitting the app ends the session.** Back from the first route, or
  `app.sh stop`, kills the isolate the VM service was attached to; `launch.sh`
  again. Test cold-start paths last.
- **READY is not "drawn".** The VM is up before the first frame; the first
  screenshot can still be the launcher.
- **Release builds have no VM service.** This add-on is for debug builds;
  release-only bugs get the plain scripts.
- **Flutter web**: run it yourself (`flutter run -d web-server`) and use the
  browser target on its URL. The page is a canvas, so `ui.sh` sees little
  unless semantics are enabled; rely on screenshots.
