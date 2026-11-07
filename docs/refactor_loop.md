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

The full suite takes 20-40 minutes. **Owner instruction (2026-11-07): do NOT run it until the very end
(item 12).** Every slice runs only its targeted tests (`DAWLINGS_TESTS=...`, in chunks of about 20) plus the
import check. Last full run: 19411 checks, 46 failed, all known, at `4189d52`.

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
- Subset-only flakes (pass alone, depend on test order): the COLOUR palette check, three `x -5.33`
  walking checks, the instrument keys-box "hidden for an ordinary host on Reaper" checks.
- 21 tour-chaos and brief checks fail identically on a clean checkout of `c702838^` (seen in 6f).
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
- [x] 5. Sample mod as a folder: appears, plays, saves, reloads, replicates (the proof test).
- [x] 6. Layouts as data: one venue first, then all of them, keeping the placement guarantees.
- [x] 7. In-game editing (move, add, remove, save, reset) and sharing the layout with the room.
- [x] 8. The new-room maker, and the single-item vs room-scale split.
- [ ] 9. Split `studio.gd` and `venue.gd` as responsibilities move out of them (this happens inside
      slices 3-8, then a final sweep here until neither is over the limit).
      Progress: slice 9a moved four blocks out of `studio.gd` (8046 -> 6459 lines); `venue.gd` is
      untouched (1270). Still to do: `studio.gd` ~5700 lines over the limit (next blocks: tablets and
      track racks, the signal/look-solo/trace views, stations and the walk/sit code, `_build_*`
      furniture, `apply_room`/`_on_room_asked`), and all of `venue.gd`.
- [ ] 10. Remove the old paths.
- [ ] 11. Docs pass: one page per system, `docs/README.md` index, code comments.
- [ ] 12. Final quality pass and the "done when" script; full suite; CI green.

## Log

(newest first; one line per pass: date, slice, commit, what changed, numbers)

- 2026-11-07 — slice 9a, item 9 (first split of `studio.gd`), no behaviour change: 103 methods moved out of `scenes/studio.gd` into four `RefCounted` helpers in the `PieceHost` pattern (`var studio: Studio`, state stays on the studio, which keeps a one-line delegate only for a method other files call or `tools/screenshot.gd` probes by name; calls inside the studio go straight to the helper). `RollRoom` (`core/rig_roulette/roll_room.gd`, 394 lines: roll board, setup wall, presets, rolling, undo), `TourRoom` (`core/tour/tour_room.gd`, 404: case, run, spills, chaos, crowd), `ItemHost` (`core/items/item_host.gd`, 636: item homes, building the items, minting, giving, weather, looper), `PatchHost` (`core/session/patch_host.gd`, 402: plugs, patch cables, wrist jacks, ON AIR). A signal on an autoload (`Session`, `Tour`) or a lambda handed to `Session` now outlives its studio (the helper is not a node, so the engine no longer drops the connection), so each such handler begins with an `is_instance_valid(studio)` guard. Numbers: `studio.gd` 8046 -> 6459 lines; `venue.gd` 1270 unchanged. Tests: 126 targeted (roulette, roll, tour, spill, chaos, jack, plug, on-air, looper, weather, give, mint, personal, crowd, paste) in 7 chunks, all pass (3,142 checks) except the 6 known tour-chaos checks, which fail identically on the pre-slice code (the two "state on previously freed" script errors in the roulette chunk also appear before the slice); (see above).

