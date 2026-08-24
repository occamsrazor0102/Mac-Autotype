# Contributing to AutoType

Thanks for helping improve AutoType. Keep changes focused, explain user-visible behavior, and treat simulated input as a safety-sensitive feature.

## Development setup

AutoType requires macOS 13 or newer and Xcode 16 or newer.

```bash
git clone https://github.com/occamsrazor0102/Mac-Autotype.git
cd Mac-Autotype
./scripts/test.sh
./build.sh
```

Source is organized as:

- `Sources/AutoTypeCore`: models, templates, preset storage, and the testable typing state machine.
- `Sources/AutoTypeApp`: macOS event delivery, safety monitoring, hotkeys, windows, and SwiftUI views.
- `Tests/AutoTypeCoreTests`: deterministic tests that use no real keyboard events.
- `scripts`: packaging, testing, release, and notarization helpers.

## Pull requests

Before opening a pull request:

1. Run `./scripts/test.sh`.
2. Run `swift build -c release` and `./scripts/package.sh --adhoc`.
3. Test target selection, countdown, pause/resume, emergency stop, focus-loss pause, and secure-field pause on a Mac.
4. Verify Unicode text, a non-US keyboard layout if relevant, newlines, and each tab mode.
5. Update tests and documentation for changed behavior.

Do not commit generated `.app`, `.dmg`, `.zip`, `dist`, or `.build` contents.

## Safety and privacy requirements

Changes must preserve these invariants:

- A run is bound to an explicitly resolved process and checks its identity and focus before each typing unit.
- A secure field, focus change, missing Accessibility permission, or terminated target pauses output.
- The emergency-stop path remains globally available during a run.
- Draft or typed content is never logged or sent over a network.
- Drafts are not persisted implicitly. Saved preset storage must remain explicit and clearly disclosed as plaintext.
- Templates perform substitution only; they must never evaluate scripts, expressions, or commands.
- Imported files are bounded and validated before modifying the local store.
- Production entitlements stay minimal. New sensitive permissions require a concrete feature justification and documentation.

Never add analytics, update frameworks, remote fonts, package-install hooks, downloaded executables, obfuscated payloads, or shell-command execution without explicit maintainer review.

## Release workflow

Tags matching `v*` run `.github/workflows/release.yml`. The version in the tag must match `CFBundleShortVersionString` in `Info.plist`. The repository must define:

- `DEVELOPER_ID_CERTIFICATE_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `DEVELOPER_ID_APPLICATION`
- `KEYCHAIN_PASSWORD`
- `APP_STORE_CONNECT_KEY_BASE64`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`

The workflow signs with the hardened runtime, submits the app for notarization, staples it, creates ZIP and DMG artifacts, notarizes and staples the DMG, regenerates `SHA256SUMS`, and publishes a GitHub release.

## Reporting issues

Include the macOS version, keyboard layout, target application, input mode, relevant settings, exact reproduction steps, and observed versus expected behavior. Never attach presets containing secrets or private data.

By contributing, you agree that your changes are licensed under the project’s MIT License.
