# Refactor loop

The brief for the large refactor: make the game mod-based, make every room's layout data, and
leave every system it touches cleaner, faster and documented. Read it at the start of every pass,
do ONE slice from the queue at the bottom, and leave the queue and the log truer than you found
them.

Started with `/loop refactor: follow docs/refactor_loop.md`, under the goal below.

## The goal

**A. Mods.** Third-party DSP and instruments are mods, not hard-wired. One manifest format (id,
version, licence, source pin, ports and params, model or skin, sound source, mood hooks) and one
registry that discovers mods from `vendor/` (pinned submodules or versioned binaries only, never
copied source) and a user mods folder. The rack's Plaits, Rings, Clouds and DaisySP modules and the
DAW's plugins load through that registry, so adding a module means adding a manifest and a binding
with no edits to `studio.gd`, the rack catalogue or the tests. A bad or missing mod degrades to a
visible "unavailable" plate and never crashes. Proof: a sample mod added only as a folder appears
in the game, plays, saves and reloads, and replicates to a guest.

**B. Rooms.** Every venue's layout is data, not code: a layout file says which room, which pieces
stand where, and what is wired to what. Venues are editable in game (move, add, remove, save,
reset to default, share with the room), and a player can make a new room and choose what goes in
it. A piece is either a *single item* that can sit in any room (a small instrument, a toy, a
tablet) or a *room-scale mod* that needs its own space (the modular room), and the layout declares
which. The current venues become layout data on the same system, with the same
clear-of-each-other and reachable-from-the-middle guarantees the tests enforce today. Proof: delete
a piece from one venue, add one to another and make a new room in game, restart, and they are
still there. A guest sees them too.

**C. Quality.** Every file the refactor touches is reviewed for repetition, documentation,
performance and cleanliness, and left better. Specifically: `scenes/studio.gd` (8,445 lines at the
start) and `core/venues/venue.gd` (1,368) are broken into focused units, none over about 800 lines;
duplicated logic is merged; dead code is gone; every public class, signal and non-obvious function
has a doc comment; each system has a current page in `docs/` (what it is, how it fits, how to
extend it) and `docs/README.md` indexes them; frame-time hot spots found with the existing perf
tools are fixed or noted with numbers.

**Done when**, all shown by command output:

1. The import check prints no `SCRIPT ERROR` or `Parse Error`.
2. The full suite has no failures beyond the known list below, and the test count has not dropped
   without a reason in the log.
3. The sample-mod and new-room proofs pass as tests.
4. No file over the line limit, and no unreferenced public symbol left in the touched areas
   (checked by a script under `tools/`).
5. `docs/` has one page per system plus the index, and CI is green on master.

## Rules

- **One slice per pass**, finished end to end, one local commit, tests for the area run. Never push
  and never cut a release unless the owner says so.
- **Third-party code is pinned, not copied**: submodules under `vendor/` at an exact commit, or
  versioned binaries. Licences go in `THIRD_PARTY_NOTICES.md`. MIT-style only.
- **Game windows only through `offscreen_run`** (`. tools/offscreen.sh`), so they open on workspace
  10. Never a bare `godot --path .`.
- **Subagents run one at a time per slice**, each ending in one commit; they are briefed from this
  file and the state map, not from memory. No attribution lines in commits.
- **No behaviour change in a pure refactor slice.** If a test must change, say why in the commit.
- **The quality checklist applies to every file a slice touches**: repetition (the same table or
  loop written twice is merged), docs (a doc comment on every public thing, and the `docs/` page
  updated in the same commit), performance (measure before and after with the perf tools, numbers in
  the commit), cleanliness (dead code gone, names that say what a thing is, no stale mentions of
  removed features outside history notes).
- **The progress page** is the artifact https://claude.ai/artifact/H4LYcC3a2mZMg4APE2Tqz8 . At the
  end of every pass, edit the three JSON files (queue, log, facts), upload each with the Artifact
  tool (`asset: true`, one call per file), and `update` `datasets/<id>` with the new `source.url`,
  `updated` and `edit`. The page reads them; never republish the page for a data change.
- A removed test function is also removed from the runner list near the end of
  `tests/run_tests.gd`, or the run aborts. GDScript has no `%g`. `timeout` on every godot command.
  `.claude/`, `tmp_probe/` and `vendor/dawkit` are not ours.

## Decisions

Made by the owner, 2026-11-07. They override anything above that reads otherwise.

