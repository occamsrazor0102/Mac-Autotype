#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/scripts/package.sh" --adhoc
open "$script_dir/dist/AutoType.app"
