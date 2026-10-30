#!/usr/bin/env bash
# Put dawlings' noray server on the VPS, or check it, or take its Caddy block back out.
# Run by a person, from this repo, on their own machine. Idempotent: run it again to update.
#
#   deploy/noray/deploy.sh --dry-run        say every step, change nothing anywhere
#   deploy/noray/deploy.sh                  bundle, copy, install and (re)start the service
#   deploy/noray/deploy.sh --caddy          ...and add/replace the dawlings.jacobsabella.com block
#   deploy/noray/deploy.sh --verify         only check it from here (TCP code, UDP, HTTPS)
#   deploy/noray/deploy.sh --rollback-caddy <ts>   put back Caddyfile.bak.pre-dawlings-<ts>
#   deploy/noray/deploy.sh --stop           stop and disable the service (files are kept)
#
# Environment: DEPLOY_HOST (ubuntu@15.204.11.205), DEPLOY_DIR (dawlings-noray, under ~ there),
# PUBLIC_NAME (dawlings.jacobsabella.com).
#
# What it never does: touch a container, print or copy the Caddyfile (it holds other sites'
# credentials), change the firewall, or use sudo. What needs the owner is printed instead:
# the DNS record, lingering for the user, firewall ports. docs/multiplayer.md has the runbook.
set -euo pipefail
cd "$(dirname "$0")/../.."
. deploy/noray/pin.env

HOST="${DEPLOY_HOST:-ubuntu@15.204.11.205}"
DIR="${DEPLOY_DIR:-dawlings-noray}"
NAME="${PUBLIC_NAME:-dawlings.jacobsabella.com}"
# The VPS takes the homelab key, as the other sites' deploys do; DEPLOY_KEY overrides it.
KEY="${DEPLOY_KEY:-$HOME/.ssh/homelab}"
SSH=(ssh -o BatchMode=yes)
if [ -f "$KEY" ]; then SSH+=(-i "$KEY"); fi
export RSYNC_RSH="${SSH[*]}"
CADDYFILE=/home/ubuntu/aa-web/Caddyfile
CADDY=aa-caddy
DRY=0; DO_CADDY=0; ONLY_VERIFY=0; ROLLBACK=""; STOP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --caddy) DO_CADDY=1 ;;
    --verify) ONLY_VERIFY=1 ;;
    --rollback-caddy) shift; ROLLBACK="${1:?a backup timestamp}" ;;
    --stop) STOP=1 ;;
    *) echo "deploy: unknown $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '\n== %s\n' "$*"; }
# A step on this machine.
run() { if [ "$DRY" -eq 1 ]; then printf '  would run: %s\n' "$*"; else "$@"; fi; }
# A step on the VPS: the script goes over ssh's stdin, never into a file there.
remote() {
  if [ "$DRY" -eq 1 ]; then printf '  would run on %s:\n' "$HOST"; sed 's/^/    | /'; else "${SSH[@]}" "$HOST" bash -s; fi
}

verify() {
  say "checking from here"
  local ip
  ip="$(getent ahostsv4 "$NAME" | awk 'NR==1{print $1}')"
  if [ -z "$ip" ]; then
    echo "  $NAME does not resolve yet: create the A record (docs/multiplayer.md, DNS)."
    ip="${HOST#*@}"
  fi
  echo "  $NAME -> $ip"
  local reply
  reply="$( { printf 'register-host\n'; sleep 1; } | timeout 4 nc "$ip" 8890 2>/dev/null | head -1 || true)"
  if [[ "$reply" == set-oid* ]]; then echo "  TCP 8890: noray answers ($reply)"; else echo "  TCP 8890: NO ANSWER (service down, or the port is filtered)"; fi
  reply="$(printf 'nobody' | timeout 3 nc -u -w 2 "$ip" 8809 2>/dev/null | head -c 80 || true)"
  if [ -n "$reply" ]; then echo "  UDP 8809: registrar answers (\"$reply\")"; else echo "  UDP 8809: no answer (filtered, or nc here cannot read UDP replies)"; fi
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --resolve "$NAME:443:$ip" "https://$NAME/health" || true)"
  echo "  HTTPS /health: ${code:-none} (200 once the Caddy block is in)"
}

if [ "$ONLY_VERIFY" -eq 1 ]; then verify; exit 0; fi

if [ -n "$ROLLBACK" ]; then
  say "putting Caddyfile.bak.pre-dawlings-$ROLLBACK back"
  remote <<EOF
set -euo pipefail
test -f "$CADDYFILE.bak.pre-dawlings-$ROLLBACK"
cat "$CADDYFILE.bak.pre-dawlings-$ROLLBACK" > "$CADDYFILE"
docker exec $CADDY caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
echo "restored and reloaded"
EOF
  exit 0
fi

if [ "$STOP" -eq 1 ]; then
  say "stopping the service"
  remote <<EOF
systemctl --user disable --now dawlings-noray.service || true
echo "stopped; files kept in ~/$DIR"
EOF
  exit 0
