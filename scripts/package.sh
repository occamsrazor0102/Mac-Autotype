#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="release"
signing_mode="adhoc"
identity="${SIGN_IDENTITY:-}"

usage() {
    cat <<'EOF'
Usage: scripts/package.sh [--adhoc|--unsigned|--identity NAME] [--debug]

Builds AutoType from source and assembles dist/AutoType.app.
Release builds are universal (Apple silicon and Intel); debug builds use the host architecture.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --adhoc)
            signing_mode="adhoc"
            shift
            ;;
        --unsigned)
            signing_mode="unsigned"
            shift
            ;;
        --identity)
            [[ $# -ge 2 ]] || { echo "--identity requires a certificate name" >&2; exit 64; }
            signing_mode="identity"
            identity="$2"
            shift 2
            ;;
        --debug)
            configuration="debug"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

if [[ "$signing_mode" == "identity" && -z "$identity" ]]; then
    echo "A signing identity is required." >&2
    exit 64
fi

if [[ "$configuration" == "release" ]]; then
    swift build --package-path "$repo_root" --configuration release --arch arm64
    arm_bin_dir="$(swift build --package-path "$repo_root" --configuration release --arch arm64 --show-bin-path)"
    swift build --package-path "$repo_root" --configuration release --arch x86_64
    intel_bin_dir="$(swift build --package-path "$repo_root" --configuration release --arch x86_64 --show-bin-path)"
    arm_binary="$arm_bin_dir/AutoType"
    intel_binary="$intel_bin_dir/AutoType"
    [[ -x "$arm_binary" ]] || { echo "Missing executable: $arm_binary" >&2; exit 1; }
    [[ -x "$intel_binary" ]] || { echo "Missing executable: $intel_binary" >&2; exit 1; }
else
    swift build --package-path "$repo_root" --configuration debug
    bin_dir="$(swift build --package-path "$repo_root" --configuration debug --show-bin-path)"
    binary="$bin_dir/AutoType"
    [[ -x "$binary" ]] || { echo "Missing executable: $binary" >&2; exit 1; }
fi
app="$repo_root/dist/AutoType.app"

[[ "$app" == "$repo_root/dist/AutoType.app" ]] || { echo "Refusing unsafe output path" >&2; exit 1; }

rm -rf -- "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ "$configuration" == "release" ]]; then
    lipo -create "$arm_binary" "$intel_binary" -output "$app/Contents/MacOS/AutoType"
    chmod 0755 "$app/Contents/MacOS/AutoType"
else
    install -m 0755 "$binary" "$app/Contents/MacOS/AutoType"
fi
install -m 0644 "$repo_root/Info.plist" "$app/Contents/Info.plist"
install -m 0644 "$repo_root/Assets/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$app/Contents/PkgInfo"

if [[ "$configuration" == "release" ]]; then
    architecture_info="$(lipo -info "$app/Contents/MacOS/AutoType")"
    [[ "$architecture_info" == *"arm64"* && "$architecture_info" == *"x86_64"* ]] || {
        echo "Release executable is not universal: $architecture_info" >&2
        exit 1
    }
fi

case "$signing_mode" in
    identity)
        codesign --force --options runtime --timestamp \
            --entitlements "$repo_root/AutoType.entitlements" \
            --sign "$identity" "$app"
        ;;
    adhoc)
        codesign --force --options runtime \
            --entitlements "$repo_root/AutoType.entitlements" \
            --sign - "$app"
        ;;
    unsigned)
        ;;
esac

if [[ "$signing_mode" != "unsigned" ]]; then
    codesign --verify --deep --strict --verbose=2 "$app"
fi
plutil -lint "$app/Contents/Info.plist"

echo "Packaged $app"
