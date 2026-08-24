#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
developer_dir="$(xcode-select -p)"

if [[ "$developer_dir" == "/Library/Developer/CommandLineTools" ]]; then
    testing_frameworks="$developer_dir/Library/Developer/Frameworks"
    testing_libraries="$developer_dir/Library/Developer/usr/lib"
    swift test --package-path "$repo_root" \
        -Xswiftc -F -Xswiftc "$testing_frameworks" \
        -Xlinker -F -Xlinker "$testing_frameworks" \
        -Xlinker -L -Xlinker "$testing_libraries" \
        -Xlinker -rpath -Xlinker "$testing_frameworks" \
        -Xlinker -rpath -Xlinker "$testing_libraries"
else
    swift test --package-path "$repo_root"
fi
