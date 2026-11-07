# Tests

## Layout

One headless scene, `tests/tests.tscn`, runs `tests/run_tests.gd` (about 46,000 lines, 17,900 checks): a node whose
`_ready` calls every `_test_*` function in order, each making `check(name, bool)` / `close_to(name, a, b)` calls, then
prints `N checks, M failed` and each `FAIL`. Newer groups live in their own files, preloaded and called from
`run_tests.gd` (`const FooTests := preload(...)`, one `_test_*` that runs it):

| File | What |
|---|---|
| `layout_data_tests`, `layout_resolver_tests`, `layout_validator_tests`, `shell_facts_tests`, `venue_files_tests` | the layout data model, resolving and validating files, venue shell facts, the venue JSON files |
| `layout_edit_tests`, `room_delta_tests`, `room_maker_tests`, `layout_share_tests` | host edits, saved deltas, made rooms, two studios (host and guest) in one tree |
| `rack_mod_tests`, `rack_composite_tests`, `rack_gaps_tests`, `rack_patch_file_tests`, `sample_mod_proof_tests` | the registry and manifests, composites, unavailable plates, patch file v2, the sample mod |
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

**Everything**: `tools/verify.sh` (builds the native core first, then runs the whole scene, non-zero on any failure or
`SCRIPT ERROR`). The suite takes tens of minutes now; the "90 s" in the script's own comment is stale. The refactor
loop runs it only at item 12 (`docs/refactor_loop.md`).

Never run a game window from a test; a window goes through `offscreen_run` (`docs/tools.md`).

## CI

`.github/workflows/ci.yml` builds the native core and runs the import on every push to a non-master branch; the suite
runs only when the repository variable `RUN_TESTS` is `true` (off since 2026-10-30). `release-check.yml` reuses it for
pull requests and master; `release-stable.yml` releases.

## Known failures

Listed with their cause in `docs/refactor_loop.md` ("Known failures"): 46 of 17,880 at the last full run (42 are
the RackWall "no two faces share a plane" scan). A new failure is yours until shown otherwise: check it against the
pre-change code in a throwaway worktree.

## How to add a test

1. Name the behaviour: `func _test_a_guest_sees_the_hosts_edit() -> void:`; the function name is the sentence.
2. Use `check("what is true", cond)`; build what you need (`Studio.new()`, `_floor_studio()`, a `Session` with fakes).
3. Call it from `_ready` in `run_tests.gd` (a group that belongs to one system goes in its own `tests/*_tests.gd`,
   preloaded, with one `_test_*` that runs it).
4. Run it alone with `DAWLINGS_TESTS=` and then with the neighbouring tests that touch the same code.
