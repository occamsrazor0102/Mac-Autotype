#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_root/Info.plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][A-Za-z0-9.-]+)?$ ]] || {
    echo "Invalid bundle version: $version" >&2
    exit 1
}
app="$repo_root/dist/AutoType.app"
output="$repo_root/dist/AutoType-$version.dmg"

[[ -d "$app" ]] || { echo "Package the app before creating a DMG." >&2; exit 1; }
[[ "$output" == "$repo_root/dist/AutoType-$version.dmg" ]] || { echo "Refusing unsafe output path" >&2; exit 1; }

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/autotype-dmg.XXXXXX")"
cleanup() {
    rm -rf -- "$temporary_dir"
}
trap cleanup EXIT

stage="$temporary_dir/AutoType"
mkdir -p "$stage"
ditto "$app" "$stage/AutoType.app"
ln -s /Applications "$stage/Applications"

rm -f -- "$output"
hdiutil create -quiet -volname "AutoType" -srcfolder "$stage" -ov -format UDZO "$output"
hdiutil verify "$output"
echo "Created $output"
