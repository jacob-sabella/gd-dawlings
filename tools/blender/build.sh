#!/usr/bin/env bash
# Rebuild every authored part into assets/hardware/ and assets/models/.
#
#   tools/blender/build.sh
#
# The .glb files are committed, so a clone needs none of this. Run it after editing a part
# script, then commit both the script and what it produced -- they are one change.
set -euo pipefail
cd "$(dirname "$0")/../.."

for part in tools/blender/*.py; do
  case "$(basename "$part")" in _*) continue ;; esac
  echo "=== $part"
  blender --background --python "$part" 2>&1 \
    | grep -E "verts,|faces|slot [0-9]|bounds|wrote|Error|Traceback|RuntimeError" || true
done
