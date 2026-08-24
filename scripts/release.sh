#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_root/Info.plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][A-Za-z0-9.-]+)?$ ]] || {
    echo "Invalid bundle version: $version" >&2
    exit 1
}
app="$repo_root/dist/AutoType.app"
zip_path="$repo_root/dist/AutoType-$version.zip"
dmg_path="$repo_root/dist/AutoType-$version.dmg"
checksums="$repo_root/dist/SHA256SUMS"
skip_package=false
package_arguments=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-package)
            skip_package=true
            shift
            ;;
        *)
            package_arguments+=("$1")
            shift
            ;;
    esac
done

if [[ "$skip_package" == false ]]; then
    "$repo_root/scripts/package.sh" "${package_arguments[@]}"
elif [[ ! -d "$app" ]]; then
    echo "--skip-package requires an existing $app" >&2
    exit 1
fi

rm -f -- "$zip_path" "$dmg_path" "$checksums"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_path"
"$repo_root/scripts/create-dmg.sh"

(
    cd "$repo_root/dist"
    shasum -a 256 "$(basename "$zip_path")" "$(basename "$dmg_path")" > "$(basename "$checksums")"
)

echo "Release artifacts are in $repo_root/dist"
