#!/usr/bin/env bash
# Is noray still introducing players? Asked the way a host asks: `register-host` over TCP, and
# a code back. If not, restart it.
#
# 2026-10-30: noray's TCP server went quiet some hours after a deploy. Its port still took the
# connection and its UDP registrar still answered, the service was "active (running)" and logged
# nothing, but nobody could get a join code until it was restarted. Not reproduced since; this
# keeps it from lasting longer than one check. Run by dawlings-noray-watchdog.timer.
set -uo pipefail
for attempt in 1 2; do
  reply="$( { printf 'register-host\n'; sleep 2; } | timeout 5 nc 127.0.0.1 8890 2>/dev/null | head -c 8)"
  [[ "$reply" == set-oid* ]] && exit 0
  sleep 3
done
echo "noray gave no join code on 8890 twice in a row; restarting it"
systemctl --user restart dawlings-noray.service
