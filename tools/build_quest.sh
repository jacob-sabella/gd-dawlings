#!/usr/bin/env bash
# Build dawlings for a Quest 3, standalone, and (with --install) put it on the headset over adb.
#
#   tools/build_quest.sh              # build/dawlings-quest.apk (debug)
#   tools/build_quest.sh --install    # and install it on the plugged-in headset, and start it
#
# Needs: Godot 4.7.2 with its Android export templates, the Android SDK (~/Android/Sdk, with
# build-tools 36.1.0, platform 36 and NDK 29, which the 4.7.2 template asks for), JDK 17, and the
# editor settings pointing at both. Fetches the vendor plugin and builds dawkit for android itself.
set -euo pipefail
cd "$(dirname "$0")/.."
tools/fetch_openxr_vendors.sh
vendor/dawkit/tools/build_native.sh android all
TEMPLATE=~/.local/share/godot/export_templates/4.7.2.stable/android_source.zip
if [ ! -f android/.build_version ]; then
	# What the editor's "Install Android Build Template" does; its command-line flag starts the
	# game instead of the editor in this project, so done by hand.
	mkdir -p android/build
	unzip -q -o "$TEMPLATE" -d android/build
	echo "4.7.2.stable" > android/.build_version
	touch android/build/.gdignore
fi
mkdir -p build
godot --headless --path . --export-debug "Quest" build/dawlings-quest.apk
ls -la build/dawlings-quest.apk
if [ "${1:-}" = "--install" ]; then
	adb install -r build/dawlings-quest.apk
	adb shell monkey -p com.jacobsabella.dawlings -c com.oculus.intent.category.VR 1 >/dev/null
fi
