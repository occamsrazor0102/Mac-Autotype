#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_root/Info.plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][A-Za-z0-9.-]+)?$ ]] || {
    echo "Invalid bundle version: $version" >&2
    exit 1
}
artifact="${1:-$repo_root/dist/AutoType-$version.dmg}"
staple_target="${2:-$artifact}"

: "${ASC_KEY_PATH:?Set ASC_KEY_PATH to the App Store Connect .p8 key}"
: "${ASC_KEY_ID:?Set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
[[ -f "$artifact" ]] || { echo "Missing artifact: $artifact" >&2; exit 1; }
[[ -e "$staple_target" ]] || { echo "Missing staple target: $staple_target" >&2; exit 1; }

xcrun notarytool submit "$artifact" \
    --key "$ASC_KEY_PATH" \
    --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" \
    --wait
xcrun stapler staple "$staple_target"
xcrun stapler validate "$staple_target"
