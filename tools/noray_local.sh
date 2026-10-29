#!/usr/bin/env bash
# A noray server on this machine's loopback, for development and tools/session_probe.sh.
#   tools/noray_local.sh up       start it (installed into ~/.cache/dawlings on first use)
#   tools/noray_local.sh down     stop the one this script started
#   tools/noray_local.sh status   "running" or "stopped"
# The same noray and bun as the server (deploy/noray/pin.env) and the same settings
# (deploy/noray/noray.env), bound to 127.0.0.1. Ports: TCP 8890, UDP 8809, relays 49152-49215.
# Game side: DAWLINGS_NORAY=127.0.0.1 (or the session panel's NORAY SERVER).
set -euo pipefail
cd "$(dirname "$0")/.."
. deploy/noray/pin.env
CACHE="${DAWLINGS_CACHE:-$HOME/.cache/dawlings}"
NORAY_DIR="${NORAY_DIR:-$CACHE/noray}"
PIDFILE="$CACHE/noray.pid"
LOG="$CACHE/noray.log"
PORT="${NORAY_SOCKET_PORT:-8890}"

bun_bin() {
  if [ -n "${BUN:-}" ]; then echo "$BUN"; return; fi
  if [ -x "$CACHE/bun/node_modules/.bin/bun" ]; then echo "$CACHE/bun/node_modules/.bin/bun"; return; fi
  if command -v bun >/dev/null; then command -v bun; return; fi
  # No bun: npm ships it as a package with the binary inside.
  command -v npm >/dev/null || { echo "noray_local: needs bun $BUN_VERSION or npm to fetch it" >&2; exit 2; }
  mkdir -p "$CACHE/bun"
  [ -f "$CACHE/bun/package.json" ] || (cd "$CACHE/bun" && npm init -y >/dev/null)
  (cd "$CACHE/bun" && npm install --no-audit --no-fund "bun@$BUN_VERSION" >/dev/null)
  echo "$CACHE/bun/node_modules/.bin/bun"
}

install() {
  if [ -f "$NORAY_DIR/.pinned" ] && [ "$(cat "$NORAY_DIR/.pinned")" = "$NORAY_COMMIT" ]; then return; fi
  rm -rf "$NORAY_DIR"
  git clone -q "$NORAY_REPO" "$NORAY_DIR"
  git -C "$NORAY_DIR" checkout -q "$NORAY_COMMIT"
  (cd "$NORAY_DIR" && "$(bun_bin)" install --production >/dev/null)
  echo "$NORAY_COMMIT" > "$NORAY_DIR/.pinned"
}

running() {
  [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

case "${1:-status}" in
  up)
    if running; then echo "noray_local: already running ($(cat "$PIDFILE"))"; exit 0; fi
    mkdir -p "$CACHE"
    install
    BUN_PATH="$(bun_bin)"
    set -a; . deploy/noray/noray.env; set +a
    export NORAY_SOCKET_HOST=127.0.0.1 NORAY_HTTP_HOST=127.0.0.1 NORAY_SOCKET_PORT="$PORT"
    # Backgrounded on its own, not as part of a list, so $! is bun's pid and `down` stops bun.
    cd "$NORAY_DIR"
    nohup "$BUN_PATH" bin/noray.ts >"$LOG" 2>&1 &
    echo $! >"$PIDFILE"
    cd - >/dev/null
    for _ in $(seq 50); do
      if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then echo "noray_local: up on 127.0.0.1:$PORT ($(cat "$PIDFILE"))"; exit 0; fi
      sleep 0.1
    done
    echo "noray_local: did not come up; see $LOG" >&2; exit 1 ;;
  down)
    if running; then kill "$(cat "$PIDFILE")"; echo "noray_local: stopped"; fi
    rm -f "$PIDFILE" ;;
  status)
    if running; then echo running; else echo stopped; fi ;;
  *) echo "usage: $0 up|down|status" >&2; exit 2 ;;
esac