1. **Mods are data-only plus pinned vendor DSP.** A user mod is a manifest, a skin/model and a patch
   that uses DSP already compiled into the game. New native DSP only comes from pinned submodules or
   versioned binaries shipped with the game. No user-supplied native code (a later, opt-in extension
   point may be marked in the design, but is not designed).
2. **The rack patch is saved to disk and loaded** (a patch is a file). A missing mod shows as a visible
   "unavailable" plate, and its place and connections are preserved, never dropped.
3. **A guest who lacks a mod the host's room uses** sees an unavailable plate naming the mod and still
   hears the host's sound. No transfer, no refusal.
4. **The 800-line limit applies to `studio.gd`, `venue.gd` and every file the refactor touches**, not to
   the whole repo.
5. **Design sign-off (2026-11-07).** Built-in manifests live in `res://mods/builtin/`, pointing at
   `vendor/` by pin. The native rack engine is built for Linux, macOS and Windows; Android/Quest native
   support is dropped. Shell geometry stays in code (only placements, zones and wiring are data).
   Piece positions are per room. Editing is host-only. The rack stays room-scale (no single-item rack).
   A made room may have any subset of zones. Room sizes: small, standard and large offered by the
   maker (each size needs its own shell and placement tests; settle the shell form in slice 8).
6. **Mods.** Builtin types are renamed to `builtin.<name>` with no alias table (nothing is in use yet).
   Patches live in `user://patches/` only and the host loads them. User models: 2 MB / 20k triangles,
   decorative only, textures allowed (counted in the 2 MB). Under Reaper, unavailable plugin slots are
   Reaper's business. Packaging (.zip/.pck) comes after the sample-mod proof. A composite counts as its
   expanded modules against `MAX_MODULES`.
7. **Layouts.** `OLD_FLOOR_DEFAULTS`, `OLD_FIT_LINES` and `OLD_EQ_WALL` are dropped after one import step;
   the mixing neighbourhood's banner moves into the control-room fragment. Limits: 64 pieces and a 16 kB
   delta per room.

## Running things

```
timeout 200 godot --headless --path . --import 2>&1 | grep -E "SCRIPT ERROR|Parse Error"
DAWLINGS_TESTS=_test_a,_test_b CLAUDE_JOB_DIR=<scratchpad>/j timeout 500 godot --headless --path . tests/tests.tscn 2>&1 | grep -E "checks|FAIL|SCRIPT ERROR|Parse Error"
git checkout project.godot        # after every godot run
```

The full suite takes 20-40 minutes: run it in the background to a file, at the end of every third
slice and at the end.

## Known failures (not ours; do not fix inside a refactor slice)

As of 2026-11-07, full suite 17880 checks, 46 failed, all of:

- RackWall "no two faces share a plane" (42)
- `_test_a_monitor_goes_to_the_gear_and_leaves_the_room_alone`: "all of it is in frame", "a rack
  wheeled somewhere else is visited"
- the playhead count-in check ("from where the playhead stood")
- "every control names itself, not its node"
- `_test_a_duck_is_picked_up_squeezed_and_put_down`: "put down on the gear, it goes home instead",
  "and floats back onto its shelf"