fi

# --- the bundle: noray at its pin, its packages, and bun, all built here ------------------
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
say "bundling noray $NORAY_COMMIT with bun $BUN_VERSION in $STAGE"
run git clone -q "$NORAY_REPO" "$STAGE/noray"
run git -C "$STAGE/noray" checkout -q "$NORAY_COMMIT"
run mkdir -p "$STAGE/bun" "$STAGE/bin"
if [ "$DRY" -eq 0 ]; then
  (cd "$STAGE/bun" && npm init -y >/dev/null && npm install --no-audit --no-fund "bun@$BUN_VERSION" >/dev/null)
  # The real binary, not npm's launcher: the VPS has no Node.
  cp -L "$STAGE/bun/node_modules/bun/bin/bun.exe" "$STAGE/bin/bun"
  chmod +x "$STAGE/bin/bun"
  (cd "$STAGE/noray" && "$STAGE/bin/bun" install --production --frozen-lockfile >/dev/null)
  rm -rf "$STAGE/noray/.git" "$STAGE/noray/test"
else
  echo "  would fetch bun@$BUN_VERSION from npm and run: bun install --production in noray"
fi
run cp deploy/noray/noray.env deploy/noray/dawlings-noray.service "$STAGE/"

say "copying to $HOST:~/$DIR"
run "${SSH[@]}" "$HOST" "mkdir -p ~/$DIR ~/.config/systemd/user"
run rsync -a --delete "$STAGE/noray/" "$HOST:$DIR/noray/"
run rsync -a "$STAGE/bin/" "$HOST:$DIR/bin/"
run rsync -a "$STAGE/noray.env" "$HOST:$DIR/noray.env"
run rsync -a "$STAGE/dawlings-noray.service" "$HOST:.config/systemd/user/dawlings-noray.service"

say "installing and (re)starting the service"
remote <<'EOF'
set -euo pipefail
systemctl --user daemon-reload
systemctl --user enable dawlings-noray.service >/dev/null
systemctl --user restart dawlings-noray.service
sleep 2
systemctl --user --no-pager --lines=0 status dawlings-noray.service | head -5
if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != "yes" ]; then
  echo "OWNER: lingering is off, so the service stops when the last ssh session ends."
  echo "       Run once, with sudo: sudo loginctl enable-linger $USER"
fi
for p in 8890/tcp 8809/udp; do
  ss -lntu | grep -q ":${p%/*} " && echo "listening on $p" || echo "NOT listening on $p"
done
echo "memory: $(systemctl --user show dawlings-noray.service -p MemoryCurrent --value) bytes"
if command -v ufw >/dev/null && sudo -n true 2>/dev/null; then
  sudo -n ufw status | grep -E '8890|8809|49152' || echo "OWNER: ufw is on and has no rule for noray: see docs/multiplayer.md, Firewall."
else
  echo "(firewall not checked: no passwordless sudo. Needed open: 8890/tcp, 8809/udp, 49152-49215/udp.)"
fi
EOF

# --- Caddy: the landing page, appended in place (the Caddyfile is a single-file bind mount) --
if [ "$DO_CADDY" -eq 1 ]; then
  say "adding the $NAME block to the Caddyfile (backed up first, validated before it is written)"
  BLOCK="$(cat deploy/noray/dawlings.caddy)"
  remote <<EOF
set -euo pipefail
ts=\$(date +%Y%m%d-%H%M%S)
cp -p "$CADDYFILE" "$CADDYFILE.bak.pre-dawlings-\$ts"
chmod 600 "$CADDYFILE.bak.pre-dawlings-\$ts"
cand=\$(mktemp)
chmod 600 "\$cand"
# Everything but an earlier dawlings block, then this one.
awk '/^# BEGIN dawlings-noray/{skip=1} !skip{print} /^# END dawlings-noray/{skip=0}' "$CADDYFILE" > "\$cand"
cat >> "\$cand" <<'BLOCK'

$BLOCK
BLOCK
# Only the dawlings lines of the change are shown: the rest of the file is not ours to print.
diff "$CADDYFILE" "\$cand" | grep -E '^[<>]' | awk '/dawlings-noray/{show=!show; print; next} show{print}' | head -80 || true
docker exec -i $CADDY caddy validate --adapter caddyfile --config /dev/stdin < "\$cand"
cat "\$cand" > "$CADDYFILE"
rm -f "\$cand"
docker exec $CADDY caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
for site in magic.jacobsabella.com armagetronad.jacobsabella.com; do
  printf '%s still answers: ' "\$site"
  curl -s -o /dev/null -w '%{http_code}\n' --resolve "\$site:443:127.0.0.1" "https://\$site/" || echo "no answer"
done
echo "backup: $CADDYFILE.bak.pre-dawlings-\$ts  (deploy.sh --rollback-caddy \$ts)"
EOF
fi

[ "$DRY" -eq 1 ] && { echo; echo "dry run: nothing was changed"; exit 0; }
verify
