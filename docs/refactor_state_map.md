# Refactor state map

A factual map of how mods and venues are represented **today** (2026-11-07, branch `modular-room`,
HEAD `d0f3915`), written for queue item 1 of `docs/refactor_loop.md`. Nothing here is a design;
the only judgement is in the last section. Line counts are `wc -l`. Every claim names a file, so it
can be checked.

Contents: 1 Mods, 2 Venues, 3 `studio.gd` and the big files, 4 Docs and perf baselines,
5 Observations.

---

## 1. Mods today

There is no mod concept. "Third-party DSP" is three separate, unrelated paths:

| Path | What it is | Third-party code | Loaded how |
|---|---|---|---|
| **A. The rack engine** (modular room) | 29 modules in one C++ process | Mutable Instruments (Plaits, Rings, Clouds), DaisySP, both as submodules | compiled on demand by `tools/rack_build.sh`, run as a child process over stdin/stdout |
| **B. The built-in DAW** (`GodotBackend`) | Godot `AudioEffect`s described by `FXCatalogue`, plus CLAP/VST3/LV2 hosted through dawkit | `vendor/dawkit` (own submodule, own repo) | dawkit GDExtension via `addons/dawkit` symlink; plugins scanned and loaded by dawkit |
| **C. Reaper** (`ReaperBackend`) | plugins are Reaper's own, the game only sees names and parameters over OSC | none in tree | OSC to a running Reaper |

### 1.1 Submodules and notices

`.gitmodules` (3 entries) and `git submodule status`:

