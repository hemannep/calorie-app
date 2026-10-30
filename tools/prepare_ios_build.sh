#!/bin/bash
set -euo pipefail

# Keep generated frameworks outside Desktop/iCloud, with bounded retention.
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$project_dir/tools/manage_ios_builds.py" "$@"
