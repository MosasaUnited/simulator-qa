# Android — emulator or device

Everything here goes through `adb`, which ships with Android Studio
(`<sdk>/platform-tools`). The scripts find it there even when it is not on
`PATH`. A physical device needs USB debugging switched on and the computer
authorised on its screen. Works the same on macOS, Linux and Windows (Git Bash
or WSL).

Raw commands below use `adb -s <serial>`; the serial is the second word of
`$QA_DIR/target.txt`, and `devices.sh` prints it.

## Contents

- Getting the build on
- Intents and deep links
- Permissions
- Language and right-to-left
- Text that is not ASCII
- Other things worth knowing

## Getting the build on

| Stack | Build and install the debug build |
|---|---|
| Native (Gradle) | `./gradlew installDebug` — with flavors, `./gradlew tasks --all \| grep install` lists the variants |
| React Native | `npx react-native run-android` (starts Metro if needed), or Gradle as above from `android/` |
| Expo | `npx expo run:android`; for Expo Go, `npx expo start` then `open.sh exp://<host>:8081` |
| Flutter | `references/flutter.md` |
| A ready-made APK | `app.sh install path/to/app.apk` |

Then `app.sh launch <application id>`. The id is `applicationId` in
`app/build.gradle(.kts)` plus any flavor or debug suffix; `app.sh list` shows
what actually got installed, and `app.sh current` what is in front.

Confirm the build is the new one before judging anything:
`adb -s <serial> shell dumpsys package <id> | grep -E 'versionName|lastUpdateTime'`.

## Intents and deep links

`open.sh <url>` fires `ACTION_VIEW`, which is what a tapped link does.

- With only a URL, the **system** resolves it — so this is the honest test of
  "does my link open my app". If a chooser or the browser appears instead, the
  intent filter (or, for `https` links, app-link verification) is the bug.
- With a package as second argument the intent is addressed to that app and the
  chooser is skipped. That proves the app *handles* the link, not that the
  system would *offer* it. Test both when the manifest changed.
- What the system has registered for a link, without launching anything:
  `adb -s <serial> shell cmd package query-activities --brief -a android.intent.action.VIEW -d '<url>'`
- App-link verification state: `adb -s <serial> shell pm get-app-links <id>`.

Other entry points another app can use, addressed to one component
(`<id>/<activity class>`):

```bash
# share sheet → text
adb -s <serial> shell "am start -n <id>/<activity> -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT 'hello'"
# text-selection toolbar
adb -s <serial> shell "am start -n <id>/<activity> -a android.intent.action.PROCESS_TEXT -t text/plain --es android.intent.extra.PROCESS_TEXT 'hello'"
# a broadcast
adb -s <serial> shell am broadcast -a <action> -n <id>/<receiver>
```

**A running app and a stopped app receive an intent on different code paths**
(`onNewIntent` versus the launch intent in `onCreate`). Test both:
`app.sh stop` in between gives the cold path.

## Permissions

```bash
adb -s <serial> shell pm grant  <id> android.permission.CAMERA
adb -s <serial> shell pm revoke <id> android.permission.CAMERA
adb -s <serial> shell pm reset-permissions            # every app — emulators only
```

Granting skips the prompt, which is right for getting past it and wrong for
testing it. To test the prompt itself, leave the permission ungranted and tap
the system dialog like a user: `tap.sh` reaches it, and `ui.sh` lists its
buttons. Test "deny" as well as "allow"; the denied path is where apps break.

## Language and right-to-left

`locale.sh <tag>` sets the **per-app** language (Android 13+). That covers the
app's own screens. Text the system draws on the app's behalf — launcher label,
home-screen widgets, shortcuts, share-sheet and selection-toolbar entries,
notifications built from resources — follows the **system** language instead.

- System language on an emulator, the reliable way: open the settings screen and
  tap through it — `adb -s <serial> shell am start -a android.settings.LOCALE_SETTINGS`.
- Mirror the layout without translating anything (fast check that nothing is
  pinned left): `adb -s <serial> shell settings put global debug.force_rtl 1`,
  then restart the app. Put it back with `0`.
- Larger text: `adb -s <serial> shell settings put system font_scale 1.3` (back to `1.0`).

## Text that is not ASCII

`adb shell input text` types ASCII only, and `type.sh` refuses anything else
rather than typing garbage. For Arabic, CJK, emoji:

- put the text where the app will read it another way — a deep link or share
  intent carrying it, or seeded state; or
- paste it: copy the text inside the emulator (the device's browser can show
  any page you serve — select, copy), then long-press the field (`tap.sh x y --long`) and tap Paste.

## Other things worth knowing

- **Web content can be missing from `ui.sh` at first.** A page in Chrome or in
  a web view often exposes nothing to the accessibility tree until it has been
  touched; after the first tap or scroll the elements appear. Until then, read
  tap targets off the screenshot.
- **Back closes the keyboard first.** `key.sh back` once hides the keyboard; a
  second one goes back. Read the screenshot between them.
- **Rotation:** `adb -s <serial> shell settings put system accelerometer_rotation 0`
  then `… put system user_rotation 1` (landscape) or `0` (portrait).
- **Process death** — the state-restoration test most apps fail: put the app in
  the background (`key.sh home`), `adb -s <serial> shell am kill <id>`, then
  bring it back from recents. It should return to the same screen with the
  same input.
- **Doze / offline:** `adb -s <serial> shell svc wifi disable` and `svc data disable`
  (re-enable both afterwards) for the no-network state.
- **Crashes** show in `logs.sh` as `FATAL EXCEPTION`; an ANR dialog is a system
  window, visible in the screenshot and in `ui.sh`.
- **Screen recording** for a bug report:
  `adb -s <serial> shell screenrecord --time-limit 20 /sdcard/qa.mp4`, then `adb pull`.
- **More than one display** (foldables, Android Auto) makes `screencap` print a
  warning; the default display is still captured.
