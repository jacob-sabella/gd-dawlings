#!/usr/bin/env bash
# Install the Godot OpenXR Vendors plugin (GodotVR/godot_openxr_vendors) into
# addons/godotopenxrvendors: what a standalone headset build needs from its vendor -- Meta's
# passthrough, scene (the room's walls, furniture and mesh), anchors and depth on a Quest.
# Fetched, not committed: it is 80MB of prebuilt libraries for every platform, and a desktop or
# WiVRn launch runs without it.
#
#   tools/fetch_openxr_vendors.sh            # the pinned version, if it is not there already
#   tools/fetch_openxr_vendors.sh --force    # again, over whatever is there
set -euo pipefail
VERSION="5.1.0-stable"
cd "$(dirname "$0")/.."
DEST=addons/godotopenxrvendors
if [ -f "$DEST/plugin.gdextension" ] && [ "$(cat "$DEST/.version" 2>/dev/null)" = "$VERSION" ] \
		&& [ "${1:-}" != "--force" ]; then
	echo "openxr vendors $VERSION already installed"
	exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -sSLf -o "$TMP/addon.zip" \
	"https://github.com/GodotVR/godot_openxr_vendors/releases/download/$VERSION/godotopenxrvendorsaddon.zip"
unzip -q "$TMP/addon.zip" -d "$TMP/x"
rm -rf "$DEST"
mkdir -p addons
mv "$TMP/x/asset/addons/godotopenxrvendors" "$DEST"
echo "$VERSION" > "$DEST/.version"
echo "openxr vendors $VERSION installed in $DEST"
