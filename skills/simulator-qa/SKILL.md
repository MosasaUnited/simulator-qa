---
name: simulator-qa
description: Hands-on QA of a feature in the REAL running app — on an Android emulator or device, an iOS simulator, or a browser (Chromium, Firefox, WebKit, phone-sized or desktop). Launch it, drive it with real taps, typing, swipes, deep links and intents, screenshot every step and look, read the logs, then repeat in dark mode and in a second language or RTL, and report what passed with evidence. Works for any stack — native Android or iOS, Flutter, React Native, web — with an optional add-on that reads and seeds live state inside a Flutter app. Use whenever a request says test, QA, verify, confirm, check or reproduce something "on the emulator", "on the simulator", "on the device", "in the browser", "in the app", "end to end", or asks whether it "really works" — and after a change that unit tests cannot see, such as manifests, permissions, deep links, native code, layout, theming or translations. Not for writing or running unit, widget or component tests.
license: MIT
compatibility: Needs bash. Android — adb (Android SDK platform-tools). iOS — macOS with Xcode; taps need AXe or idb. Browsers — Node.js 22+ and Playwright. Flutter add-on — Flutter SDK and Node.js 22+.
---

# Simulator QA — drive the real app, look at the real screen

Tests prove the code does what its fakes assume the platform does. This skill
proves what the platform ACTUALLY does: whether the screen renders, whether the
tap lands, whether the system offers the app for a link, what the keyboard
covers, what the page looks like in Firefox, in dark mode, in Arabic.

The loop for every scenario is **act → collect evidence → look**:

1. do what a user (or another app) would do — a real tap, real typing, a real link;
2. take the evidence — the screenshot, and where it helps the UI list, the logs
   or the app's own state;
3. **open the screenshot and look at it.** A step is not verified until you
   have. Scripts report that a tap was sent, never that it did what was meant.

A scenario passes only when what you see agrees with what was intended.

## Ground rules (read before touching anything)

1. **Nothing that leaves the device.** Do not send a message, place an order,
   pay, post, or email on someone's behalf to prove a flow works. Drive the flow
   up to the last reversible step, show it, and ask. A staging backend the user
   has pointed you at is the exception — when they say so.
2. **Test data only.** Never type the user's real phone number, contacts,
   address, card or password, and do not use data you find on the device
   (clipboard, contacts, signed-in accounts) as test input. Ask for test
   credentials if the flow needs an account.
3. **Prefer a debug or dev build** with its own application id, so the user's
   installed production app and its data are never touched.
4. **A physical phone is somebody's phone.** On one, ask before installing,
   clearing data, changing a system setting or opening other apps. Emulators
   and simulators are fair game.
5. **Put back what you changed**: language, theme, clipboard, permissions,
   seeded data, anything you installed for the test.
6. **Never `git stash` the user's checkout** to compare with old code. Use a
   throwaway worktree (`git worktree add --detach <tmp>/wt HEAD`).
7. **What you see may be private.** Logs and state dumps can hold tokens and
   personal data. Quote the lines that matter in the report, not the dump.

## Setup

Scripts live in `scripts/` next to this file — `${CLAUDE_SKILL_DIR}/scripts` in
Claude Code. Below, `$S` stands for that path; shell variables do not survive
between commands, so write the path out in each one. Run them with `bash`.

They keep the session in `$QA_DIR` (default `$TMPDIR/simulator-qa`): the chosen
target, screenshots, the browser session, logs.

```bash
bash $S/devices.sh                    # what could be a target, and what is missing
bash $S/boot.sh "<AVD or simulator>"  # start one if nothing is running (selects it too)
bash $S/use.sh                        # or pick what is running: use.sh <serial | udid>
bash $S/use.sh web http://localhost:3000 --browser firefox --device "iPhone 15"
bash $S/shot.sh start                 # then Read the printed .png
```

Every script acts on the target `use.sh` chose, so the same commands work on
all three. Read the reference for the platform you are on before the first
scenario — each has the recipes and traps that do not fit here:

| Target | Read | Covers |
|---|---|---|
| Android emulator or device | `references/android.md` | building and installing, intents, deep links, permissions, system language, RTL, non-ASCII text |
| iOS simulator | `references/ios.md` | building and installing, the touch tool, deep links, permissions, push, language, what a simulator cannot do |
| Browser | `references/web.md` | first-time setup, engines, phone presets, dev servers, real mobile browsers |
| A Flutter app (any device) | `references/flutter.md` | launching through `flutter run`, reading and seeding live state, hot reload |

If the project has a `.simulator-qa.env`, it names the app under test
(`QA_APP=<application or bundle id>`) and other defaults. If it does not and
you had to work out the app id, the build command or the dev-server URL, offer
to save them there at the end — the next session then starts in one step.

## Toolkit

