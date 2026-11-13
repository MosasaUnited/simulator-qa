# iOS — simulator

Needs a Mac with Xcode. Everything except touch goes through `xcrun simctl`,
which Xcode provides. Raw commands below use `<udid>`: the second word of
`$QA_DIR/target.txt`, printed by `devices.sh` (`booted` also works when only
one simulator is running).

## Contents

- Touch needs one extra tool
- Getting the build on
- Deep links
- Permissions, push, location
- Language and right-to-left
- What a simulator cannot tell you
- Physical iPhones

## Touch needs one extra tool

`simctl` can install, launch, screenshot and open URLs, but it has no tap.
`tap.sh`, `swipe.sh`, `type.sh`, `key.sh` and `ui.sh` use the first of these
that is installed:

1. **AXe** — one binary: `brew install cameroncooke/axe/axe`
2. **idb** — `brew tap facebook/fb && brew install idb-companion && pip3 install fb-idb`

Without either, everything else still works, and a Flutter app started through
the add-on can be tapped from inside the app (`references/flutter.md`) — which
does not reach system dialogs or the keyboard. Installing a tool changes the
user's machine: say what is missing and ask before running the install.

Typing goes through the simulated hardware keyboard, so iOS still
auto-capitalises and "smart"-quotes it as it would for a user — `it's` arrives
as `It’s`. Text beyond the US keyboard (accents, Arabic, CJK, emoji) is pasted
in instead, which replaces the simulator's clipboard.

Web content inside Safari or a web view often does not appear in `ui.sh` until
the page has been touched; read tap targets off the screenshot there.

There is no back key. Tap the back button (`ui.sh back` finds it), or swipe in
from the left edge: `swipe.sh 2 500 300 500`.

## Getting the build on

| Stack | Build and install for the simulator |
|---|---|
| Native (Xcode) | `xcodebuild -scheme <Scheme> -sdk iphonesimulator -destination "id=<udid>" -derivedDataPath build build`, then `app.sh install build/Build/Products/Debug-iphonesimulator/<App>.app` |
| React Native | `npx react-native run-ios --udid <udid>` |
| Expo | `npx expo run:ios --device <udid>`; for Expo Go, `npx expo start` then `open.sh exp://127.0.0.1:8081` |
| Flutter | `references/flutter.md` |
| A ready-made build | `app.sh install path/to/App.app` — a simulator build; an `.ipa` for devices will not install |

`xcodebuild -list` shows the schemes; add `-workspace <X>.xcworkspace` when the
project uses CocoaPods. Then `app.sh launch <bundle id>` (`app.sh list` shows
what is installed).

`xcodebuild` output is enormous. Pipe it through `tail -20`, or
`grep -E "error:|warning: unused|BUILD"`, rather than reading all of it.

## Deep links

`open.sh <url>` is `simctl openurl`. A custom scheme (`myapp://…`) opens the
app that registered it; the first time, iOS shows an "Open in …?" alert — a
system dialog, so tap it with `tap.sh`. An `https` universal link only reaches
the app if its associated-domains entitlement and the site's
`apple-app-site-association` file agree; otherwise it opens Safari, and that
is the finding.

Like Android, a running app and a terminated app receive a link on different
code paths. `app.sh stop` between runs gives the cold path.

## Permissions, push, location

```bash
xcrun simctl privacy <udid> grant  photos   <bundle id>   # camera, microphone, location, contacts, calendar, …
xcrun simctl privacy <udid> revoke photos   <bundle id>
xcrun simctl privacy <udid> reset  all      <bundle id>   # the prompt will show again
xcrun simctl push <udid> <bundle id> payload.json         # a simulated remote notification
xcrun simctl location <udid> set 30.0444,31.2357
xcrun simctl addmedia <udid> photo.jpg                    # something to pick in the photo picker
xcrun simctl status_bar <udid> override --time 9:41 --batteryLevel 100 --cellularBars 4   # clean screenshots; `clear` to undo
echo -n 'text' | xcrun simctl pbcopy <udid>               # the simulator's clipboard
```

To test the permission prompt itself, `reset` rather than `grant`, then tap
"Allow" or "Don't Allow" like a user — and test the denied path.

## Language and right-to-left

`locale.sh <tag>` relaunches the app with `-AppleLanguages (<tag>)`, which
lasts for that launch only and leaves the simulator's own language alone.
Arabic and Hebrew mirror the layout.

To mirror without translating — a fast check that nothing is pinned left —
launch with pseudo-language flags:

```bash
xcrun simctl launch <udid> <bundle id> -AppleTextDirection YES -NSForceRightToLeftWritingDirection YES
xcrun simctl launch <udid> <bundle id> -NSDoubleLocalizedStrings YES   # every string doubled: finds truncation
```

Larger text: `xcrun simctl ui <udid> content_size extra-extra-large` (back to `medium`).

## What a simulator cannot tell you

No camera, no real push from APNs, no Face ID hardware (Features → Face ID in
the Simulator menu fakes a match), no real cellular or SIM, no App Store
purchases, and performance that says nothing about a phone. List these under
"not covered" rather than guessing.

`logs.sh` needs the app id (`QA_APP`), because the unified log is filtered by
the app's process name. `print` output from Swift is not in the unified log;
`NSLog` and `os_log`/`Logger` are. A crash leaves a report in
`~/Library/Logs/DiagnosticReports/`.

## Physical iPhones

Out of scope here. iOS has no supported way to inject a touch into a real
device from the command line; that takes a WebDriverAgent build signed for
the device (Appium, or a tool built on it). Screens that only a real device can
show are something to hand back to the user.
