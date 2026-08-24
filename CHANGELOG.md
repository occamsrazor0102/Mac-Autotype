# Changelog

Notable changes to AutoType are documented here. This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- Launching or reopening the menu-bar app now presents the editor window immediately.

## [2.0.0] - 2026-08-24

### Added

- Native SwiftUI menu bar app, full editor, non-activating progress HUD, and settings window.
- Explicit target-application selection and per-event safety checks.
- Automatic pauses for focus changes, secure fields, terminated targets, and lost Accessibility permission.
- Pause, resume, emergency stop, and configurable conflict-safe global shortcuts.
- Unicode and layout-aware physical-key modes with visible Unicode fallback counts.
- Configurable start delay, typing rate, tab handling, line delay, repeat count, and repeat interval.
- Searchable, tagged, favorite presets with optional configuration overrides.
- Validated, versioned JSON preset import/export with non-destructive conflict handling.
- Safe placeholder templates and locale-aware date/time built-ins.
- Optional launch at login and an in-app Accessibility permission flow.
- Unit tests for typing state transitions, safety pauses, templates, and preset persistence.
- Reproducible source packaging, hardened-runtime signing, notarization, DMG/ZIP generation, checksums, and CI workflows.

### Security and privacy

- Removed the checked-in application bundle and release archive.
- Removed unused Apple Events, USB, and library-validation entitlements.
- Removed obsolete source, screenshots, debug output, and binary build paths.
- Added target identity checks, secure-field protection, atomic user-only preset storage, bounded imports, and state-only logging.
- Kept the application free of telemetry, network code, clipboard reading, and keyboard capture.

## [1.0.0] - 2023-03-12

- Initial menu bar auto-typing utility.
