# AutoType

AutoType is a privacy-focused macOS menu bar utility for reliably typing prepared text into a specific application. It is useful for repetitive form entry, demos, snippets, test data, and any workflow where paste is unavailable or undesirable.

## Highlights

- Select a running target application before a run starts.
- Type from 1 to 100 characters per second, with a configurable countdown and per-line delay.
- Pause, resume, or emergency-stop from configurable global shortcuts.
- Automatically pause if focus leaves the selected app, the target closes, Accessibility access is lost, or a secure text field is focused.
- Choose Unicode entry for broad language and emoji support, or layout-aware physical key events with automatic Unicode fallback.
- Handle tabs as spaces, a real Tab key, or skipped input.
- Repeat a run up to 100 times with a configurable interval.
- Track progress in a non-activating heads-up display, so the target keeps focus.
- Save searchable, tagged, favorite presets with optional per-preset typing settings.
- Import and export versioned JSON presets with validation and a conflict preview.
- Use safe text templates such as `Hello {{name}}` and built-ins including `{{date}}`, `{{time}}`, and `{{datetime}}`.
- Optionally launch at login.

## Install

AutoType requires macOS 13 or newer. Release builds are universal for Apple silicon and Intel Macs.

1. Download the DMG from [GitHub Releases](https://github.com/occamsrazor0102/Mac-Autotype/releases).
2. Drag AutoType into Applications.
3. Open AutoType and grant Accessibility access when prompted.

Accessibility is the only sensitive permission AutoType needs. It does not require Apple Events, Input Monitoring, Screen Recording, or network access.

## Use

1. Open the keyboard icon in the menu bar and choose **Open Editor**.
2. Enter text or select a preset.
3. Choose the destination under **Target**. “Last active application” is convenient when you came from the intended destination.
4. Adjust speed, start delay, tabs, line delay, and repeats.
5. Select **Start Typing**, then return focus to the target before the countdown ends.

The floating status panel does not take keyboard focus. If focus changes during a run, AutoType pauses before sending the next unit. Return to the chosen application and use Pause/Resume to continue.

Default global shortcuts are:

| Action | Shortcut |
| --- | --- |
| Show AutoType | Control–Option–A |
| Start typing | Control–Option–Return |
| Pause or resume | Control–Option–Space |
| Emergency stop | Control–Option–Escape |

Shortcuts can be changed in Settings. Conflicts are rejected without discarding the previously working shortcut set.

## Templates

Placeholders contain only an identifier; they never execute code or shell commands.

```text
Hello {{name}},

Your appointment is confirmed on {{date}} at {{time}}.
```

AutoType asks once for each custom placeholder before a run. Built-in date values use the Mac’s current locale and time zone. To type literal opening braces, use `\{{`.

## Presets and privacy

Draft text remains in memory unless **Save As** or **Update** is selected. Saved presets are plaintext JSON at:

```text
~/Library/Application Support/io.github.occamsrazor0102.autotype/presets.json
```

The file is written atomically with user-only permissions. Imports are limited to 10 MB, individual preset text is limited to 1 MB, schema versions are checked, and conflicts are duplicated instead of overwriting local data. Because saved presets are plaintext, do not store passwords, recovery codes, API keys, or other secrets in them.

AutoType has:

- no telemetry, analytics, update checker, or network client;
- no clipboard reader or keyboard-capture event tap;
- no content logging—diagnostics record only state names such as “typing” or “paused”;
- no third-party runtime dependencies.

## Build from source

Building requires Xcode 16 or newer with the macOS SDK.

```bash
git clone https://github.com/occamsrazor0102/Mac-Autotype.git
cd Mac-Autotype
./scripts/test.sh
./build.sh
open dist/AutoType.app
```

`build.sh` always rebuilds from the checked-out Swift source, assembles `dist/AutoType.app`, and applies an ad-hoc signature. It never runs a checked-in executable. Other useful commands are:

```bash
make test
make run
make install
make clean
```

Pull-request CI also publishes an ad-hoc-signed DMG, ZIP, and `SHA256SUMS` as a downloadable workflow artifact for testing. Production GitHub Releases use the separate Developer ID signing and notarization workflow below.

The project is a Swift Package with a platform-independent `AutoTypeCore` library and a native SwiftUI/AppKit application. Core tests use in-memory event, clock, and safety implementations, so they never emit real keyboard events.

## Releases

Local release artifacts can be created with:

```bash
./scripts/release.sh --adhoc
```

Maintainers can pass `--identity "Developer ID Application: …"` to create a hardened-runtime build. The tag workflow imports the signing certificate, notarizes and staples the app and DMG, generates SHA-256 checksums, and publishes the artifacts. See [CONTRIBUTING.md](CONTRIBUTING.md) for the required secrets and verification steps.

## Troubleshooting and contributing

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for permissions, focus, shortcuts, and typing reliability help. Contributions are described in [CONTRIBUTING.md](CONTRIBUTING.md).

AutoType is available under the [MIT License](LICENSE).
