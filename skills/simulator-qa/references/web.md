# Browsers

The browser target is driven by Playwright. `use.sh web` starts one browser
that stays open between commands; `stop.sh` closes it. Works on macOS, Linux
and Windows (Git Bash or WSL). Needs Node.js 22 or newer.

## Contents

- First-time setup
- Starting a session
- Engines: what each one stands for
- Phone and tablet presets
- The site under test
- Finding and pressing things
- Beyond the scripts
- Real mobile browsers
- What this does not cover

## First-time setup

```bash
bash $S/setup-web.sh                      # Playwright + Chromium
bash $S/setup-web.sh chromium firefox webkit
```

This installs into `~/.cache/simulator-qa`, never into the project, and each
engine is a download of roughly 100–200 MB — tell the user before starting it.
If the project already depends on `playwright` or `@playwright/test`, that copy
is used and only its engines need installing (`npx playwright install`).
`devices.sh` shows which engines are ready. On Linux, WebKit and Firefox may
need system libraries: `npx playwright install-deps`.

## Starting a session

```bash
bash $S/use.sh web http://localhost:5173
bash $S/use.sh web http://localhost:5173 --browser webkit --device "iPhone 15"
bash $S/use.sh web https://staging.example.com --browser firefox --viewport 1440x900 --locale de-DE
bash $S/use.sh web http://localhost:5173 --headed     # a visible window, to watch along
```

Starting a session replaces the previous one. Cookies and storage live for the
session: a login survives navigation, `locale.sh` and a preset change, but not
`stop.sh` or a new `use.sh web`. `locale.sh` and a preset change reload the
page, so anything typed but not submitted is gone — set them before filling a form.

## Engines: what each one stands for

| `--browser` | Stands for | Honest caveat |
|---|---|---|
| `chromium` (default) | Chrome, Edge, Brave, Opera, Android Chrome | Open-source build: no proprietary media codecs |
| `chrome`, `msedge` | The real installed browser | Must already be installed. An installed Chrome can close itself after about 30 seconds when run hidden — if the session ends on its own, add `--headed` or use `chromium` |
| `firefox` | Firefox | Playwright's patched build; very close to release Firefox |
| `webkit` | Safari, and every browser on iOS | The engine, not Safari itself: catches most layout and API differences, not Safari-only UI such as the address-bar resize or autofill |

Run the changed scenarios in Chromium first, then repeat the *visual* rows in
the other engines; logic bugs rarely differ between engines, layout and form
controls often do.

## Phone and tablet presets

`--device "<name>"` applies a Playwright device preset: viewport, pixel ratio,
user agent and touch. Common ones: `iPhone 15`, `iPhone 15 Pro Max`,
`iPhone SE`, `Pixel 7`, `Galaxy S9+`, `iPad Mini`, `iPad Pro 11`. A wrong name
prints the close matches. Change it mid-session with
`node $S/web.mjs device "Pixel 7"` (`reset` for none), or just resize:
`node $S/web.mjs viewport 390 844`.

A preset is emulation: the right size and touch events, on a desktop engine.
It finds responsive-layout bugs. It does not reproduce a phone's on-screen
keyboard, safe areas or address bar — for those see "Real mobile browsers".
Firefox has no mobile mode, so a preset there gives the size and user agent only.

## The site under test

The scripts open a URL; they do not start the site. Find how the project
serves itself (`package.json` scripts, a `Makefile`, the README), start it in
the background, wait for the port, then `use.sh web <url>`. If a server is
already running on the port, use it and do not start a second one. Stop what
you started when you finish, and say so if you leave it running.

Static files need a server too (`file://` pages get different security rules):
`python3 -m http.server 8000 --directory <folder>`.

## Finding and pressing things

`shot.sh` captures the viewport, and its pixels are CSS pixels — the same
numbers `tap.sh` takes, so no arithmetic. `shot.sh <name> --full` captures the
whole scrollable page: use it to *look* at a long page in one image, not to
read tap coordinates, which only make sense inside the viewport.

`ui.sh` lists what is in view with the point to press; `ui.sh <text>` filters.
Something below the fold is not listed until you scroll to it
(`swipe.sh 400 600 400 100`, or `key.sh End`).

`tap.sh` prints what was under the point (`→ <button> "Save"`), which catches a
tap that landed on an overlay. `type.sh` warns when nothing has focus.

**Dropdowns.** A native `<select>` opens a list drawn by the operating system,
outside the page: it is in no screenshot and cannot be tapped. Choose by label
instead — `ui.sh` shows the options and the element's id:

```bash
node $S/web.mjs select '#plan' 'Pro'        # a CSS selector, then the option's visible text
```

Custom dropdowns built from page elements are ordinary taps.

**Long press under a phone preset** is a real held touch in Chromium. Firefox
and WebKit cannot hold a touch, so there it is done with the mouse and the
output says so — a page that listens only for touch events needs Chromium, or
the real mobile browser, for that row.

**A phone preset on a page with no viewport meta tag** shows the page laid out
desktop-wide and shrunk. Coordinates still work — they are always positions in
the screenshot — but everything is tiny, and that is usually the finding.

`key.sh back | forward | reload` drive history; any Playwright key name or
chord works (`key.sh Control+A`, `key.sh Shift+Tab`).

`logs.sh` returns console messages, uncaught exceptions, failed requests and
4xx/5xx responses since the last read, and empties the buffer; `logs.sh 20`
keeps it to the newest 20, `logs.sh --clear` empties it without printing. Read
it after each scenario: a page that looks fine with a red console is a finding.

## Beyond the scripts

`node $S/web.mjs eval '<javascript expression>'` runs in the page and prints
the result — for facts a screenshot cannot give:

```bash
node $S/web.mjs eval 'document.title'
node $S/web.mjs eval 'getComputedStyle(document.querySelector("h1")).fontFamily'
node $S/web.mjs eval 'JSON.stringify(localStorage)'
node $S/web.mjs eval 'document.documentElement.scrollWidth > innerWidth'   # horizontal overflow?
node $S/web.mjs eval 'document.dir + " " + document.documentElement.lang'
```

Use it to read, and to seed state that is slow to reach by hand. Do not use it
to *perform* the scenario (`element.click()` from script skips hit testing,
overlays and disabled states that a real click respects).

`appearance.sh dark` sets `prefers-color-scheme`. A site with its own theme
switch ignores that — then tap the switch.

`locale.sh ar` sets the browser locale. A site that picks its language from a
URL prefix or a setting ignores that — then navigate or tap accordingly, and
check `document.dir` flipped to `rtl`.

## Real mobile browsers

For what only the real thing shows — the on-screen keyboard pushing the
layout, safe areas, the collapsing address bar, the real Safari:

1. boot an emulator or simulator and `use.sh` it;
2. `open.sh <url>` — it opens in the device's own browser (Chrome on Android,
   Safari on iOS);
3. drive it with the same `shot.sh` / `tap.sh` / `type.sh`.

A dev server on the computer is `http://10.0.2.2:<port>` from the Android
emulator and `http://localhost:<port>` from the iOS simulator. There are no
console logs on this path; use it for looks and behaviour.

## What this does not cover

Real Safari on macOS, browser extensions, file-download dialogs and native
pickers drawn by the operating system, DRM video, and cross-browser
performance. Say so in the report where it matters.
