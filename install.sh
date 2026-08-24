#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_app="$script_dir/dist/AutoType.app"
destination="/Applications/AutoType.app"

"$script_dir/scripts/package.sh" --adhoc

if [[ -e "$destination" ]]; then
    rm -rf -- "$destination"
fi
ditto "$source_app" "$destination"

echo "Installed AutoType at $destination"
echo "On first use, grant Accessibility access when macOS asks."