| Path | Upstream | Pinned commit | Licence (per `THIRD_PARTY_NOTICES.md`) |
|---|---|---|---|
| `vendor/mutable-eurorack` | github.com/pichenettes/eurorack (STM32 projects only) | `f4cfa76` | MIT (AVR projects GPL-3.0, not used). Only its `stmlib` sub-submodule is initialised |
| `vendor/daisysp` | github.com/electro-smith/DaisySP | `2c72eaf` (V1.0.0-30) | MIT (`DaisySP-LGPL` folder unused) |
| `vendor/dawkit` | `../gd-dawkit.git` (this project's host) | `a810ec5` | "see its LICENSE" (the notices table has no version pin; `git status` shows it `m`odified, not ours) |

`THIRD_PARTY_NOTICES.md` is 13 lines: one table, one row per submodule, no per-module rows, no
licence text copies. Nothing ties a licence to an individual rack module or to a user-installed plugin.
`vendor/.gdignore` hides `vendor/` from Godot. `addons/dawkit` is a symlink to
`vendor/dawkit/addons/dawkit`.

### 1.2 Path A: the rack engine, end to end

**Native side** (`native/`, 1,248 lines of C++ in total):

| File | Lines | Role |
|---|---|---|
| `native/rack/rack.h` | 134 | `rack::Knob`, `Spec` (type, title, group, blurb, ins, outs, knobs), `Module` base, `Registrar` (static-init registration into `registry()`) |
| `native/rack/rack.cc` | 247 | graph: modules, cables, block loop (`BLOCK`=24 frames @ 48 kHz), meters |
| `native/rack/main.cc` | 203 | process front end: `--describe` (JSON catalogue), `--render OUT.wav` (offline), `--live` (float32 stereo on stdout, `meter ID PEAK` on stderr); text commands on stdin: `add ID TYPE`, `remove`, `clear`, `cable`, `uncable`, `cut`, `knob`, `bpm`, `play`, `stop`, `note_on/off`, `bend`, `cc`, `run`, `patch`, `quit` |
| `native/rack/modules_core.cc` | 656 | 25 `static Registrar` modules on DaisySP + hand-written DSP: keys, clock, seq, lfo, noise, sh, slew, att, quant, env, vco, drum, svf, ladder, vca, mix, fold, drive, crush, scope, delay, chorus, out, world, hand |
| `native/rack/modules_mutable.cc` | 208 | 4 `static Registrar` modules on Mutable Instruments: plaits (line 72), rings (119), reverb (146), clouds (198) |
| `native/rack_probe.cc` | 51 | stand-alone Plaits render probe (`tools/rack_probe.sh`) |

**Build** (`tools/rack_build.sh`, 30 lines): bash + `c++` (C++14), `-O2 -DTEST`. The source list is
hard-coded in the script: the four `native/rack/*.cc`, globs for `plaits/dsp`, `rings/dsp`,
`clouds/dsp`, `stmlib` resources, and 12 named DaisySP `.cpp` files (adsr, chorus, decimator,
overdrive, wavefolder, analogbassdrum, analogsnaredrum, hihat, ladder, svf, oscillator, dcblock).
Objects cached per file in `build/rack/obj`; output `build/rack/rack`. No CMake. Not built in CI
(`.github/workflows/*.yml` mention neither `rack` nor `rack_build`) and not in `export_presets.cfg`.

**Loading** (`core/music/rack/rack_engine.gd`, 343 lines, `class_name RackEngine`):
`RackEngine.binary()` runs `bash tools/rack_build.sh` once per process (env override
`DAWLINGS_RACK`); only on Linux and macOS (`rack_engine.gd:25`). On Windows, Android and Quest
the engine is `""`, `available()` is false and the room is silent. `RackEngine.render()` is offline
(tests), `RackEngine.Source` (line 272) is the live audio stream, `describe()` runs `--describe`.

**Game side, `core/music/rack/`** (all `RefCounted`/`Node`, no scene):

| File | Lines | Role |
|---|---|---|
| `modules.json` | 1,520 (45 KB) | committed output of `rack --describe`: `{rate, block, modules: [{type, title, group, blurb, ins, outs, knobs: [{id,label,lo,hi,def,curve,names}]}]}` |
| `rack_catalogue.gd` | 118 | `RackCatalogue`: lazily parses `modules.json` into `_modules`/`_order`; `types()`, `spec()`, `in_group()`, `knob()`, `real()`/`position()` (knob 0..1 <-> value, curves lin/exp/step), `readout()`. `GROUPS` = Source, Voice, Control, Filter, Shape, Time, Mix |
| `rack_patch.gd` | 672 | `RackPatch`: the patch is a plain Dictionary `{modules: {id: {type, at:[col,row], knobs:{k:v01}}}, cables: [[from,to]]}`. `ROW=&"rack"`, `MAX_MODULES=64`, `MAX_CABLES=160`. 30 `preset()` patches (lines 47-345, hand-coded `_put`/`_add`/`_wire` calls naming module types and knob ids), `add/remove/move/connect_cable/pull/set_knob`, `sanitize()`, `lines()` (patch -> engine commands), `answer(p, op, args)` (the one verb entry the room uses), world-socket helpers (`WORLD_OUTS`, `world_out`, `world_sink`, `step_world`) |
| `rack_layout.gd` | 169 | `RackLayout`: case grid `COLS=40` x `ROWS=4`; `width_of(type)` computed from knob and jack counts (`KNOBS_PER_COLUMN=8`, `JACKS_PER_COLUMN=6`; scope fixed at 4); `fits`, `free_slot`, `tidy`, `flow` (auto-layout by signal flow) |
| `rack_mood.gd` | 29 | `RackMood.MOODS`: a colour triple for each of the 14 venue ids (so a mod-ish concern keyed by venue), `FALLBACK`; `palette(venue_id)` |
| `rack_curves.gd` | 108 | knob curve drawing for the module's second face |
| `rack_engine.gd` | 343 | see above; plus a WAV writer (`write_wav`) and `Source` |
| `rack_voice.gd` | 322 | `RackVoice` (Node): owns the engine process, `set_patch` -> `_sync_patch` (diff -> `RackPatch.lines`), `knob`, `note_on/off`, `bend`, `cc`, `play_world`, `set_hand`, `set_track`; pumps audio into `InputMonitor.feeds` for the chosen DAW track; `record_start/stop` takes a take. Host only |

`core/music/modular/` (703 lines) is the room-side of the rack, not the DSP: `modular.gd` (57: ids
`SOURCE`/`STATION`, `WORLD` = 12 world socket ids, `Event` enum, `WORLD_GATE`), `modular_world.gd` (332:
weather/drips/venue/looper rings turned into events on every machine and fed to
`RackVoice.play_world`), `world_socket.gd` (314: the 3D socket objects in the room).

### 1.3 Path A in the game: from catalogue to 3D object

| File | Lines | Role |
|---|---|---|
| `hardware/rack/rack_wall.gd` | 1,400 | `RackWall` (Surface): the case (`_build_case`), per-module plates (`_build_module` at 656: plate, title, jacks, knobs from `RackCatalogue.spec`), second face (`_build_second_face` 770), palette of group keys and module keys (`_build_palette` 892), cables (`_lay_cables` 1095), drag/grip/drop (1200-1400), VU, pillars, mood glow (`set_mood`), touch keys; `show_patch(patch)` (986) builds, drops or moves only what changed (the ~65 ms to ~8 ms change in commit 680bae4). Signals: `edit_asked(op,args)`, `knob_streamed`, `knob_set`, `touched`, `keys_asked`, `track_asked`, `record_asked`, `told` |
| `hardware/rack/rack_skin.gd` | 136 | `RackSkin.SKINS`: per type `[face colour, accent colour, pattern, tagline]` (29 rows); `DEFAULT` for unknown; `signal_of(port)` colours cables by port-name lists `_GATES`, `_AUDIO` (by name, not by type) |
| `hardware/rack/rack_pad.gd` / `rack_bars.gd` | 207 / 146 | the orb pad (2 knobs) and the sequencer bar strip |
| `hardware/rack/scope_screen.gd`, `rack_jack.gd`, `rack_handle.gd`, `tear_tab.gd` | 138/37/74/106 | scope face, jack, grip handle, tear tab |
| `hardware/modular/modular_touch.gd`, `modular_jack.gd` | 126 / 0 (uid only) | touch keys under the case |
| `core/venues/modular_annex.gd` | 835 | `ModularAnnex`: a room built onto the live room of **every** venue (walls, doorway cut by `cut_the_wall`, lights, 14 columns, bench of 15 CV knobs, `rack_spot(annex_edge())`), in the venue's `RackMood` |
| `core/music/stations.gd` | 578 | the `modular` row (`spot: &"modular_spot"`, `frame: [RackWall.FRAME_TOP, RackWall.FRAME_FOOT]`, help lines) |

Per-module visuals are **procedural** (BoxMesh plate + Label3D + pattern MultiMesh from the skin);
there is no `.glb` per rack module. `RackUnit` (`hardware/rack/rack_unit.gd`, 612) is a different
thing: the DAW's per-track FX strip, using `assets/hardware/rack_panel.glb` (see 1.5). `MeshBank`
(`hardware/mesh_bank.gd`, 258) is a MultiMesh "many identical boxes as one draw call" helper used by
the DAW hardware (consoles, `RackUnit`'s four banks); `RackWall` does not use it for modules.
`hardware/patchbay/*` (`pin_matrix.gd` 1,937, `patchbay_surface.gd` 473, `patch_wall_surface.gd` 432,
`patch_cable.gd` 315) is the DAW's **audio routing** patchbay (tracks to sends), not the modular rack;
`PatchCable` is reused for rack cables.

### 1.4 Other lists that name rack things

| List | File:line | Keyed by | Note |
|---|---|---|---|
| Module catalogue | `core/music/rack/modules.json` | type | generated from C++ |
| Groups in palette order | `rack_catalogue.gd:8` `GROUPS` | group | must contain every module's `group` (test) |
| Skins | `rack_skin.gd:19` `SKINS` | type | unique face/accent pair per type (test) |
| Orb-pad knob pairs | `rack_wall.gd:114` `PAD_KNOBS` (21 types) | type | optional, per type |
| Type special cases | `rack_wall.gd:713` (`out`), `:738` (`scope`), `:778` (`seq`) | type | hard-coded UI per type |
| Out singleton | `rack_patch.gd:397,582,629,639`; `rack_voice.gd:264` | type `"out"` | one `out` per patch, special-cased in 6 places |
| World sockets | `modular.gd:30` `Modular.WORLD` (12) <-> `rack_patch.gd:405` `WORLD_OUTS` (12) <-> C++ `world` module outs (24 = 12 + 12 `_g` gates) | index | three lists that must stay in order |
| Gate-input names | `rack_patch.gd:408` `GATE_INS` | port name | |
| Cable colour port lists | `rack_skin.gd:124-126` | port name | |
| Venue moods | `rack_mood.gd:9` `MOODS` | venue id | a rack file that knows the venue list |
| Presets | `rack_patch.gd:22-345` (`presets()`, `preset_title()`, `preset()`) | name | reference module types and knob ids |
| Case size | `rack_layout.gd:8` COLS=40, ROWS=4 | | tests assert both |

### 1.5 Path B and C: DAW plugins as hardware

Plugins are not a catalogue of files; they are **rows of a track's FX chain** in `MixState`, shown
on rack units and tablets.

| Piece | File (lines) | Role |
|---|---|---|
| Choice list | `MixState.fx_choices` (`core/daw/mix_state.gd:497`, `Array` of `[id, label]`); published by `OfflineBackend.publish_fx_choices` (`offline_backend.gd:729`), `GodotBackend.fx_choices` (`godot_backend.gd:493`), `ReaperBackend.fx_choices` (`reaper_backend.gd:546`); wired to guests as `/fxchoices` (`mix_wire.gd:85,967`) | what ADD PLUGIN offers |
| Backend API | `core/daw/daw_backend.gd` (2,730): `add_fx`, `remove_fx`, `set_fx_param`, `set_fx_enabled`, `set_fx_wet`, `step_fx_preset`, `move_fx`, `read_fx_params`, `open_plugin_window`, `fx_latency`, capability flags (`FX_PRESETS`, `FX_CHAIN`, `PLUGIN_WINDOW`) | contract each backend fills |
| Facade | `core/daw/daw.gd` (1,674): `add_fx` (289), the intent check against `fx_choices` (1314) | |
| Godot's own effects | `core/built_in/fx_catalogue.gd` (194): `FXCatalogue` kinds -> `{name, make: Callable, params}`; every param normalised 0..1 | |
| Third-party plugins | `core/built_in/plugin_catalogue.gd` (195, `PluginCatalogue`: dawkit's scanner program lists CLAP/VST3/LV2, cached in `user://plugin_scan.json`, one process per plugin file, 60 s timeout), `hosted_plugins.gd` (210, `HostedPlugins`: loaded `DawKitPlugin` objects by `host_key`, loaded on a thread), `hosted_plugin_window.gd` (76) | host only |
| Reaper | `core/reaper/reaper_backend.gd` (2,005), `osc.gd` (142), `osc_peer.gd` (70), `script_bridge.gd` (102), `reaper_plugin_window.gd` (246) | plugin windows via `native/plugin_view.c` (794), a helper that reparents the plugin window |
| Window stand-in | `core/daw/plugin_window.gd` (78, `PluginWindow`) | picture + forwarded pointer events |
| In-game FX strip | `hardware/rack/rack_unit.gd` (612, `RackUnit`: 2U panel, up to `MAX_KNOBS=8` knobs, page prev/next, bypass, remove, chain arrows), `hardware/rack/rack_surface.gd` (545, `RackSurface`: a track's rack of units) | one unit per FX slot |
| Tablet | `hardware/rack/plugin_tablet.gd` (974, `PluginTablet`: 12 knobs a page, presets, MIX, KEY IN, CHAIN, MOVE TO, UI face = the plugin's own window), `plugin_screen.gd` (145), `tablet_selector.gd` (124, the ADD PLUGIN wheel) | |
| Picker | `scenes/plugin_picker.gd` (145, `PluginPicker`, searchable list over `fx_choices`) | |
| Studio side | `studio.gd:2056-2244` (tablets: `open_tablet`, `_build_tablet`, `_dock_tablet`, `_remember_tablets`), `2245-2438` (pulled-out track racks) | |
| Persist / share | tablets and racks: per-player in `LayoutProfile` (`core/presentation/layout_profile.gd`, 166: `track_racks`, tablets), and in the room row `tablets`/`track_racks` (`studio.gd:2446-2480`) | |

DAWKit (`vendor/dawkit`, own repo): GDExtension (`libdawkit.*.so/.dll`, prebuilt binaries in
`vendor/dawkit/addons/dawkit/bin`), engine scripts (`dawkit_metronome/stretch/tine.gd`), scanner
(`dawkit_scan.*`). The game's `tools/verify.sh` builds and tests it first. A third-party plugin has
no skin or model: it appears as a generic `RackUnit` with parameter knobs and an optional tablet.

### 1.6 Save and replication of the rack

| Question | Answer (with file) |
|---|---|
| Where does the patch live in memory? | `Studio.rack_row = {"patch": ..., "track": int}` (`studio.gd:264`, default preset `keys_voice`) |
| Is it saved to disk? | **No.** `LayoutProfile` has no rack field (`layout_profile.gd`, `grep rack` finds only `track_racks`); `rack_row` is only in the room state. A restart is back at `keys_voice` unless a host session is already carrying it |
| How is it shared? | Room row `RackPatch.ROW = &"rack"` inside `Studio.room_state()` (`studio.gd:2446-2480`), carried by `Session.room`; a guest's `apply_room` (`studio.gd:2716`) re-applies it, replaying its own un-acked `rack` predictions on top, then `_show_rack` |
| How is it edited? | One verb. `ask_rack(op, args)` (`studio.gd:4805`): authority -> `_answer_rack` -> `RackPatch.answer` -> `_show_rack` -> `_publish_room_soon`; guest -> `_rack_apply` on a copy, then `Session.ask_room(&"rack", [op, args])` (`session.gd:1686` validates the arg types, `:329` documents the row). Knobs have a fast path `_turn_knob` (rate limited by `Session.KNOBS_PER_SECOND`) |
| Who makes sound? | Host only. `RackVoice` runs the engine and feeds `InputMonitor.feeds[track]`, so guests hear it in the mix. A guest's keys reach the rack as notes (`Presence.modular_heard` -> `Modular.SOURCE`) |
| Sanitising | `RackPatch.sanitize` clamps ids, types known to `RackCatalogue`, columns, `MAX_MODULES/MAX_CABLES`. A module type the catalogue does not know is dropped |
| What does a guest need to have? | The same `modules.json` (shipped in the project). The guest never runs the engine |

### 1.7 Adding one rack module today: every file touched

Worked example: a new DaisySP-based module `foo` (group Shape). A new Mutable Instruments project
(e.g. Elements) additionally needs a new glob in `tools/rack_build.sh` and a notice row.

| # | File | Edit | Forced by |
|---|---|---|---|
| 1 | `native/rack/modules_core.cc` (or `modules_mutable.cc`) | a `struct Foo : Module` and a `static Registrar r_foo({"foo","FOO","Shape","blurb", ins, outs, knobs}, factory)` | engine |
| 2 | `tools/rack_build.sh` | add the upstream `.cpp` to the explicit DaisySP list (or a new MI glob) | build |
| 3 | `core/music/rack/modules.json` | regenerate: `build/rack/rack --describe \| python3 -m json.tool > core/music/rack/modules.json` | test `_test_a_rack_catalogue_is_the_engines_own_description` (`run_tests.gd:44550`) compares it to `--describe` |
| 4 | `hardware/rack/rack_skin.gd` `SKINS` | a `[face, accent, pattern, tagline]` row | `_test_every_module_has_a_skin_and_the_big_rig_fits_the_case` (`:44881`): every type has a skin of its own (unique face+accent), a tagline and a non-`none` pattern |
| 5 | `hardware/rack/rack_skin.gd` `_GATES`/`_AUDIO` | only if a port name is new (cable colour) | none (cosmetic, silent) |
| 6 | `core/music/rack/rack_catalogue.gd` `GROUPS` | only if a new group | test "every group the palette lists has modules" |
| 7 | `hardware/rack/rack_wall.gd` `PAD_KNOBS` | optional orb pad pair | none |
| 8 | `hardware/rack/rack_wall.gd` `_build_module` | only if the module needs a custom face (like `scope`, `seq`) | none |
| 9 | `core/music/rack/rack_patch.gd` presets | optional | none |
| 10 | `docs/architecture.md` ("The modular room") | prose; currently stale (see 5) | none |
| 11 | `THIRD_PARTY_NOTICES.md` | only for a new upstream | none |
| 12 | `.gitmodules` + `vendor/<x>` | only for a new upstream | none |

`studio.gd` needs **no** edit for a rack module. Plaits as the worked example: items 1 (`modules_mutable.cc:72`),
3 (json), 4 (`rack_skin.gd:45`), 7 (`rack_wall.gd:114`), plus presets referencing it
(`rack_patch.gd:52,154,224,306`). A rack module needs no 3D model, mood hook or sound-source binding
beyond what the C++ `Module` is.

### 1.8 Tests that enumerate or hard-code modules

All in `tests/run_tests.gd` (45,360 lines, 731 `_test_` functions); `tests/signal_tests.gd` and
`tests/workshop_tests.gd` have none.

| Line | Check | Breaks on a new module? |
|---|---|---|
| 44551 | `RackCatalogue.types().size() >= 25` | no (floor, now 29) |
| 44552-44553 | every group has modules; every module's group is in `GROUPS` | only if a new group is not added |
| 44566-44568 | `modules.json` equals `rack --describe` (needs a built engine; skipped if unavailable) | **yes**, until json regenerated |
| 44693-44712 | loops over `RackCatalogue.types()` (not `out`): patches it hot between `keys`/`noise`/`out`, renders 0.3 s and checks 14,400 finite frames | runs the new module automatically; fails if it NaNs or exceeds +-2.0 |
| 44885-44893 | every type has a unique skin, a tagline, a pattern; `seen.size() == types().size()` | **yes**, until a skin is added |
| 44896-44897 | `COLS==40`, `ROWS==4`, `width_of("scope")==4` | no |
| 44626-44627 | `world` has an out for every `Modular.WORLD` socket and `marbles_g` | no (world only) |
| 44759 | `width_of("seq") > width_of("vco")` | no |
| 44981 | `annex.bench.size() == 15` (ModularAnnex bench; in the known-failure list) | no |
| 44598 etc. | named types in tests: `vco`, `wave`, `ladder`, `cutoff`, `keys`, `noise`, `out`, `world`, `reverb`, `clock`, `seq`, `scope`, `plaits`... | only on rename or removal |
| 44571-44614, 44663-44790 | `_test_a_rack_patch_checks_every_verb`, `_a_rack_engine_makes_the_sound_the_patch_says`, `_a_rack_voice_plays_live_through_a_track`, `_a_rack_layout_keeps_modules_apart...` | no |

So today, adding a module breaks exactly two tests until the json and the skin are added; no test
hard-codes the count 29. A future "sample mod as a folder" proof cannot pass these two as written,
because both read in-tree lists.

---

## 2. Venues today

### 2.1 The set

15 classes, 14 selectable (`Venue.IDS`, `venue.gd:21`) + the roulette room (`Venue.ROULETTE_ID`,
`RouletteRoom`, 208 lines). Each of the 14 has 3 arrangements (`Venue.VARIANTS`, `venue.gd:31`);
the roulette room has 1. 14 x 3 = 42 venue/arrangement combinations are what the tests loop over.

| id | File | Lines | Arrangements |
|---|---|---|---|
| studio | `studio_venue.gd` | 1,244 | Live room behind / beside / Through the glass |
| grid | `grid_venue.gd` | 1,013 | Highway / Downtown / Neon sea |
| chalk | `chalk_venue.gd` (+ `chalk.gd` 283) | 1,869 | Open sky / Sketched room / Classroom |
| loft | `loft_venue.gd` | 1,468 | City night / Sunday morning / Thunderstorm |
| cabin | `cabin_venue.gd` | 1,556 | Snowy night / Summer dusk / Northern lights |
| rooftop | `rooftop_venue.gd` | 858 | Dusk / Golden hour / Night |
| station | `station_venue.gd` | 881 | Night side / Day side / Orbital sunrise |
| dome | `dome_venue.gd` | 1,554 | Twenty metres / The deep / Shipwreck |
| club | `club_venue.gd` | 2,145 | After hours / Showtime / Speakeasy |
| cave | `cave_venue.gd` | 1,962 | Crystal grotto / Glowworm lake / Lava tube |
| greenhouse | `greenhouse_venue.gd` | 1,583 | Morning / Rain / Night bloom |
| stage | `stage_venue.gd` | 1,798 | Headline night / Soundcheck / Arena |
| garden | `garden_venue.gd` | 1,562 | Spring / Autumn / Winter |
| desert | `desert_venue.gd` | 1,670 | Starlit canyon / Dawn dunes / Oasis |
| roulette | `roulette_room.gd` | 208 | one (not in `IDS`) |

Shared code in `core/venues/`: `venue.gd` 1,368 (base class), `zone_kit.gd` 570 (riser, booth,
table, keyboard stand, mic stand, prop shelf), `shell_kit.gd` 68 (wall/ceiling helpers),
`mirror.gd` 187, `wardrobe.gd` 202, `modular_annex.gd` 835. Total `core/venues/*.gd`: 24,884 lines (the 14 venue
scripts are 21,163 of it, avg ~1,510). `core/room/` (1,065 lines): `neighbourhoods.gd` 215, `floor_plan.gd` 229,
`trolley.gd` 417, `session_layout.gd` 73, `caster.gd` 131. `core/music/venue_instrument.gd` (1,447) is each
venue's own playable instrument (`Venue.instrument()`), and `Weather` is each venue's weather.

### 2.2 How a venue is built

1. `Venue.make(id, which)` (`venue.gd:105`): a 14-arm `match` on id -> `XVenue.new()`, default `StudioVenue`; sets `variant`.
2. `Studio.set_venue(id, remember, variant)` (`studio.gd:619`) builds an `Environment`, calls `dress(env, key)`,
   restyles lamps (`lamp_colour/energy`), sets `rich`, adds the venue as a child; then re-stands everything that
   depends on it: `_stand_the_cassette_rack/sampler/drum_circle/looper/venue_instrument/weather/modular/...`
   (`studio.gd:690-860`, `4718`), `_build_live_pieces` / `_wheel_in_live_pieces` (`1814-1932`).
3. Each venue builds its own geometry in `_ready`, branching on `variant`. There is no shell data: `ShellKit` is
   a 68-line helper, not a description. Walls, windows, props are code (`BoxMesh`/`add_child` etc.) with Blender `.glb` props
   from `assets/`.
4. Each venue dresses the five `ZONE_IDS` (bricks, matrix, drums, vocals, synth) as nodes `Zone_<id>` via `ZoneKit`.
5. The base `Venue` exposes about 60 `*_spot()` methods (`venue.gd:385-1100`): `prop_shelf_spot`, `headphones_spot`,
   `tablet_spot`, `hoop_spot`, `sampler_spot`, `modular_spot`, `lyrics_spot`, `looper_spot`, `drum_circle_spot`,
   `wheel_spot`, `sections_spot`, `platter_spot`, `eq_wall_spot`, `levels_spot`, `tv_spot`, `stage_table_spot`,
   `rig_roulette_spot`, `roll_board_spot`, `workshop_spot`, `miniature_spot`, `mic_spot`, `weather_spot`,
   `instrument_spot`, ... Most are computed from the zone boxes (`Venue.ZONES`) plus constants; venues override
   some (counted `*_spot`/`default_*` overrides per venue file: club 6, rooftop 6, desert 4, dome 3, stage 3, studio 3,
   chalk 2, loft 2, greenhouse 2, cabin 1, garden 1, cave, grid and station none: 11 of 14 files override).

### 2.3 Where spot and layout data lives

**Code, not data.** Nothing is read from a file. Layers, from most to least fixed:

| Layer | Where | Form |
|---|---|---|
| Zone boxes (5, at base width) | `Venue.ZONES` `venue.gd:65` | `AABB` consts; `zones()` (366) steps them outward per side as the desk widens the room |
| Room/live-room extents | `LIVE_ROOM_BACK/HALF/HEIGHT`, `DRAWN_*`, `Studio.ROOM_WIDTH/DEPTH` | consts |
| Per-station default spots | `Venue.*_spot()` methods, per-venue overrides | GDScript functions returning `Transform3D` or `null` (= no room for it here) |
| Station table | `Stations.ALL` `stations.gd` (578 lines, 24 rows): `id, title, area, zone, air, spot (method name), at, frame, foot, top, cart, surface, seat, reach, desk/hands help` | const array of Dictionaries; `spot` is a **string naming a Venue method** |
| Wheeled pieces | `Venue.WHEELED` `venue.gd:889` = `cassette_rack, sampler, tour_case, prop_shelf, hoop` and `default_spot(id)` (895) matching on id | const + match |
| Trolley specs | `Studio.LIVE_TROLLEYS` `studio.gd:1790` (footprint, push weight, grips for the same 5 ids) | const dict |
| Neighbourhoods | `Neighbourhoods.ALL` `neighbourhoods.gd:30` (6 banners: mixing, rhythm, harmony, synth, vocals, tape); which `Stations` ids and `WHEELED` ids belong to each | const; `RADIUS` 3.4 m |
| Walkable/solid | `Venue.rooms()`, `solids()`, `zone_solids()`, `wheeled_solids()`, `instrument_solids()`, `weather_solids()`, `footprint_corners()` | functions |
| Desk-dependent furniture | `SessionLayout` (`session_layout.gd`): `RACK_AT`, `DECK_AT`, `PATCH_AT` etc. and `WIDTH_STEP=0.8`: the room widens in 0.8 m steps and pieces step with it | consts |
| Legacy defaults | `Studio.OLD_FLOOR_DEFAULTS`, `OLD_FIT_LINES`, `OLD_EQ_WALL` (`studio.gd:3219-3240`), `was_an_old_default` (3249) | migration table: a saved spot equal to an old default is treated as "not chosen" |

### 2.4 What is mounted on the venue vs. what stands on the floor

| Kind | Examples | Placement | Moves? |
|---|---|---|---|
| Venue-built, fixed | walls, riser, booth, bricks table, wheel on the table, lattice frame, the venue's own instrument, weather switch, modular annex | the venue's code | no (`FloorPlan.stops` / `_venue_stops`) |
| Zone-mounted stations | wheel, sections, drums, looper, lyrics, modular (`zone` field in `Stations`) | `Venue.*_spot()` from zone boxes | no |
| Wheeled "live pieces" | `WHEELED` (5) + `station_board` + `patch_wall` legs (`live_pieces` Dictionary) | `Venue.default_spot(id)` then saved `floor/<id>` | yes (Trolley) |
| Control-room furniture | console, tape deck cart, rack trolley, stage table, EQ wall, levels niche, TV mount, patch stand (`_build_furniture` 1229-1770) | `SessionLayout` + `Venue` spots | yes (Trolley) |
| Player-owned | plugin tablets, track racks (`2056-2438`) | wherever pushed | yes, saved per player and shared |
| Items | toys, tablet, instruments on the shelf (`ItemRoom`, `core/items/`) | `Venue.item_spots()` on the prop shelf, homes `_item_homes` (3998) | picked up |

### 2.5 Saved defaults, room rows, re-spot

* **Per player** (`LayoutProfile`, `core/presentation/layout_profile.gd`, 166 lines, a ConfigFile; `Session.layout`):
  `set_transform(key, Presentation.Mode, Transform3D)`; floor pieces use key `"floor/<piece_id>"`, mode STUDIO;
  also `track_racks`, tablets, `made` items, venue + variant. `save()` after every settle
  (`_on_trolley_settled`, `studio.gd:3285-3318`).
* **A push that equals the venue's default is not stored**: `_where_the_venue_stands_it` (`studio.gd:3269`)
  clears the key instead, so a different venue or a wider room re-stands it. `was_an_old_default` does the same for
  legacy values.
* **Re-spot on venue change**: `_wheel_in_live_pieces` (`studio.gd:1902`): for each live piece take `_live_default`, hide it
  if null, else the saved `floor/<id>` (unless an old default), then `Trolley.place` each against the others and the venue's solids
  (`FloorPlan.resolve`), so a spot that is a wall in this venue becomes the nearest clear place. Not saved.
* **Shared room**: `Studio.room_state()` (`studio.gd:2446`) is the host's room row: `venue, variant, tablets, floor
  {piece_id: [x, z, yaw]}, placed {surface_id: studio_home}, items, made, patches, on_air, board, track_racks, jacks, ropes,
  sampler, weather, looper, rack, tv, pads`. A guest sees it via `apply_room` (2585), and its own wheeling is a prediction
  (`move_piece`, `move_tablet`) that the host confirms. Guests do not edit the host's layout without a host round trip.
* **Not in the room row**: which venue pieces exist. There is no "add a piece" or "remove a piece"; the set of pieces is the
  code's.

### 2.6 What the placement tests guarantee (`tests/run_tests.gd`)

| Line | Test | Guarantee |
|---|---|---|
| 9195 | `_test_every_venue_leaves_room_for_the_activities` | all 5 zones present, big enough, clear of the footprint and each other, dressed, at base width and widened |
| 8905 | `_test_venues_change_the_world_and_not_the_setup` | no gear moves, nothing added or lost, a floor exists, the choice persists |
| 26660 | `_test_every_venue_stands_every_station_clear` | every `Stations.ALL` row in every venue/arrangement: on the floor, off the footprint, clear of zones/solids/props, solid where the room is, a seat to fit at, facing it; exact list of stations per venue (`:26675`) |
| 26741 | `_test_every_venue_keeps_its_pieces_apart_and_every_station_in_reach` | with a blank `LayoutProfile`: no two pieces closer than `ROOM_CLEAR` (polygon gap), and every station reachable from the middle (walker) |
| 27062-27082 | six `_test_the_*_neighbourhood_*_stands_together_and_is_signed` | each neighbourhood's members within `RADIUS`, banner present |
| 32563 | `_test_the_stage_table_stands_clear_in_every_venue` | |
| 36347 | `_test_the_platter_rides_the_deck_cart_clear_in_every_venue` | |
| 37639 | `_test_the_bricks_table_holds_its_two_bands_clear` | |
| 43722, 43996 | looper rings, lyric board clear in every booth | |
| 25021 | `_test_every_venue_has_a_clear_door_to_the_roulette_room` | |
| 6628 | `_test_the_big_board_hangs_clear_in_every_venue` | |
| 17944, 18544, 29408, 41791 | mirror, toy, wheel-on-table, something-to-play-in-key per venue | |
| tools | `tools/layout_dump.gd` + `layout_map.py` (headless JSON + SVG/PNG maps of every venue: floor, walls, zones, footprints, clearances); `tools/probe/walk_map.tscn` | measuring, not a test |

Venue-id tables outside `core/venues/`: `RackMood.MOODS` (14), `VENUE_SETS` (tests `:41763`), `WEATHERS` (tests), `Venue.VARIANTS`, `Venue.make`,
`Venue.make_title`, `IDS`, `core/items/toy_item.gd` (per-venue toy), `Stations` instrument rows through `VenueInstrument`.

### 2.7 `docs/venues.md` (171 lines)

Prose table of the 14 venues and the 3 arrangements, a "Contract" (dress/lamps/pulse, footprint, zones, walking, prop shelf),
"Adding one" (4 steps: subclass; build geometry in `_ready`, dress all five zones; add to `IDS`/`make`/`make_title`; list `VARIANTS`),
and Chalk. It does not describe `Stations`, `Neighbourhoods`, `WHEELED`, trolleys, saved `floor/<id>` rows, the annex, or
the instrument/weather. Those live in `docs/architecture.md` ("Room layout"), `docs/spatial_loop.md`, and the
doc comments in the files above.

---

## 3. `studio.gd` and the big files

### 3.1 `scenes/studio.gd` (8,445 lines, 393 `func`s): sections by line range

Class doc at the top; `Studio extends Node3D`. Classification: **M** = mods/rack, **V** = venue/layout/placement, **O** = other.

| Lines | Responsibility | Key functions | Kind |
|---|---|---|---|
| 1-431 | consts, vars, signals (one flat list: ~300 member vars), `LIVE_TROLLEYS` (1790) later | | O/V |
| 432-618 | `_ready`, environment, renderer tuning, mirror exclusion, `_exit_tree` | `_ready`, `_build_environment`, `_tune_renderer` | O |
| 619-1070 | venue swap + stand the venue-dependent stations | `set_venue`, `_stand_the_*` (roulette door, wheel, sections, cassette rack, sampler, drum circle, looper, venue instrument, weather), `_hold_the_rack` (cassette), patch wall, lamps | V |
| 1072-1226 | walkable, ceiling, choose/cycle venue, roulette room, headset check | `_walkable`, `choose_venue`, `enter_roulette_room` | V |
| 1229-1770 | control-room furniture builders | `_build_furniture`, `_build_platter_leaf`, `_build_stage_trolley`, `_build_eq_wall_trolley`, `_build_levels_niche`, `_build_tv_mount`, `_build_patch_stand` | V |
| 1771-2055 | live pieces: trolley table, build, wheel in, carry, hood signs, rehome | `LIVE_TROLLEYS`, `_build_live_pieces`, `_live_default`, `_wheel_in_live_pieces`, `_carry_live`, `_hang_hood_signs` | V |
| 2056-2244 | plugin tablets | `open_tablet`, `_build_tablet`, `_dock_tablet`, `_remember_tablets`, `_restore_tablets` | M (DAW plugin hardware) |
| 2245-2438 | pulled-out track racks | `open_track_rack`, `_build_track_rack`, `close_track_rack`, `_remember_track_racks` | M (DAW) |
| 2439-3000 | the shared room: state out / in, predictions, asks | `room_state`, `apply_room`, `_predict`, `_on_room_asked` (2837-2957) | V + O (replication; carries the `rack` row) |
| 3000-3320 | fitting the room to the session, trolleys, saved spots | `_fit_room_to_session`, `_trolley`, `was_an_old_default`, `_where_the_venue_stands_it`, `_on_trolley_settled` | V |
| 3321-3897 | clip editor, anchors, fingertips, chord hand, surfaces, lamp stands | `_build_anchors` (3371-3523 is one function), `_build_surfaces` | O |
| 3898-3992 | looms (cable looms between gear) | `refresh_looms` | O |
| 3993-4450 | items and made items (cassettes) | `_build_items` (4035-4174), `give_item`, `_hand_made` | O |
| 4451-4642 | weather, looper, lyrics | `_set_weather`, `_answer_looper`, `edit_lyrics` | O |
| **4643-5100** | **the modular room's rack** | `_build_rack`, `_stand_the_modular`, `_stand_the_annex`, `ask_rack`, `_turn_knob`, `_rack_apply`, `_answer_rack`, `_show_rack`, `_rack_wake`, `at_modular`, `_follow_modular` | **M** |
| 5101-5300 | sampler | `_arm_sampler`, `_sample` | O |
| 5301-5750 | tour case, setup wall, presets, roll board, rig roulette rolling and undo | `_roll_rig`, `undo_the_roll` | O |
| 5750-6110 | tour events, spilled instruments, crowd | `_spill_instrument`, `_on_tour_*` | O |
| 6110-6870 | listening, clap/lean/ear, patches (`_on_patch_asked`, `_on_plug_asked`), jacks, on-air, headphones, walker | | O |
| 6870-7140 | input and `_process` | `_unhandled_input` (160 lines), `_process` | O |
| 7140-7390 | text scale, viewport, sitting, seats | `_sit_down`, `_walk_to_seat` | O |
| 7387-7680 | going to a station (desktop and headset) | `go_to_station`, `_travel_to_station`, `_build_station_board` | V |
| 7679-7990 | the session in miniature, drum pads on anything | `_build_desk_wing`, `_build_pads` | O |
| 7989-8445 | seeing the signal, look-to-solo, trace | `signal_view_on`, `look_solo_*`, `trace_*` | O |

Totals (approx): mods/rack-specific 460 lines in one block + 340 for tablets/track racks (DAW plugins); venue/layout
~2,800; the rest ~4,800 is features that are neither. Splitting out venue/layout and mods alone leaves ~4,800, still
over the ~800-line goal, so item 9 will need to move non-mod/venue systems too.

### 3.2 Files over 800 lines (`git ls-files '*.gd' '*.cc' | xargs wc -l | sort -rn | head -25`)

| Lines | File | Note |
|---|---|---|
| 45,360 | `tests/run_tests.gd` | 731 tests, one file |
| 8,445 | `scenes/studio.gd` | god object |
| 4,195 | `tools/probe/session_probe.gd` | |
| 2,793 | `core/session/session.gd` | |
| 2,740 | `hardware/timeline/timeline_surface.gd` | |
| 2,730 | `core/daw/daw_backend.gd` | |
| 2,333 | `core/built_in/godot_backend.gd` | |
| 2,206 | `scenes/session_panel.gd` | |
| 2,145 | `core/venues/club_venue.gd` | |
| 2,112 | `core/daw/offline_backend.gd` | |
| 2,005 | `core/reaper/reaper_backend.gd` | |
| 1,962 | `core/venues/cave_venue.gd` | |
| 1,937 | `hardware/patchbay/pin_matrix.gd` | |
| 1,869 | `core/venues/chalk_venue.gd` | |
| 1,798 | `core/venues/stage_venue.gd` | |
| 1,784 | `hardware/stage/stage_table.gd` | |
| 1,783 | `core/audio/foley.gd` | |
| 1,748 | `core/session/presence.gd` | |
| 1,674 | `core/daw/daw.gd` | |
| 1,670 | `core/venues/desert_venue.gd` | |
| 1,583 | `core/venues/greenhouse_venue.gd` | |
| 1,562 | `core/venues/garden_venue.gd` | |
| 1,559 | `tools/screenshot.gd` | |
| 1,556 | `core/venues/cabin_venue.gd` | |
| 1,554 | `core/venues/dome_venue.gd` | |

Within the refactor's reach and over the ~800 limit (besides studio.gd and venue.gd): all 14 venue scripts (the smallest, `rooftop`, is 858); `rack_wall.gd` 1,400; `modular_annex.gd` 835; `plugin_tablet.gd` 974;
`pin_matrix.gd` 1,937; `venue_instrument.gd` 1,447; `mix_wire.gd` 1,043; `daw_backend.gd`, `daw.gd`,
`offline_backend.gd`, `godot_backend.gd`, `reaper_backend.gd`. "None over about 800" in goal C is stated for `studio.gd` and
`venue.gd` only; the done-when item 4 ("no file over the line limit") reads wider. Open question 4 below.

---

## 4. Docs and perf baselines

### 4.1 Doc comments

Counted with a script: first `##` before the first member, per `.gd` file (excluding `vendor/`, `.claude/`, `tmp_probe/`).

* 341 `.gd` files; **1** lacks a class doc comment, and it is under `addons/` (not ours). So the class-doc rule is already met.
* Public functions (`func name(`, no leading underscore) with no `##` line directly above (rough; a `#` comment or doc
  two lines up counts as missing, multi-line docs counted by their last line):

| Area | Public funcs | Without `##` |
|---|---|---|
| `core/music/rack/` | 79 | 40 |
| `core/music/modular/` | 30 | 8 |
| `hardware/rack/` | 59 | 41 |
| `hardware/patchbay/` | 51 | 19 |
| `hardware/mesh_bank.gd` | 15 | 3 |
| `core/venues/` | 423 | 150 |
| `core/room/` | 29 | 6 |
| `scenes/studio.gd` | 69 | 9 |
| `core/daw/` | 617 | 264 |
| `core/reaper/` | 152 | 83 |
| `core/built_in/` | 170 | 48 |

(Signals and consts are not counted. A script for this belongs in `tools/` per done-when item 4.)

### 4.2 `docs/` pages (23 files, no `docs/README.md` yet)

`architecture.md` (the one big page, includes "The modular room", "Room layout" and others), `colocation`, `daw_loop`,
`daw_parity`, `desktop_first`, `discord`, `environments_loop`, `flat_loop`, `items_loop`, `loop_backlog`, `multiplayer`,
`patchbay_backlog`, `perf_backlog`, `playtest`, `refactor_loop`, `roulette_loop`, `sampling_station`, `session_walkthrough`,
`spatial_ideas`, `spatial_loop`, `transport`, `venues`, `workshop`; plus `docs/media/`, `docs/walkthrough/`.
Many are loop briefs or backlogs (process), not system pages.

Systems with no page of their own (only a section of `architecture.md` or code comments): the modular rack and its
engine; the DAW backend contract (`daw_parity.md` compares, `daw_loop.md` is a loop); the built-in engine and dawkit hosting;
plugin tablets and track racks; rooms, stations, neighbourhoods and the floor plan (Trolley/FloorPlan/LayoutProfile);
the shared room and prediction (`multiplayer.md` covers the network, not `room_state`); items (`items_loop.md` is a loop
brief); the walker; venue instruments and weather.

`docs/architecture.md` is stale about the rack: it describes a case of `ROWS (2) x COLS (16)` holding "25 modules"
with groups "Source, Voice, Shape, Mod, Time, Utility, Mix" (line ~2225); the code is 4 x 40, 29 modules, groups
Source/Voice/Control/Filter/Shape/Time/Mix.

### 4.3 Perf tools

| Tool | Run | Gives |
|---|---|---|
| `tools/budget.sh` (+ `tools/budget.gd`) | `tools/budget.sh [tracks...]`, `VENUE=cabin tools/budget.sh 13`; runs the game windowed (`offscreen_run`, so workspace 10), vsync off, two poses (fitted, wide), 200 frames | prims, draws, objects, frame ms, worst ms, nodes, start ms, mem MB per track count |
| `docs/perf_backlog.md` | read | Baseline 1 table for all 42 venue/arrangement combos at 13 tracks (studio 7.1-7.9 ms, grid 5.4-6.5, ... greenhouse 6.8-7.2 ms, 2.7M prims), startup breakdown (about 2.9 s first frame), busy rooms, optimisations kept, dead ends, "144 fps loop" |
| `tools/light_check.sh` | script | the venue light budget |
| `tools/patchbay_stress.gd/.tscn` | `--headless` scene | patchbay stress |
| `tools/layout_dump.tscn` | `godot --headless --path . tools/layout_dump.tscn` then `python3 tools/layout_map.py` | per-venue floor-plan JSON and maps |
| `tools/probe/walk_map.tscn`, `size_probe`, `live_check`, `session_probe` | probes | |
| `tools/audio_latency.sh`, `keys_latency.sh`, `rack_probe.sh` | scripts | audio latency; Plaits render |
| `tools/verify.sh` | full local gate | builds dawkit, imports, runs dawkit's tests and the suite |

There is no number in `perf_backlog.md` for the rack (a `show_patch` before/after exists only in commit `680bae4`:
~65 ms to ~8 ms) or for `set_venue` time or `_wheel_in_live_pieces`. The "start ms" column (about 3.5-4.5 s per venue) is the
only venue-swap-adjacent figure.

---

## 5. Observations

Not a design; checkable facts that will matter.

### 5.1 Repetition, dead code, hacks

* `Venue.make` (`venue.gd:105`), `IDS` (21), `VARIANTS` (31), `make_title` (155), `RackMood.MOODS` (`rack_mood.gd:9`),
  tests' `VENUE_SETS` (`run_tests.gd:41763`) and `WEATHERS` are parallel per-venue lists: a venue is registered in at least 6 places.
* The five wheeled pieces are listed in `Venue.WHEELED` (`venue.gd:889`), `Venue.default_spot` (895), `Studio.LIVE_TROLLEYS`
  (`studio.gd:1790`), `Studio._carry_live` (1940, a match with a branch per piece), `Neighbourhoods.ALL` `pieces`, and `Stations.ALL` `foot`/`top`. Adding a piece
  is edits in all of them.
* Stations name their venue method as a string (`"spot": &"modular_spot"`, `stations.gd`); a typo is a runtime null.
* `"out"` is special-cased in 6 places (`rack_patch.gd:397,582,629,639`, `rack_voice.gd:264`, `rack_wall.gd:713`).
* Three parallel lists for world sockets (`Modular.WORLD`, `RackPatch.WORLD_OUTS`, the C++ `world` outs) must stay in the same order; `ring_1`..`ring_8` vs `ring1`..`ring8` spelling differs between them.
* `rack_skin.gd:124-126` colours cables by port **name** lists; any new port name defaults silently to "CV".
* `OLD_FLOOR_DEFAULTS`/`OLD_FIT_LINES`/`OLD_EQ_WALL` (`studio.gd:3219-3240`) are migration tables for saved spots from older rooms;
  they only matter to anyone with a pre-change profile (candidate for removal in item 10 if the owner agrees).
* `studio.gd:3243` `_left_where_it_was_authored` is a one-line wrapper over the static `was_an_old_default`.
* `rack_voice.gd` and `Studio._rack_*` duplicate "is the engine running / wake" logic across `_rack_wake`, `_rack_engaged`, `_turn_knob`, `_show_rack`.
* `docs/architecture.md` rack section is stale (4.2). `docs/venues.md` "Adding one" omits Stations, WHEELED, moods, tests.
* `RackEngine.binary()` runs the build script synchronously on first use (a compiler call inside `OS.execute` on the main thread; first-run cost not measured).
* Known suite failures in the loop file include RackWall "no two faces share a plane" (42 checks) and the bench count; both are
  in the area the mod slices touch.

### 5.2 What will make the refactors hard (coupling points)

1. **The rack engine is a build-it-yourself bash+c++ child process on Linux/macOS only.** It is not built in CI or the exports, so a "mod" that is
   a versioned binary has no precedent; the manifest has to say how a native module is obtained, and Windows/Quest need an answer.
   The whole module set is one executable (static `Registrar`s): a drop-in folder mod cannot add DSP without either a plugin ABI
   in `rack.h` or being data-only (a patch of existing modules).
2. **The catalogue is generated from the C++**, then committed, then compared by a test. A registry that discovers mods needs
   one source of truth; the current test would then contradict it.
3. **`modules.json` + `SKINS` + `PAD_KNOBS` + presets** are four places that know a module by id, in three directories.
4. **The patch format holds module type strings; `sanitize` drops unknown types.** A mod that goes missing silently erases its modules
   from the room row when the host sanitises (`RackPatch.sanitize`, `rack_patch.gd:570`). "Unavailable plate" needs the patch to keep the unknown node.
5. **The rack patch is not persisted locally** (1.6): "saves and reloads" for a sample mod needs a place for it (profile? project? room?).
6. **Replication carries only ids and knob values**; a guest without the mod has no catalogue entry to draw. Whether guests need the mod, or get a
   manifest/skin over the wire, is undecided.
7. **DAW plugins are an entirely separate system** (path B/C): they are strings from `fx_choices`, hosted by dawkit or Reaper, with generic
   `RackUnit` visuals. Putting them "through the same registry" means deciding what a manifest means for a plugin that is already a
   file on the user's disk and has its own scanner (`PluginCatalogue`).
8. **Venues have no data form at all.** Spots are methods that call other methods, read zone boxes, and in 11 of 14 venue files are overridden with literal
   numbers. Converting `*_spot` to data means giving a data format for "computed from the zone box plus an offset", which the tests'
   clearance checks rely on.
9. **Stations vs. pieces vs. surfaces vs. trolleys** are four overlapping notions (`Stations.ALL` rows; `Venue.WHEELED`; `Studio.live_pieces`; Surface ids in
   `mount`). The brief's "single item vs room-scale mod" split maps onto none of them cleanly. A modular room is today a `Station` +
   `Surface` + the `ModularAnnex` built into every venue.
10. **`ModularAnnex` is built onto every venue** (via `cut_the_wall` / `clear_the_site`), mutating the venue's walls. A "room-scale mod" that
    "needs its own space" is this today, hard-wired.
11. **`Studio.room_state()`** is a hand-written dictionary of ~17 keys, and `apply_room` (150 lines) is the matching reader; every new shared
    thing (a layout, a mod list) adds to both and to `Session`'s arg validation (`session.gd:1687`).
12. **`run_tests.gd` is a single 45k-line file** where every placement test builds a real `Studio` in a loop over 42 combos; the clearance
    guarantees are tested through `Studio`, not through the venue. Moving to layout data keeps them testable only if the placement logic can run
    without building a venue's geometry (it cannot today; the tests run the full build).
13. `studio.gd` is one class with ~300 member variables; the rack block (4643-5100) is separable, the venue/layout blocks are tangled with
    furniture builders, trolleys and the shared room.

### 5.3 Open questions for the owner

1. Should a rack mod be allowed to bring **new DSP code**, or only be a **patch macro / sample / data mod** over the existing modules?
   (Today there is no way to load DSP without recompiling.) Should the rack engine ship as a prebuilt binary per platform?
2. Does the rack need to **persist across restarts** (it does not today), and where: profile, project file, or only the room?
3. Do guests **need the mod installed**, or should the host send the manifest and skin (a guest then draws it but cannot hear it either way)?
4. Is the 800-line limit meant for every file (done-when 4), or only for `studio.gd` and `venue.gd` (goal C)? Fourteen venue scripts are 858-2,145 lines;
   `run_tests.gd` is 45k.
5. When layouts become data, do the 14 venue **scripts keep building geometry** (the shell stays code, only the placements move), or must the shell
   be data too (item 6 says "which room")?
6. May the `OLD_*` migration tables and the `Neighbourhoods` banners be dropped or must saved profiles from before the 0.8 m room steps keep working?
7. Is the DAW-plugin side in scope as **mods** (item 4: "then the DAW plugins") given dawkit is its own repository and Reaper plugins are not
   ours to ship? What is "unavailable" for a plugin the user's machine lacks?
8. The `docs/refactor_loop.md` file itself is untracked in git; this slice commits it with its first tick.