| Script | What it does |
|---|---|
| `bash $S/shot.sh <name>` | Screenshots the target and prints the path of a copy small enough to view. **Read it.** Every coordinate below is a pixel position in the latest one. |
| `bash $S/ui.sh [filter]` | The screen as text: one line per labelled or pressable element with the point to tap — `540,1210  Button  "Sign in"  #login`. For finding a target exactly, checking wording, or seeing what a screen reader would get. Blind to anything drawn without semantics. |
| `bash $S/tap.sh <x> <y> [--long]` | Tap or one-second long press. OS-level on devices, so it reaches system dialogs, the home screen and other apps too. |
| `bash $S/swipe.sh <x1> <y1> <x2> <y2> [ms]` | Drag; swiping up scrolls down. In a browser it scrolls by that distance. |
| `bash $S/type.sh '<text>'` | Types into whatever has focus — tap the field first. |
| `bash $S/key.sh <key>` | `enter tab delete escape up down left right`, plus `back`, `home`, and platform keys (see the script header). |
| `bash $S/open.sh <url>` | Opens a deep link, universal link or web page the way the platform would. |
| `bash $S/app.sh install\|launch\|stop\|clear\|uninstall\|list\|current` | The app under test, by id. `stop` then `launch` is a cold start. |
| `bash $S/logs.sh [lines]` | Newest log lines for the app; in a browser, console output, uncaught errors and failed requests. `--clear` first to see only what a step produced. |
| `bash $S/appearance.sh dark\|light` | System theme, or the page's `prefers-color-scheme`. |
| `bash $S/locale.sh <tag>\|reset` | Runs the app or page in another language without changing the device's own. |
| `bash $S/stop.sh` | Ends the browser and any `flutter run` this session started. Devices stay up. |
| `node $S/web.mjs select\|device\|viewport\|eval …` | Browser only: choose a dropdown option, switch phone preset or window size, run JavaScript in the page (`references/web.md`). |

Anything the scripts do not wrap is plain `adb` or `xcrun simctl`; the
references list the useful commands. A script that fails says why and exits
non-zero — read the message before retrying.

## Workflow

1. **Change → scenario list.** One row per behaviour: how the user gets there,
   what should happen, what the screen should show. Include the paths *around*
   the change — the same input by typing and by paste, the empty and the error
   state, arriving by deep link as well as by tapping through, coming back to
   the screen after leaving it. Show the list before a long run.
2. **Get the build onto the target** (platform reference). Confirm you are
   testing the code that was changed: a stale install is the most common false
   pass.
3. **Run each scenario with real input.** Screenshot, find the target (by eye,
   or `ui.sh` when it is small or one of several alike), act, wait a moment,
   screenshot again, look. If a state is slow or impossible to reach by hand —
   the 500th row, an expired session — seed it and say so in the report.
4. **Check the logs** after anything that looked wrong, and once at the end:
   a screen can look right while the console fills with errors.
5. **Second passes**, on the rows the change touched:
   - **Dark mode** — `appearance.sh dark`. Look for text that vanished into its
     background, icons that did not invert, hard-coded white panels.
   - **Another language** — `locale.sh de` for long words (truncation,
     overflow), `locale.sh ar` or `he` for right-to-left: the layout should
     mirror, while phone numbers, code and Latin text stay left-to-right.
   - **Another size** — a small phone and a tablet, or in a browser a phone
     preset and a desktop viewport; and the other engines (`references/web.md`).
   - **Large text**, where accessibility matters to the project.
6. **Fix → reload → replay.** When a scenario fails and the fix is yours to
   make: fix it, rebuild or hot-reload, replay the failing row *and* the rows
   near it. A fix earns a test that fails on the old code when one can be written.
7. **Clean up** (rule 5) and **report**.

## Gotchas

- **The first screenshot after a launch can be the previous screen.** "Launched"
  means the process started, not that the first frame is drawn. Shoot again.
- **Coordinates go stale.** They belong to the latest screenshot; after a
  scroll, a rotation, the keyboard opening or a new page, take a new one.
- **The keyboard covers the lower half** on phones. Close it (`key.sh back` on
  Android, tap outside or `key.sh enter` on iOS) before judging the layout or
  reaching for a button under it — and note that covering the submit button is
  itself a finding.
- **`enter` in a form submits it.** Do not press it to "confirm" a field unless
  submitting is the step — on a real backend that is an action you cannot undo.
- **A tap that "did nothing"** usually hit something else: an overlay, a
  permission prompt, a cookie banner, a first-run tooltip. Look before retrying.
- **Other apps have first-run screens.** The device's browser asks about
  sign-in and notifications before it shows a page; tap through them before
  judging anything that involves another app.
- **Animations and network make timing loose.** If a screenshot shows a
  spinner or a half-finished transition, wait a second and shoot again rather
  than concluding it is stuck; conclude that only after it stays that way.
- **`ui.sh` is not the screen.** It lists what the accessibility tree exposes.
  An element missing from it may still be drawn (a canvas, a custom view) —
  and an element present in it may be hidden under something else.
- **Emulators lie about some things**: no real SIM, camera, biometrics, push
  from the real service, or performance. Say what was not coverable.
- Run the scripts with `bash`, not `sh` or `zsh`.

## Keeping the cost down

A screenshot is the expensive part of each step (a phone screen is roughly 500
tokens, a desktop browser window about three times that), and the whole
conversation is re-read on every step.

- Chain the commands of one step in a single shell call — tap, type, tap,
  `ui.sh <text>`, `shot.sh` — and look at the one screenshot at the end. Split
  it only where you need to see the screen to decide the next move.
- One screenshot per step is enough; do not re-shoot a screen you already saw.
- `ui.sh <filter>` answers "is that label there, and where?" in one line.
- For a browser, test at a phone preset unless the desktop layout is the point.
- Cap log reads (`logs.sh 30`) and clear them before the step you care about.
- Start a fresh session per feature rather than one long one.

## Report template

1. **Verdict** in one line: works, or which paths are broken.
2. **What was tested on**: target, OS or browser version, build.
3. **Table:** scenario · how it was driven (touch / link / seeded) · what the
   screen showed · ✅/❌.
4. **Bugs:** steps to reproduce, the screenshot, the log line, and the cause
   in the code (file:line) when you found it.
5. **Not covered**, and why (needs a physical device, a real account, another
   OS version, an engine that is not installed).
6. **Left behind:** an installed build, seeded data, a running emulator or
   dev server, a changed setting you could not restore.
