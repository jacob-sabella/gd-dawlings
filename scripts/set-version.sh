#!/usr/bin/env bash
# Read, set or bump the release version. VERSION holds the next target final version (X.Y.Z); CI
# writes the concrete release string into project.godot's config/version just before an export, so
# the git tag, the GitHub release and the build's own version all carry the same string.
#
#   set-version.sh --get          # print VERSION's content (e.g. 0.0.3)
#   set-version.sh --base         # same, release segment only (X.Y.Z)
#   set-version.sh --bump minor   # print the next base (does not write)
#   set-version.sh 0.0.3b7        # write an explicit version to VERSION
#   set-version.sh --godot 0.0.3b7  # stamp project.godot's config/version, leave VERSION alone
set -euo pipefail
cd "$(dirname "$0")/.."

base() { sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/' VERSION | tr -d '[:space:]'; }

case "${1:-}" in
  --get) tr -d '[:space:]' < VERSION; echo ;;
  --base) base ;;
  --bump)
    IFS=. read -r major minor micro <<<"$(base)"
    micro="${micro:-0}"
    case "${2:-}" in
      major) echo "$((major + 1)).0.0" ;;
      minor) echo "${major}.$((minor + 1)).0" ;;
      patch) echo "${major}.${minor}.$((micro + 1))" ;;
      *) echo "unknown bump part: ${2:-}" >&2; exit 2 ;;
    esac ;;
  --godot)
    v="${2:?version}"
    if grep -q '^config/version=' project.godot; then
      sed -i -E "s|^config/version=.*|config/version=\"${v}\"|" project.godot
    else
      sed -i -E "s|^(config/name=.*)|\1\nconfig/version=\"${v}\"|" project.godot
    fi ;;
  "") echo "usage: set-version.sh --get | --base | --bump part | --godot VERSION | VERSION" >&2; exit 2 ;;
  *) echo "$1" > VERSION ;;
esac
