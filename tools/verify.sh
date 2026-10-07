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

godot --headless --path . tests/tests.tscn 2>&1 \
  | grep -vE "OpenXR|RuntimeManifest|RuntimeInterface|xrEnumerate|Failed querying|HMD was not|Check logged|normal mode|^\s*$"
exit "${PIPESTATUS[0]}"
