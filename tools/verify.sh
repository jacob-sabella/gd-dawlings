#!/usr/bin/env bash
# Run the headless test suite.
#
#   tools/verify.sh
#
# Exits non-zero on any failure, so it is usable as a pre-commit hook or in CI. This covers the
# arithmetic -- OSC framing, state parsing, room calibration -- and nothing about how the studio
# looks. For that, tools/shot.sh and your own eyes.
set -uo pipefail
cd "$(dirname "$0")/.."

# A brand-new class_name is invisible to a --headless run until the project has been scanned,
# and the failure is nasty: the test script fails to PARSE, the scene comes up with no script,
# and the run hangs forever with nothing to quit it rather than reporting an error. Godot writes
# a .uid next to every script it has seen, so an unscanned file is one without one.
if find . -name '*.gd' -not -path './.godot/*' | while read -r f; do
      [ -f "$f.uid" ] || { echo new; break; }
    done | grep -q new; then
  echo "verify: new script(s) found; scanning the project first."
  godot --headless --path . --editor --quit >/dev/null 2>&1
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

godot --headless --path . tests/tests.tscn 2>&1 \
  | grep -vE "OpenXR|RuntimeManifest|RuntimeInterface|xrEnumerate|Failed querying|HMD was not|Check logged|normal mode|^\s*$" \
  | tee "$log"
status="${PIPESTATUS[0]}"

# A SCRIPT ERROR is a failure even when nothing reported a failure.
#
# This is here because of a run that printed "499 checks, 0 failed" while four scripts were not
# compiling at all. A GDScript that fails to parse does not throw -- it simply is not there, so
# `Knob.new()` returns null, every check that would have touched a knob never executes, and the
# count quietly drops by seventeen while the summary stays green. A suite that can pass over a
# build that does not build is worse than no suite, because it is the one you stop reading.
if grep -qE "^(SCRIPT ERROR|ERROR: Failed to load script)" "$log"; then
  echo
  echo "verify: a script failed to compile or raised at runtime -- see SCRIPT ERROR above."
  echo "verify: the check count is NOT trustworthy on this run; checks in a broken script"
  echo "verify: never ran and therefore never failed."
  status=1
fi

exit "$status"
