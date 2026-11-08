# Tests

## Layout

One headless scene, `tests/tests.tscn`, runs `tests/run_tests.gd` (about 46,000 lines, 20,300 checks): a node whose
`_ready` calls every `_test_*` function in order, each making `check(name, bool)` / `close_to(name, a, b)` calls, then
prints `N checks, M failed` and each `FAIL`. Newer groups live in their own files, preloaded and called from
`run_tests.gd` (`const FooTests := preload(...)`, one `_test_*` that runs it):

| File | What |
|---|---|
| `layout_data_tests`, `layout_resolver_tests`, `layout_validator_tests`, `shell_facts_tests`, `venue_files_tests` | the layout data model, resolving and validating files, venue shell facts, the venue JSON files |
| `layout_edit_tests`, `room_delta_tests`, `room_maker_tests`, `layout_share_tests` | host edits, saved deltas, made rooms, two studios (host and guest) in one tree |
| `rack_mod_tests`, `rack_composite_tests`, `rack_gaps_tests`, `rack_patch_file_tests`, `sample_mod_proof_tests`, `mods_screen_tests`, `plugin_dress_tests` | the registry and manifests, composites, unavailable plates, patch file v2, the sample mod, the MODS list and screen, plugin skins and the unavailable plugin plate |
| `guest_live_tests` | a guest follows the host's meters, clock and modular room (`RackLive`); solo unchanged |
| `mod_share_tests` | a host's user mod is offered, accepted or declined, refused when bad, installed and live on the guest; the plugin marker reaches a guest |
| `control_room_tests`, `signal_tests`, `workshop_tests` | the control room, the signal view, the Workshop |
| `fake_noray.gd`, `fixtures/` | an in-process noray; JSON/jsonl inputs (`fixtures/layouts/`, legacy floor files, a workshop stream) |

Helpers in `run_tests.gd`: `_floor_studio()` builds a real `Studio` with a floor; most studio helpers are covered by
building `Studio.new()` and driving it. Test-only fakes (`FakeHand`, `RenderSpy`, `HistorySpy`...) are classes inside
`run_tests.gd`. The suite switches off the player's saved state (`RackAutosave.disabled`, `RoomDeltas.disabled`,
`MadeRooms.disabled`) so it never reads or writes this machine's.

## Running

**Targeted** (what to run while working): name the `_test_*` functions, comma separated, in `DAWLINGS_TESTS`:

```
DAWLINGS_TESTS=_test_a,_test_b timeout 500 godot --headless --path . tests/tests.tscn 2>&1 | grep -E "checks|FAIL|SCRIPT ERROR|Parse Error"
git checkout project.godot        # godot rewrites it
```

A name picks one function; list several for a corner of the game (`grep -n "^func _test_.*rack" tests/run_tests.gd`).
`DAWLINGS_TESTS_PROGRESS=<n>` prints a progress line every n checks.

**Import check** (a script that does not compile, with no test run; enough for a comment-only change):
`timeout 200 godot --headless --path . --import 2>&1 | grep -E "SCRIPT ERROR|Parse Error"`.

**Everything, in parallel (use this)**: `tools/test_parallel.sh [N]` (default 4 shards) runs the whole scene as N godot
processes, merges their output and prints one line: `shards 4: 20289 checks, 50 failed (48 known, 2 new), 132s wall`.
It exits non-zero on a failure that matches no line of `tests/known_failures.txt`, a shard that did not finish, or a
`SCRIPT ERROR`. How it works:

- `DAWLINGS_SHARD=i/n` (i from 1) makes `run_tests.gd` run only its share. Every `_test_*` call in `_ready` is
  `await _t("name")`; `_t` skips the tests that are not this shard's and times the rest. The share is dealt longest
  first onto the lightest shard by the seconds in `tests/test_times.txt` (regenerate it from a `DAWLINGS_TIMES` run:
  `name seconds checks` per line), so the shards finish together. The source and that file decide the deal; every
  shard computes the same one. A new test not in the file counts as the median.
- `DAWLINGS_TIMES=path` appends `name seconds checks` for each test as it finishes (the script merges the shards'
  files into one, slowest first). It works with `DAWLINGS_TESTS` too.
- Each shard gets its own `XDG_DATA_HOME` (so its `user://`), `XDG_CACHE_HOME` (the helpers' pipes), `XDG_CONFIG_HOME`
  and `CLAUDE_JOB_DIR`, and its own block of ports: the tests that open the stand-in noray and ENet ports add
  `_port_shift` (100 per shard) to 18809, 18832-18836 and 18890. The keys helper is copied in from this machine's build
  so no shard compiles it.
- Anything a test writes to a fixed place must stay under `user://` or the cache dir, or take a shard-unique name.
  `tests/workshop_tests.gd` writes `shots/tmp/workshop_test` and a throwaway repo under `user://`; nothing else
  writes under the project.
- The "Rig Roulette is off" check runs in shard 1 only, so the checks add up to the serial count.

**Timings** (2026-11-07, 32 cores): 784 test functions, 20,289 checks. Serial CPU total 660 s before the trim, 481 s
after (sum of the per-test seconds). Wall: 296 s on 6 shards before (the slowest test, the plane-sharing scan, took
222 s and was the floor), 132 s on 4 shards after. Slowest now: the plane-sharing scan (55 s, 42 venue variants), the
struck-sounds helper (31 s, it synthesises every sound), `every_venue_keeps_its_pieces_apart` (28 s), a rope ducking
a render (19 s), the mix and stems render (13 s); the rest is a flat tail under 9 s each. Per-test numbers:
`tests/test_times.txt`.

**One process**: `tools/verify.sh` (builds the native core first, then runs the whole scene, non-zero on any failure or
`SCRIPT ERROR`). The suite takes tens of minutes now; the "90 s" in the script's own comment is stale. The refactor
loop runs it only at item 12 (`docs/refactor_loop.md`).

Never run a game window from a test; a window goes through `offscreen_run` (`docs/tools.md`).

## CI

`.github/workflows/ci.yml` builds the native core and runs the import on every push to a non-master branch; the suite
runs only when the repository variable `RUN_TESTS` is `true` (off since 2026-10-30). `release-check.yml` reuses it for
pull requests and master; `release-stable.yml` releases.

## Known failures

Listed with their cause in `docs/refactor_loop.md` ("Known failures") and, as substrings `tools/test_parallel.sh`
matches, in `tests/known_failures.txt`: 50 of 20,289 at the last sharded run (42 are the RackWall "no two faces share a
plane" scan; 9 pass alone and fail only when the tests run as a subset, which sharding is). A new failure is yours until shown otherwise: check it against the
pre-change code in a throwaway worktree.

## How to add a test

1. Name the behaviour: `func _test_a_guest_sees_the_hosts_edit() -> void:`; the function name is the sentence.
2. Use `check("what is true", cond)`; build what you need (`Studio.new()`, `_floor_studio()`, a `Session` with fakes).
3. Call it from `_ready` in `run_tests.gd` (a group that belongs to one system goes in its own `tests/*_tests.gd`,
   preloaded, with one `_test_*` that runs it).
4. Run it alone with `DAWLINGS_TESTS=` and then with the neighbouring tests that touch the same code.
