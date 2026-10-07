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
godot --headless --path . tests/tests.tscn 2>&1 \
  | grep -vE "OpenXR|RuntimeManifest|RuntimeInterface|xrEnumerate|Failed querying|HMD was not|Check logged|normal mode|^\s*$"
exit "${PIPESTATUS[0]}"
