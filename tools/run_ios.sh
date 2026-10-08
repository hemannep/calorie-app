#!/bin/bash
set -euo pipefail

# Desktop/iCloud file providers can attach FinderInfo to generated frameworks,
# which makes Apple code signing fail. Keep generated output in a local cache.
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
personal_team=false
if [ "${1:-}" = "--personal-team" ]; then
  personal_team=true
  shift
fi
bash "$project_dir/tools/prepare_ios_build.sh"

flutter pub get
if [ "$personal_team" = true ]; then
  exec flutter run --flavor personal --dart-define=KAYLEO_APPLE_SIGN_IN_ENABLED=false "$@"
fi
exec flutter run "$@"