- 2026-11-07 — slice 8, layouts design step 11 (the new-room maker, the two classes of piece): a player makes a room from `RoomMaker` (F4, host only): small/standard/large, any subset of the zones that fit, the singles to keep, the look, and the modular room as its own room-scale line. `MadeRoom` writes it as layout data (`shell.builder` "BoxVenue"), checks it with the parser and `LayoutValidator` (64 pieces, 16 kB), `MadeRooms` keeps it in `user://layouts/made/` and scans it into the same `LayoutSet` as the shipped rooms, so `VenueCatalogue`/`Venue.make` find it and a restart reopens it; `room_state` carries it in a `made_room` row and a guest adopts it in memory only. `PieceDef.Kind` is enforced: a layout cannot state a `class`, a room-scale piece cannot be wheeled or added from the floor, `modular_annex` has its own `PieceDef` (`Mount.SITE`, limit 1, claims) and `PieceBuilders` names the node classes. New: `BoxVenue`, `BoxStyle`, `MadeRoom`, `MadeRooms`, `PieceBuilders`, `RoomMaker`, `tests/room_maker_tests.gd` (2 tests, 39 checks incl. 83 size x zone-subset rooms). Fixes on the way: `Venue.hoop_spot/tour_case_spot/cassette_rack_spot` fall back to the shared live room for a piece a layout switched off, `PieceHost.stand` and the venue's own hoop honour it, `ZoneKit.solids` tolerates missing zones; venue_files test now expects the 16th builder. 2 new + 40 layout/delta/share/validator/venue-file tests + 23 solid/hoop/venue/annex tests: 39 + 1761 + 217 + 154 + 6187 checks, 0 failed after the venue_files fix; import check clean. studio.gd 8041 -> 8046, venue.gd 1250 -> 1270. Next: item 9.
- 2026-11-07 — slice 7c, layouts step 10 (sharing) and a wider catalogue: two-instance tests (`tests/layout_share_tests.gd`: a host Studio and a guest Studio in the tree together, the row from `room_state()` into `apply_room`): the guest holds the host's delta, stands the added hoop, does not stand the removed pieces, is told `HOST_ONLY` to remove/add/rotate/reset, may still push, and one host `reset all` returns it to the defaults. An added piece this build cannot make (a mod's) is a `PieceGap` named plate in its place (`RoomSync._gaps`; the entry stays in the delta; odd or absurd entries mended, never a crash). `PieceCatalogue.REMOVABLE` 3 -> 7: the wheel, section blocks, looper and lyric board (`ZONED`: removed by `PieceHost.unstand`, put back by `add`/`reset` with no spot, refused where the venue has no zone). Copies stay the hoop's alone: the drum plaque (hand-drum items read the ring), the venue's instrument and weather, Tour case, prop shelf, control-room furniture and every item (toys, small instruments, tablets are replicated `ItemRoom.KINDS`, not pieces) are out, reasons in layouts.md 7. Brief proof so far: delete in one venue, add in another, restart, a guest sees both (`_test_deleting_and_adding_a_piece_survives_a_restart`); the new-room part is item 8. 5 new tests (62 checks); 72 layout/delta/piece/trolley/hoop/rack/looper/lyric/wheel/section tests plus 12 neighbourhood/venue-file/layout/room-state tests: 2069 + 1250 checks, 0 failed; import check clean. studio.gd 8041 -> 8041. Next: item 8 (new-room maker, single-item vs room-scale split, `modular_annex` as a piece).
- 2026-11-07 — slice 7b, layouts step 9 (edit ops, building, the F3 panel): `Studio.ask_layout` / room verb `layout` (`LayoutEdit`: move, rotate, add, remove, reset; host only, a guest is told so except for pushing wheeled pieces; each op tried on a `RoomDelta.copy()`, checked by `LayoutValidator` against the room's `ShellFacts` for any new error, add retried at `nearest_clear`, then `RoomDeltas.commit` + `RoomFloor.follow` + publish), `PieceCatalogue` (rack, sampler, hoop removable; hoop addable to 4), `RoomSync` (copies built as trolley + `Hoop` node by `PieceHost.equip`; removed pieces hidden and un-stood via `PieceHost.unstand`; `_wheel_in_live_pieces` moved here), `LayoutEditor` (F3, host only, bootstrap.gd). Not done: other kinds addable, prop shelf / Tour case not removable, no station-board or VR entry. 6 new tests (`tests/layout_edit_tests.gd`, 69 checks) plus targeted layout/delta/piece-host/venue-file subsets (1869 checks) green; no full suite per owner. studio.gd 8060 -> 8041 lines.
- 2026-11-07 — slice 7a, layouts step 8 (room delta, the `layout` row, persistence, floor import): new `RoomDelta` (moved/added/removed over a venue's resolved layout, `apply`, `problem`, `from_dict` mending, 16 kB `fits`), `RoomDeltaFile` (`user://layouts/rooms/<venue>.<variant>.delta.json`, atomic write with `.bak` via `RackPatchFile.write_text`, `.bad` set-aside), `RoomDeltas` (`Studio.room_deltas`: per-room, in-memory cache, debounced 1 s worker write, host only, `adopt` for a guest) and `RoomFloor` (the studio's trolleys against the delta); `FloorImport.into_room` moves the remaining saved `floor/*` spots into the current room once (`LayoutProfile.floor_moved`). The `floor` row of `room_state` is now `layout {room, base, variant, rev, moved, added, removed}`; a guest adopts it and follows (`RoomFloor.follow`). Unknown or unavailable pieces are flagged, never dropped; a corrupt, oversized or newer file degrades to the defaults and says so. A player's own stands/racks stay in the profile. Existing tests changed (the floor row became the layout row; three profile-key checks read the delta; the fresh-studio check in `_test_what_stands_on_its_own_is_pushed_about_too` now writes to a test folder), no expectation of behaviour changed. studio.gd 8099 -> 8060. 6 new tests (`tests/room_delta_tests.gd`, 65 checks); targeted subsets in chunks of 20 plus earlier chunks: failures only the known tour-chaos/brief ones and cv-bench fifteen controls; import check clean. Not done: no editing UI or `ask_layout` (step 9), no `added` piece is built in the room yet (only carried and flagged), made-room files (step 12), control-room furniture is not re-stood on a venue change. Next: step 9.
- 2026-11-07 — slice 6g, layouts step 7 (the 14 venue files and the roulette room), no behaviour change: `layouts/venues/<id>.layout.json` for all 14 venues and `roulette` (id, title, `order`, `extends` both common fragments, `shell.builder`, `mood`, `variants`; the studio keeps its shelf variant, no other venue overrides a placement); new `VenueCatalogue` (`ids`, `title_of`, `variant_titles`, `builder_of`, `mood_of`) and `ShellBuilders.BY_NAME` (the one list kept while shells are code). `Venue.IDS` (now a static var from `order`), `VARIANTS`, `make_title`'s 14-arm match, `make`'s match and `RackMood.MOODS` deleted, dumped first to `tests/fixtures/layouts/venue_tables_legacy.json` (mood colours are now bytes, within 1/255). `LiveRoom.spots` leaves the control room's pieces out (the venue files extend that fragment; `default_spot(mini_table)` moved the mini table until it did), `PieceFeet.mounted` covers control-room kinds, `tools/light_check.sh` reads the files instead of grepping venue.gd. `_test_every_layout_is_valid` and `LayoutResolverTests.room` now resolve the 15 shipped files (86 runs, 0 errors, the same 10 warnings). venue.gd 1324 -> 1250, studio.gd 8099 -> 8099 (nothing venue-table-like is left in it; its mass is rack, tablets, session). 2 new tests (`tests/venue_files_tests.gd`). 114 placement/venue/mood/title/station/layout/neighbourhood/tour/piece tests in 6 chunks: 11407 checks, 21 failed, all the tour-chaos/brief ones, identical at HEAD in a throwaway worktree (17 + 4); import check clean. Not moved: venue `instrument()`/`weather()` specs (built from each shell's own constants), `lyrics`, the `Stations` text rows (class constants), `rig_roulette_spot`, zones (the shells report them), the annex. Next: step 8 (room delta and the `layout` row).
- 2026-11-07 — slice 6f, layouts step 6 part 3 (control-room fragment, `Neighbourhoods` as groups, the one floor import), no behaviour change: `layouts/common/control_room.layout.json` places the eight trolleys of `Studio._build_furniture` (stage, EQ wall, deck, rack, patch stand, patch wall, station board, mini table; stage table and platter as `rides` wires) and the MIXING group with its banner; new placement key `fit` (the rack's and deck's spots for the thirteen-track desk, read by `SessionLayout.fit`), group key `banner`, anchor `height.control_header`, public `LayoutResolver.place`; `ControlRoom` loads it, `Studio._authored` builds from it. `Neighbourhoods.ALL`, `MIXING_ABOVE/OUT`, `STAGE_AT`, `EQ_WALL_*`, `_eq_wall_at`, `PATCH_STAND_*`, `BOARD_*`, `MINI_TABLE_*`, `_patch_wall_default` and `SessionLayout`'s `RACK/DECK/PATCH_AT/HEADING` deleted; `Neighbourhoods.all()` reads the groups (rhythm, harmony, vocals added to live_room; `lyrics` listed there with no `at`). Import: `OLD_FLOOR_DEFAULTS/OLD_FIT_LINES/OLD_EQ_WALL`, `was_an_old_default` and its two per-build calls are gone; `FloorImport.run` (data `layouts/import/floor_v1.json`, marker `LayoutProfile.floor_import`) forgets old saved spots once before `_build_furniture`. Frozen fixture `control_room_legacy.json` (dumped from HEAD before deleting): trolleys at 4 widths, fit for 5 desks, old rows, banner frame, 4536 old-default probes. studio.gd 8170 -> 8099, venue.gd 1324 -> 1324 (nothing in it could move: the station spots read the trolleys, levels/tv depend on the built wall). Existing tests changed (named constants replaced by the layout equivalents, no expectation changed): `Studio.BOARD_AT/_patch_wall_default/EQ_WALL_IN/STAGE_AT/was_an_old_default`, `SessionLayout.*_AT/DECK_HEADING`, `Neighbourhoods.ALL` -> `all()`, and one count (live_room has 10 listed pieces). 3 new tests. Targeted subsets (191 placement/station/neighbourhood/furniture/reach/tour/item/layout/walk tests, no full run): the failures are the known ones plus 17+4 tour-chaos/brief checks identical at HEAD and an instrument keys-box check that passes alone; layout subset 1054 checks 0 failed; import check clean. Not moved: levels, tv, timeline stand, lamps (see layouts.md 4.1). Next in step 6: the `Stations` text rows.
- 2026-11-07 — slice 6e, layouts step 6 part 2 (zone-mounted pieces and `PieceHost.stand`), no behaviour change: `PieceDef` gains `mount` and seven definitions (wheel, sections, drums, looper, lyrics, venue, weather); `PieceHost.stand/stand_all` replace nine `_stand_the_*` of studio.gd (wheel, sections, cassette rack, sampler, drum circle, looper, lyrics, venue instrument, weather); wheel, sections, drums and looper are placed by `layouts/common/live_room.layout.json` through two new `at` keys (`up`: metres or an anchor, `height.table`/`zone.<id>.floor`; `yaw` as `{toward, snap}`), and `Venue.wheel_spot/sections_spot/drum_circle_spot(-1)/looper_spot` read it (`band_spot` deleted). Frozen fixture `zone_pieces_legacy_spots.json` (dumped from HEAD before the change): 336 transforms + 8 roulette nulls equal. studio.gd 8342 -> 8170, venue.gd 1339 -> 1324. Three existing layout-test checks changed because the fragment now has nine pieces (`all.size() == 9`; wheeled five of nine; the roulette room leaves out 10 warnings = sampler plus the four zone pieces, at two widths); no Studio placement test touched. 2 new tests; 199 placement/station/neighbourhood/reach/tour/item/layout/walk tests: 12320 checks, 8 failed in my tree, of which 3 were my own test slips (fixed, layout subset 1562 checks 0 failed) and 5 identical to the same subset at HEAD (11957 checks: COLOUR next colour, cv-bench fifteen controls, three `x -5.33` walk checks; all order-dependent, pass or are known in isolation); import check clean. Not moved: lyrics (reads the mic stand node), the venue's instrument and weather (the shell's spot, step 7), the modular rack/annex (scaled transform, step 11), the control-room furniture rows, the `Stations` text rows, `Neighbourhoods`. Next in step 6: the control-room fragment and `Neighbourhoods`.
- 2026-11-07 — slice 6d, layouts step 6 part 1 (piece definitions), no behaviour change: new `PieceDef` (`core/layouts/piece_def.gd`: kind, trolley name, footprint, top, weight, grips, pole body, needs, node, followers; numbers read from the classes' constants) and `PieceHost` (`core/layouts/piece_host.gd`, `Studio.pieces`: `build`, `carry`, `rehome_items`, `rehome_spills`, `hold_the_rack`); `Studio.LIVE_TROLLEYS`, the five `_carry_live` arms (rack, sampler, case, shelf, hoop) and the three rehome/hold functions deleted from studio.gd; `PieceFeet` reads `PieceDef`. studio.gd 8451 -> 8342, venue.gd 1339 (untouched). 2 new tests (`_test_the_piece_definitions_are_the_classes_own_numbers`, `_test_a_defined_piece_carries_its_followers`); 150 placement/trolley/carry/reach/neighbourhood/tour/item/layout tests with them: 11429 checks, 1 failed (the known cv-bench one; identical subset at HEAD: 11414, 1 failed); import check clean. Next in step 6: the rest of `Stations.ALL`, zone-mounted pieces, control-room fragment, `Neighbourhoods`, `PieceHost` replacing `_stand_the_*`.
- 2026-11-07 — slice 6c, layouts step 5 (layouts.md 11), no behaviour change: `Venue.default_spot` and the five `default_*_spot` read the layout through new `LiveRoom` (scan once, cached; `ShellFacts.anchors_of`; per-venue cache keyed on arrangement and width); `Venue.WHEELED` is derived from the fragment (file order kept = trolley build order); studio's shelf override and `BESIDE_TOYS_IN` deleted for the variant entry of `layouts/venues/studio.layout.json`; `TOYS_IN`, `HOOP_ALONG`, `TOUR_CASE_ALONG`, `RACK_GAP`, `SAMPLER_RING`, `_toys_wall` and the formula bodies deleted. The 428-transform test is a regression check against the frozen `tests/fixtures/layouts/live_room_legacy_spots.json` (dumped before deleting). venue.gd 1368 -> 1339, studio_venue.gd 1244 -> 1230, studio.gd 8451 -> 8451 (untouched). 56 placement/venue/neighbourhood/tour/item/carry/layout tests: 8856 checks, 2 failed, both on the known list (monitor `all of it is in frame`, rack visited); import check clean. Not switched: `Studio.LIVE_TROLLEYS` (footprints from class constants, no layout field until piece definitions) and the five `_carry_live` arms (followers, not positions): both wait for step 6. Next: step 6.
- 2026-11-07 — slice 6b, layouts steps 3-4 (layouts.md 11), no game change, venue.gd and studio.gd untouched: `LayoutResolver` (anchors and frames to Transform3D), shipped `layouts/common/live_room.layout.json` (the five wheeled pieces, `feeds`, groups synth and tape; hoop and tour_case in the shelf's frame so Studio-beside needs one variant), `LayoutValidator` with `LayoutChecks`, `LayoutIssue` (17 codes), `LayoutReach`, `LayoutGeometry`, `PieceFeet`, and `ShellFacts.can_cut`. Tests in `tests/layout_resolver_tests.gd` and `tests/layout_validator_tests.gd`: `_test_the_layout_resolves_to_the_venues_own_defaults` (428 transforms equal `Venue.default_spot` within 1e-4, 2 null samplers), `_test_a_placement_is_anchors_plus_an_offset_or_a_frame`, `_test_every_layout_is_valid` (43 rooms x 2 widths, annex included, 0 errors, 2 warnings), `_test_the_validator_names_each_seeded_violation`; 14 placement-related tests green, 6408 checks, import check clean. Deviations recorded in layouts.md 5.2 and 6. Next: step 5, switch the five (`default_*_spot`, WHEELED, LIVE_TROLLEYS and `_carry_live` read the layout).
- 2026-11-07 — slice 6a, layouts steps 1-2 (layouts.md 11), no game change: `core/layouts/` `LayoutData` (parse, 14 problem codes via `LayoutProblem`, field rules in `LayoutCheck`), `LayoutMerge` (objects by key, null removes, `pieces`/`groups` by id, `wiring` by kind|from|to, `at` replaces whole, `enabled:false` settled last) and `LayoutSet` (scan, `extends` fragments, one variant, whole-room checks, 64-piece limit); `layouts/layout.schema.json`; fixtures `tests/fixtures/layouts/` (a working set of 6 and 15 bad files); `ShellFacts` (rooms, zones, shell solids without the wheeled pieces, anchors) read from a venue never put in a tree. Found: no fact needs `_ready` (only `lyrics_spot`/`mic_spot`/`hoops` read nodes, none is a fact); un-readied equals built for 43 combinations x 2 widths and equals the venue in a real Studio. 7 new tests in `tests/layout_data_tests.gd` and `tests/shell_facts_tests.gd`, 530 checks, 0 failed; `_test_every_venue_leaves_room_for_the_activities` 3643 checks 0 failed; import check clean. Layouts.md records the deviations (dotted ids, null removes, atomic `at`, wire identity). Next: step 3, `LayoutResolver`.
- 2026-11-07 — slice 5d, the proof (mods.md step 9): `mods_examples/dawlings.sample.pluck/` (mod.json as 3.5, README; folder only, excluded from export via `mods_examples/*`) and `tests/sample_mod_proof_tests.gd` (`_test_a_sample_mod_dropped_in_a_folder_appears_plays_saves_reloads_and_replicates`, 30 checks): copied to a temp user root and scanned via `default_roots`; appears (registry, catalogue, ADD list, preset, skin), plays (engine render equals the hand patch, plucked, silent without a note), saves and reloads (file, fresh Studio, folder removed and back, same bytes), replicates (guest with the mod: real plate; without: named plate, no engine, host's sound). Also fixed the stale bare-name check in `builtin_types_are_prefixed...` to the keep-unknown behaviour. 140 rack/patch/registry/guest/mod/plugin tests, 2191 checks, 0 failed; import check clean.
- 2026-11-07 — slice 5c, composite modules (mods.md step 7): new `RackModuleDef` (scan-time `resolve`: interface, depth <= 3, cycles, inner types, jacks, knobs, cost; engine snapshot reader) and `RackExpansion` (play-time `expand` to `<instance>~<inner>` ids with fan-out cables and routed knobs, `cost`, `meter_map`); the registry drops a bad composite as `composite_invalid` (unavailable plate through the step-5 stranger path, reason in `RackGaps.plate_text`); the catalogue lists good ones; `MAX_MODULES` is counted on the expansion in `add`, the `add` verb and `sanitize`; `RackVoice` diffs the expanded patch and folds `meter_from` into the plate's lamp; plain patches go through untouched. 10 new tests in `tests/rack_composite_tests.gd` (fixtures under `tests/fixtures/mods/composite/`), 119 checks, plus 43 rack/patch/registry/plugin tests: 802 checks, failures only the known cv-bench one and `_test_builtin_types_are_prefixed...` ("a bare name is not carried", stale since slice 5a, fails at HEAD too, not fixed here). Sample mod and proof test are the next slice (step 9).
- 2026-11-07 — slice 5b, unavailable plate and guests (mods.md step 6): new `RackGaps` (plate title/note/sentence from `uses`, `keep_cable`/`dangling`, `problems`, `published`) and `RackStubs` (red stub for a cable on a port a known module lost, grey for one to an absent module, with a take-out key); `sanitize` keeps dangling cables and `playable` keeps them from the engine; `room_state` publishes the rack row with `uses` for every type (studio.gd +0 lines net, one call changed); wall prints the mod name on the plate. 4 new tests (34 checks, `tests/rack_gaps_tests.gd`) incl. `_test_a_guest_without_the_mod_sees_a_named_plate_and_hears_the_host`; one old check changed (a cable on a lost port is now kept, not dropped); 141 rack/patch/guest/session/plugin tests 2131 checks, only the known cv-bench and the 2 Reaper-keys subset failures. Open: unavailable DAW plugin slot, nothing shows `RackGaps.problems`.

- 2026-11-07 — slice 5a, patch file and keep-unknown (mods.md step 5): `RackPatch.to_dict/from_dict/problem` (format `dawlings.rack-patch`, version 2, `w`, `uses`; v1 still loads), `sanitize` keeps a module no mod provides (`missing`, place, width, knobs, cables; `playable`/`lines` keep it from the engine, `RackLayout.width_in`, a plain `<type> not installed` plate on the wall), `RackPatchFile` (read with `.bak` fallback, atomic write) and `RackAutosave` (restore at build, 1.5 s debounce, worker-thread write, host only; studio.gd +7 lines). Cost: `to_dict` 105 us main thread for a 35-module rack, text 180 us + write 130 us on the worker, `note()` 1.3 us. 5 new tests (101 checks, new file `tests/rack_patch_file_tests.gd`); 98 rack/patch/registry/plugin tests 1478 checks, only the 2 Reaper-keys checks that also fail in that subset without this change. Open: dangling cables on known modules (step 6), `uses` on the room row (step 6), named saves.

- 2026-11-07 — slice 4b, `builtin.<name>` rename and the DAW plugin catalogue: all 29 rack module types, the 17 preset patch files, the catalogue, skin, pad-knob and curve lookups, `rack_layout`/`rack_wall`/`rack_voice`, three `studio.gd` comparisons (`RackPatch.OUT_MODULE`/`WORLD_MODULE`) and the tests now use `builtin.<name>` with no alias (a bare-name patch is dropped); engine names (`modules.json`, `sound.type`, the `add` lines) unchanged, mapped by `ModRegistry.rack_engine_type`; ids stay short (`vco`, `vco2`); `tools/mods_from_legacy.py` retired (manifests are the source of truth). New mod `builtin.effects` (10 `plugin` entries, format `godot`) gives `FXCatalogue` its names; `ModRegistry.plugin_display/plugin_title/plugin_ids`, `PluginCatalogue.display_name` for scanned plugins. 69 tests that touch rack/plugin/catalogue/registry classes: 2658 checks, only the known cv-bench failure; 2 new tests. Item 4 stays open: plugin `display.skin`/`first_params`/`param_key` not applied in `RackUnit`/`PluginTablet`, no unavailable slot for a missing plugin, Reaper's `fx_choices` untouched, `plugin_not_found` not raised.
- 2026-11-07 — slice 4a, rack modules and presets on the registry: `tools/mods_from_legacy.py` writes `builtin.core`, `builtin.daisysp`, `builtin.mutable` (29 modules) and `builtin.presets` (17 presets as patch files) from the frozen old tables (`tests/fixtures/rack_legacy_tables.json`); `RackSkin.SKINS`, `PAD_KNOBS`, `RackCatalogue.GROUPS` and the preset bodies deleted (rack_patch.gd 672 -> 347 lines); new `tests/rack_mod_tests.gd` (`_test_the_manifests_equal_the_old_tables`, bad-preset-file test; old Plaits test replaced); 525 checks over 26 rack/registry tests, only the known cv-bench failure; still to do: the `builtin.<name>` rename and the DAW plugins (queue 4).
- 2026-11-07 — slice 3 step 3, Plaits on the registry: `res://mods/builtin/mutable/mod.json` (type stays `plaits`, rename to `builtin.*` is step 4), `ModRegistry.ensure_current`, catalogue/skin/pad_knobs read the registry first; new test `_test_the_registry_says_what_the_old_tables_say_for_plaits` (25 checks), 356 checks 0 failed over the rack/registry subset; shipped root is now `res://mods/builtin/`.

- 2026-11-07 — slice 2 closed: owner answers folded into docs/mods.md §11 and docs/layouts.md §13; docs only.

- 2026-11-07 — slice 1, state map: `docs/refactor_state_map.md` (mods, venues, studio.gd sections, doc and perf baselines, observations, 8 open questions); docs only, no code, no tests run.
- 2026-11-07 — loop started; brief written.
