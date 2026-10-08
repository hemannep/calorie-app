#!/bin/bash
set -euo pipefail

# Keep generated frameworks away from Desktop/iCloud signing metadata.
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
project_key="$(printf '%s' "$project_dir" | shasum | cut -c1-12)"
cache_dir="${TMPDIR:-/private/tmp}/Kayleo/${project_key}/build"

if [ ! -L build ]; then
  mkdir -p "$(dirname "$cache_dir")"
  if [ -e build ]; then
    # Flutter resolves Swift packages before CocoaPods. Preserve this exact
    # build tree rather than replacing it with an older cache after resolution.
    if [ -e "$cache_dir" ]; then
      cache_dir="${cache_dir}-$(date +%Y%m%d-%H%M%S)-$$"
    fi
    # File Provider can time out when moving a whole directory out of Desktop.
    # Copy its contents first, then rename the original within the workspace.
    mkdir -p "$cache_dir"
    /usr/bin/rsync -a build/ "$cache_dir/"
    # SwiftPM marks checkouts read-only. This generated copy must be writable
    # so metadata cleanup and subsequent Flutter builds can update it.
    /bin/chmod -R u+w "$cache_dir"
    /usr/bin/xattr -dr com.apple.FinderInfo "$cache_dir"
    /usr/bin/xattr -dr com.apple.ResourceFork "$cache_dir"
    mkdir -p .codex-backups
    backup_dir=".codex-backups/build-before-ios-$(date +%Y%m%d-%H%M%S)-$$"
    mv build "$backup_dir"
    printf 'Preserved current build output in %s\n' "$cache_dir"
  else
    mkdir -p "$cache_dir"
  fi
  ln -s "$cache_dir" build
elif [ ! -d build ]; then
  mkdir -p "$(readlink build)"
fi
