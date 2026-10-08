# Sourced, not run. Gives the scripts that open a real window a way to open it somewhere you
# are not looking.
#
#   offscreen_run godot --path . ...      # output on stdout as usual, window out of sight
#
# Captures and budget runs need a real window -- headless draws none of the glow, shadow and
# metal they exist to look at -- but they open one every few minutes during a loop, and a
# window that takes the screen from whoever is using the machine is not a test harness, it is
# an interruption. So on Hyprland the window goes to OFFSCREEN_WORKSPACE (10, which is SUPER+0)
# without being followed there. Anywhere else, or if the hand-off fails, it runs in place and
# says so; a capture that silently did not happen would be worse than one that was seen.
#
# OFFSCREEN_WORKSPACE= (empty) to watch it.

OFFSCREEN_WORKSPACE="${OFFSCREEN_WORKSPACE-10}"

offscreen_run() {
  if [ -n "$OFFSCREEN_WORKSPACE" ] && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] \
      && command -v hyprctl >/dev/null 2>&1; then
    local dir
    dir="$(mktemp -d)"
    # Through a runner script because the command is launched by the compositor, not by us, and
    # quoting an argument vector through Lua through hyprctl is three escaping layers too many.
    # `exec`, so the PID the compositor spawned is the PID that opens the window: the rule is
    # attached to that process, and a window opened by a child of it is not guaranteed to match.
    {
      printf '#!/usr/bin/env bash\ncd %q || exit 1\necho $$ >%q\nexec' "$PWD" "$dir/pid"
      printf ' %q' "$@"
      printf ' >%q 2>&1\n' "$dir/log"
    } >"$dir/run.sh"
    chmod +x "$dir/run.sh"
    : >"$dir/log"
    # Lua's `hyprctl dispatch` does not take the old `[rules] cmd` form; exec_cmd's second
    # argument is the same thing spelled as a table.
    if hyprctl eval "hl.exec_cmd('$dir/run.sh', { workspace = '$OFFSCREEN_WORKSPACE silent' })" \
        2>/dev/null | grep -qx ok; then
      local i=0
      while [ ! -s "$dir/pid" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
      local pid
      pid="$(cat "$dir/pid" 2>/dev/null)"
      if [ -n "$pid" ]; then
        tail --pid="$pid" -n +1 -f "$dir/log"
        rm -rf "$dir"
        return 0
      fi
    fi
    rm -rf "$dir"
    echo "offscreen: could not hand the window to workspace $OFFSCREEN_WORKSPACE; running it here" >&2
  fi
  "$@"
}
