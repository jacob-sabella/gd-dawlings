#!/usr/bin/env bash
# Run the whole headless suite as N parallel godot processes and print one summary.
#
#   tools/test_parallel.sh [N]            N shards (default 4)
#   DAWLINGS_TIMES=out.txt tools/test_parallel.sh   also write "name seconds checks" for every test
#
# Each shard is `DAWLINGS_SHARD=i/N` (tests/run_tests.gd): the tests are dealt out by the seconds in
# tests/test_times.txt so the shards finish together. A shard has its own user-data, cache and job
# directories and its own block of TCP/UDP ports, so none collide. Exits non-zero when any failure
# is not matched by a line of tests/known_failures.txt (a substring of the FAIL label), when a shard
# did not finish, or on a SCRIPT ERROR.
set -uo pipefail
cd "$(dirname "$0")/.."
n="${1:-4}"
work="$(mktemp -d "${TMPDIR:-/tmp}/dawlings_shards.XXXXXX")"
start=$(date +%s)
pids=()
for i in $(seq 1 "$n"); do
  d="$work/shard$i"; mkdir -p "$d/data" "$d/cache" "$d/config" "$d/job"
  # The keys helper (native/keys.c) is compiled into user://bin on first use, ~30 s; start each shard with
  # this machine's build (its mtime says whether it is current).
  ud="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/dawlings"
  if [ -x "$ud/bin/keys" ]; then mkdir -p "$d/data/godot/app_userdata/dawlings/bin"; cp -p "$ud/bin/keys" "$d/data/godot/app_userdata/dawlings/bin/"; fi
  (
    export XDG_DATA_HOME="$d/data" XDG_CACHE_HOME="$d/cache" XDG_CONFIG_HOME="$d/config" CLAUDE_JOB_DIR="$d/job"
    export DAWLINGS_SHARD="$i/$n"
    [ -n "${DAWLINGS_TIMES:-}" ] && export DAWLINGS_TIMES="$d/times.txt"
    timeout "${SHARD_TIMEOUT:-7200}" godot --headless --path . tests/tests.tscn >"$d/out.txt" 2>&1
    echo $? >"$d/status"
  ) &
  pids+=($!)
done
wait "${pids[@]}"
wall=$(( $(date +%s) - start ))

checks=0; failed=0; bad=0
: >"$work/fails.txt"
for i in $(seq 1 "$n"); do
  d="$work/shard$i"
  line="$(grep -E '^[0-9]+ checks, [0-9]+ failed' "$d/out.txt" | tail -1)"
  if [ -z "$line" ]; then echo "shard $i did not finish (status $(cat "$d/status" 2>/dev/null)); see $d/out.txt"; bad=1; continue; fi
  c="${line%% checks*}"; f="${line#*, }"; f="${f%% failed*}"
  checks=$((checks + c)); failed=$((failed + f))
  grep -E '^  FAIL  ' "$d/out.txt" | sed 's/^  FAIL  //' >>"$work/fails.txt"
  grep -E '^(SCRIPT ERROR|ERROR: Failed to load script)' "$d/out.txt" | sed "s/^/shard $i: /"
done
if grep -qhE '^(SCRIPT ERROR|ERROR: Failed to load script)' "$work"/shard*/out.txt; then bad=1; fi

known=tests/known_failures.txt
grep -v '^#' "$known" 2>/dev/null | grep -v '^$' >"$work/patterns.txt" || true
new=0; known_n=0
: >"$work/new.txt"
while IFS= read -r label; do
  if [ -s "$work/patterns.txt" ] && grep -qF -f "$work/patterns.txt" <<<"$label"; then known_n=$((known_n + 1))
  else echo "  NEW FAIL  $label" >>"$work/new.txt"; new=$((new + 1)); fi
done <"$work/fails.txt"
cat "$work/new.txt"

if [ -n "${DAWLINGS_TIMES:-}" ]; then
  cat "$work"/shard*/times.txt 2>/dev/null | sort -k2 -n -r >"$DAWLINGS_TIMES"
fi
git checkout project.godot 2>/dev/null
echo "shards $n: $checks checks, $failed failed ($known_n known, $new new), ${wall}s wall; logs in $work"
[ "$new" -eq 0 ] && [ "$bad" -eq 0 ]
