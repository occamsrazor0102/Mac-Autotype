# Troubleshooting AutoType

## AutoType does not type

1. Open **System Settings → Privacy & Security → Accessibility** and enable AutoType.
2. Quit and reopen AutoType after changing the permission.
3. In the editor, select the intended running application under **Target**.
4. Return focus to that application before the countdown ends.
5. Confirm the status HUD is not paused for focus, a secure field, or a closed target.

AutoType intentionally refuses to continue when its safety checks cannot confirm the selected destination. Return to the correct target and use the pause/resume shortcut.

## Characters are missing or incorrect

- Reduce the speed or add a line delay for slow web forms, remote desktops, or terminal sessions.
- Use **Unicode** mode for emoji, composed characters, and broad language support.
- Use **Physical keys** when the destination reacts to key positions rather than inserted Unicode. Unsupported layout characters fall back to Unicode and are reported at completion.
- Verify the active macOS keyboard layout is the one expected by the destination.
- For indentation, choose spaces instead of a physical Tab when the target uses Tab for focus navigation.

## AutoType pauses immediately

- **Return to application** means a different process is frontmost. The selected process must remain frontmost.
- **Secure field detected** means the focused field is protected; AutoType will not type into it.
- **Target app closed** means the selected process ended or its identity no longer matches.
- **Accessibility permission required** means macOS revoked or has not granted permission.

Choosing a different target during a run is disabled. Stop the run, select the new target, and start again.

## A global shortcut does not save

Every shortcut needs at least one modifier and each AutoType action needs a unique combination. macOS and other apps may reserve combinations. When registration fails, AutoType keeps the previously working shortcuts.

## Presets cannot be imported

Imports must be valid UTF-8 JSON using schema version 1, no larger than 10 MB, with each preset’s text no larger than 1 MB. AutoType previews validated presets before import. An ID conflict creates a renamed copy rather than replacing existing data.

Saved presets are located at:

```text
~/Library/Application Support/io.github.occamsrazor0102.autotype/presets.json
```

If that file is damaged, preserve it when reporting a bug. It may contain private text, so redact it before sharing.

## Launch at login fails

Launch at login requires AutoType to run as an installed application bundle. Move the app to Applications, reopen it, and try again. Source executables launched directly by Swift Package Manager are not suitable for login registration.

## Build problems

Use Xcode 16 or newer and select it as the active developer directory:

```bash
xcode-select -p
swift --version
./scripts/test.sh
./scripts/package.sh --adhoc
```

The packaged application is written to `dist/AutoType.app`. `build.sh` always rebuilds it from the current source.

For a clean rebuild:

```bash
make clean
./scripts/test.sh
./build.sh
```

## Reporting a problem

[Open an issue](https://github.com/occamsrazor0102/Mac-Autotype/issues) with the macOS version, keyboard layout, target application, input mode, settings, steps to reproduce, and the exact status or error. Do not include secret preset or draft contents.