- `_test_you_walk_into_the_room_and_not_through_it`: "the desk has a footprint to walk into" (alone)
- `_test_the_rooms_cv_bench_is_reached_from_the_wall_and_drives_the_rack` ("the bench has fifteen
  controls", out-of-bounds index 7 on `Array[Knob]`)
- GuestMidi 60 Hz throttle: take tests that depend on call parity are flaky in subsets.

## The queue

Do the first unchecked item. Break it down in the log if it is too big for one pass.

- [x] 1. **State map**: how a mod and a venue are represented today, with file and line counts
      (`docs/refactor_state_map.md`).
- [x] 2. **Design on paper**: the mod manifest, the registry, the layout file format and the piece
      kinds (single item vs room-scale mod), in `docs/mods.md` and `docs/layouts.md`. The owner reads
      them before any code (stop the loop and ask).
- [x] 3. Registry and manifest loader beside the old path, with bad-mod degradation; move one rack
      module (Plaits) onto it.
- [x] 4. Move the rest of the rack modules, then the DAW plugins. (Rack modules, presets and the
      `builtin.<name>` rename done; plugin catalogue names done; plugin skins, the unavailable plugin slot
      and Reaper's list move into items 5 and 10.)
- [ ] 5. Sample mod as a folder: appears, plays, saves, reloads, replicates (the proof test).
- [ ] 6. Layouts as data: one venue first, then all of them, keeping the placement guarantees.
- [ ] 7. In-game editing (move, add, remove, save, reset) and sharing the layout with the room.
- [ ] 8. The new-room maker, and the single-item vs room-scale split.
- [ ] 9. Split `studio.gd` and `venue.gd` as responsibilities move out of them (this happens inside
      slices 3-8, then a final sweep here until neither is over the limit).
- [ ] 10. Remove the old paths.
- [ ] 11. Docs pass: one page per system, `docs/README.md` index, code comments.
- [ ] 12. Final quality pass and the "done when" script; full suite; CI green.

## Log

(newest first; one line per pass: date, slice, commit, what changed, numbers)

- 2026-11-07 — slice 5a, patch file and keep-unknown (mods.md step 5): `RackPatch.to_dict/from_dict/problem` (format `dawlings.rack-patch`, version 2, `w`, `uses`; v1 still loads), `sanitize` keeps a module no mod provides (`missing`, place, width, knobs, cables; `playable`/`lines` keep it from the engine, `RackLayout.width_in`, a plain `<type> not installed` plate on the wall), `RackPatchFile` (read with `.bak` fallback, atomic write) and `RackAutosave` (restore at build, 1.5 s debounce, worker-thread write, host only; studio.gd +7 lines). Cost: `to_dict` 105 us main thread for a 35-module rack, text 180 us + write 130 us on the worker, `note()` 1.3 us. 5 new tests (101 checks, new file `tests/rack_patch_file_tests.gd`); 98 rack/patch/registry/plugin tests 1478 checks, only the 2 Reaper-keys checks that also fail in that subset without this change. Open: dangling cables on known modules (step 6), `uses` on the room row (step 6), named saves.

- 2026-11-07 — slice 4b, `builtin.<name>` rename and the DAW plugin catalogue: all 29 rack module types, the 17 preset patch files, the catalogue, skin, pad-knob and curve lookups, `rack_layout`/`rack_wall`/`rack_voice`, three `studio.gd` comparisons (`RackPatch.OUT_MODULE`/`WORLD_MODULE`) and the tests now use `builtin.<name>` with no alias (a bare-name patch is dropped); engine names (`modules.json`, `sound.type`, the `add` lines) unchanged, mapped by `ModRegistry.rack_engine_type`; ids stay short (`vco`, `vco2`); `tools/mods_from_legacy.py` retired (manifests are the source of truth). New mod `builtin.effects` (10 `plugin` entries, format `godot`) gives `FXCatalogue` its names; `ModRegistry.plugin_display/plugin_title/plugin_ids`, `PluginCatalogue.display_name` for scanned plugins. 69 tests that touch rack/plugin/catalogue/registry classes: 2658 checks, only the known cv-bench failure; 2 new tests. Item 4 stays open: plugin `display.skin`/`first_params`/`param_key` not applied in `RackUnit`/`PluginTablet`, no unavailable slot for a missing plugin, Reaper's `fx_choices` untouched, `plugin_not_found` not raised.
- 2026-11-07 — slice 4a, rack modules and presets on the registry: `tools/mods_from_legacy.py` writes `builtin.core`, `builtin.daisysp`, `builtin.mutable` (29 modules) and `builtin.presets` (17 presets as patch files) from the frozen old tables (`tests/fixtures/rack_legacy_tables.json`); `RackSkin.SKINS`, `PAD_KNOBS`, `RackCatalogue.GROUPS` and the preset bodies deleted (rack_patch.gd 672 -> 347 lines); new `tests/rack_mod_tests.gd` (`_test_the_manifests_equal_the_old_tables`, bad-preset-file test; old Plaits test replaced); 525 checks over 26 rack/registry tests, only the known cv-bench failure; still to do: the `builtin.<name>` rename and the DAW plugins (queue 4).
- 2026-11-07 — slice 3 step 3, Plaits on the registry: `res://mods/builtin/mutable/mod.json` (type stays `plaits`, rename to `builtin.*` is step 4), `ModRegistry.ensure_current`, catalogue/skin/pad_knobs read the registry first; new test `_test_the_registry_says_what_the_old_tables_say_for_plaits` (25 checks), 356 checks 0 failed over the rack/registry subset; shipped root is now `res://mods/builtin/`.

- 2026-11-07 — slice 2 closed: owner answers folded into docs/mods.md §11 and docs/layouts.md §13; docs only.

- 2026-11-07 — slice 1, state map: `docs/refactor_state_map.md` (mods, venues, studio.gd sections, doc and perf baselines, observations, 8 open questions); docs only, no code, no tests run.
- 2026-11-07 — loop started; brief written.
