#!/usr/bin/env bash
# Prints the mod registry headless, for scripts and CI: one row per mod folder (status, id, version,
# licence, source pin, what it provides, and the reason when unavailable), the same rows the in-game
# MODS screen (F5) shows (core/mods/mod_listing.gd).
#
#   tools/rack_describe.sh              # tab-separated rows, shipped mods and $DAWLINGS_MODS
#   tools/rack_describe.sh --json       # {"roots": [...], "mods": [...]}
#   tools/rack_describe.sh --user       # also the player's user://mods/ (reads the real user data dir)
#   tools/rack_describe.sh --strict     # exit 1 when any mod is unavailable (CI)
#   DAWLINGS_MODS=/path/a:/path/b tools/rack_describe.sh
#
# Exit status: 0, or 1 with --strict and an unavailable mod; 2 when godot printed no listing (a script
# error). Never runs a game window.
set -uo pipefail
cd "$(dirname "$0")/.."
out="$(timeout 120 godot --headless --path . --script tools/rack_describe.gd -- "$@" 2>/dev/null)"
code=$?
if ! grep -q '^@@end$' <<<"$out"; then
  echo "rack_describe: no listing (run the import check: godot --headless --path . --import)" >&2
  exit 2
fi
sed -n '/^@@begin$/,/^@@end$/p' <<<"$out" | sed '1d;$d'
exit "$code"
