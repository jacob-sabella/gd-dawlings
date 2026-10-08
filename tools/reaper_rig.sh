#!/usr/bin/env bash
# A real Reaper for proving the link against, kept entirely apart from yours.
#
#   tools/reaper_rig.sh up      # build the rig if needed, start Reaper on it, wait for OSC
#   tools/reaper_rig.sh down    # stop it
#   tools/reaper_rig.sh status
#
# Its own resource directory (-cfgfile), so it never opens your last project, never touches
# your preferences, and has the OSC device and the bridge installed without you doing either.
# Its audio goes to a null sink: a rig that plays forty tracks of test tones out of your
# speakers at 3am is not a test harness. And its window goes to the offscreen workspace like
# every other window the tooling opens.
#
# The session is built once by tools/rig/build_session.lua -- forty tracks, folders, colours,
# stock Cockos plugins, sends, markers, a loop -- and reopened every run after.
set -euo pipefail
cd "$(dirname "$0")/.."
RIG="${REAPER_RIG:-$HOME/.cache/reaper-3d/rig}"
SINK=reaper3d_null
. tools/offscreen.sh

running() { pgrep -f -- "-cfgfile $RIG/reaper.ini" >/dev/null; }

case "${1:-up}" in
  down)
    pkill -f -- "-cfgfile $RIG/reaper.ini" || true
    # A session with changes in it asks whether to save before it quits, and the rig's window
    # is on a workspace nobody is looking at. Its session is a scratch copy: discard it.
    for _ in $(seq 1 25); do running || exit 0; sleep 0.2; done
    pkill -9 -f -- "-cfgfile $RIG/reaper.ini" || true
    for _ in $(seq 1 25); do running || exit 0; sleep 0.2; done
    echo "rig: would not stop" >&2
    exit 1 ;;
  status)
    running && echo "rig: running ($RIG)" || echo "rig: stopped"
    exit 0 ;;
  up) ;;
  *) echo "usage: $0 up|down|status" >&2; exit 2 ;;
esac

if running; then echo "rig: already running"; exit 0; fi

mkdir -p "$RIG/OSC" "$RIG/Scripts" "$RIG/rig_media" "$RIG/rig_session"
[ -f "$HOME/.config/REAPER/reaper-license.rk" ] && cp -n "$HOME/.config/REAPER/reaper-license.rk" "$RIG/" || true
cp reaper/Reaper3D.ReaperOSC "$RIG/OSC/"
cp reaper/reaper3d_bridge.lua "$RIG/Scripts/"
printf 'dofile(reaper.GetResourcePath() .. "/Scripts/reaper3d_bridge.lua")\n' > "$RIG/Scripts/__startup.lua"
if [ ! -f "$RIG/reaper.ini" ]; then
  cat > "$RIG/reaper.ini" <<INI
[REAPER]
csurf_cnt=1
csurf_0=OSC "Reaper3D" 7 8000 "127.0.0.1" 9000 16384 1 "Reaper3D"
splashscreen=0
autosavemode=0
promptendrec=0
undomaxmem=64
[verchk]
lastt=4102444800
INI
fi
# Stopping a take must not open a modal: while "save/delete new files?" is up, Reaper drops
# every OSC message, and the link looks broken for a reason the link cannot see.
grep -q '^promptendrec=' "$RIG/reaper.ini" || sed -i 's/^\[REAPER\]$/[REAPER]\npromptendrec=0/' "$RIG/reaper.ini"
python3 tools/rig/make_media.py "$RIG/rig_media" >/dev/null

if ! pactl list short sinks 2>/dev/null | grep -q "$SINK"; then
  pactl load-module module-null-sink "sink_name=$SINK" \
      "sink_properties=device.description=reaper-3d-rig" >/dev/null
fi

PROJECT="$RIG/rig_session/rig.RPP"
if [ -f "$PROJECT" ]; then
  open=("$PROJECT")
else
  open=("$(pwd)/tools/rig/build_session.lua")
fi
# The bridge makes this directory when it starts, and that is what "up" waits for -- so one left
# by the last run would say up before this Reaper had even launched.
rm -rf "$RIG/Scripts/reaper3d_bridge_data"
reaper_bin="$(command -v reaper)"
( PULSE_SINK="$SINK" PIPEWIRE_NODE="$SINK" offscreen_run "$reaper_bin" -cfgfile "$RIG/reaper.ini" \
    -nosplash "${open[@]}" >"$RIG/reaper.log" 2>&1 & )

# Up means answering: the bridge writes its data directory when it starts.
for _ in $(seq 1 200); do
  if [ -d "$RIG/Scripts/reaper3d_bridge_data" ] && { [ -f "$PROJECT" ] || [ "${open[0]}" = "$PROJECT" ]; }; then
    # Reaper opens its main window from a later process than the one the compositor launched,
    # so the exec rule does not always catch it; move whatever it opened, by PID, after the fact.
    if [ -n "$OFFSCREEN_WORKSPACE" ] && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
      pid="$(pgrep -f -- "-cfgfile $RIG/reaper.ini" | head -1 || true)"
      for _ in $(seq 1 20); do
        hyprctl clients -j 2>/dev/null | grep -q "\"pid\": $pid," && break
        sleep 0.25
      done
      hyprctl eval "hl.dispatch(hl.dsp.window.move({ workspace = $OFFSCREEN_WORKSPACE, silent = true, window = 'pid:$pid' }))" >/dev/null 2>&1 || true
    fi
    echo "rig: up ($RIG)"
    exit 0
  fi
  sleep 0.2
done
echo "rig: Reaper started but the bridge did not answer; see $RIG/reaper.log" >&2
exit 1
