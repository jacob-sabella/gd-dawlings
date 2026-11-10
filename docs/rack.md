# The rack: the modular room, the rack wall, the registry

The modular room is a rack of synth modules patched with cables, in a room of its own built onto the side of every
venue. A module is a mod entry (`docs/mods.md`); the patch is a file; the sound is a separate process on the host.
Design history and the saved-patch rules are in `docs/mods.md` 6; the older description of the room is
`docs/architecture.md` ("The modular room"). This page is the map.

## Files

| Layer | Files | What |
|---|---|---|
| Mods | `mods/builtin/{core,daisysp,mutable,airwindows,presets}/mod.json`, `core/mods/` | the 38 modules, their skins and 17 presets as manifests; the registry |
| Description | `RackCatalogue`, `RackSkin`, `RackModuleDef`, `RackCurves`, `core/music/rack/modules.json` | what modules exist, their jacks and knobs (from the engine snapshot), how they look, composite resolution |
| Patch (data) | `RackPatch`, `RackPatchFile`, `RackAutosave`, `RackGaps`, `RackExpansion`, `RackLayout`, `RackMood` | the patch as a dictionary `{modules, cables}` and every edit as one `answer(op, args)`; v2 file format; `user://patches/_current.patch.json`; what this machine cannot show; composites expanded to engine modules; where modules sit in the case (`COLS` x `ROWS`); the glow per venue |
| Sound (host only) | `RackVoice`, `RackCushion`, `RackEngine`, `native/rack/` | the engine as a process (`rack` binary built from pinned `vendor/` submodules by `tools/rack_build.sh`), told the patch as text lines, heard back as stereo float32; played through a track of the song |
| The wall | `hardware/rack/rack_wall.gd` (459 lines) + `RackWallModules`, `RackWallDrag`, `RackWallKeys`, `RackWallShow`, `RackWallDressing`; `RackUnit`, `RackPad`, `RackJack`, `RackHandle`, `RackBars`, `RackStubs`, `ScopeScreen`, `ModularJack`, `ModularTouch` | the surface: the case, a plate per module with knobs and jacks, a palette under the modules, cables, touch keys, the unavailable-plate stubs |
| The room | `ModularAnnex` + `AnnexSite` (`core/venues/`), `Modular` + `ModularWorld` + `WorldSocket` (`core/music/modular/`), `RackHost` (`core/room/`) | the room built onto the venue, the world (rain, the weather, the song clock) into the rack's sockets, the studio's rack section |

(`RackUnit` is not the modular rack: it is one FX plugin as a 19-inch unit on the DAW's plugin rack.)

## How it fits (who calls whom)

- Startup: `ModRegistry.ensure_current()` scans; `RackCatalogue` builds its cache from the registry and the engine
  snapshot; `Studio.rack_host` stands the rack (`RackWall`) and the annex, loads `RackAutosave` (host only).
- A player acts on the wall (`RackWallDrag`): the wall emits `edit_asked(op, args)` / `knob_set`; `RackHost` turns
  that into the room verb `rack` (`Session.ask_room(&"rack", [op, args])`); the host runs `RackPatch.answer`, applies
  it, `RackVoice` syncs the engine (it diffs the expanded patch, so a live edit sends only what changed), and the
  room row `rack` ({patch, track, uses}) goes to guests. A guest shows the change at once and is rolled back if the
  host refuses.
- Guests do not run the engine: they hear the host's rack through the track it sounds on. A guest without a mod the
  host uses sees an unavailable plate (`RackGaps`) naming it.
- `RackWall.show_patch(patch)` builds, drops or moves only what changed.

## The direct feed and its cushion

When no track carries the rack (`RackVoice._direct()`: a launch without the built-in engine, or no track chosen), the
rack plays through a player of its own: an `AudioStreamGenerator` on the MONITOR bus. A reader thread takes the
engine's pipe every 3 ms into `RackCushion`; once a frame `_pump_direct` asks the cushion what the generator should be
given. The rules, `core/music/rack/rack_cushion.gd`:

- **Nothing is pushed until 60 ms (`TARGET`, 2880 frames) are in hand.** Godot's mixer takes a generator's sound 512
  frames (10.7 ms) at a time; the first version pushed only what had arrived since the last frame and the generator
  held 8 ms on average, so any frame that ran long ran it dry and the gap clicked. Measured with
  `tools/rack_pump_probe.tscn` (real PulseAudio driver into a null sink, 60 fps): pluck_demo 60 s, 12 empty-generator
  events before, 0 after; acid_line with a 40 ms main-thread stall each second (30 s), 8 underruns, 5 holes of up to
  37 ms in the recording and a 0.31 sample jump before, 0 of each after. A smooth acid_line or big_rig for 60 s was
  already nearly clean (0 to 3 events): the fault shows when a frame runs long, which the whole studio does.
- **An underrun refills, and the cushion learns.** When the generator is found empty it is counted (`underruns`) and
  nothing is pushed until the cushion is in hand again. The cushion is a jitter buffer: after the first 3 s (the
  window opening stalls for 300 ms) an underrun deepens it to a little over the stall that caused it (at most 200 ms,
  `DEEPEST`), and 5 s of calm gives 10 ms back, down to 60 ms. A 100 ms stall every second therefore costs a few
  underruns while it learns, then none; a stall longer than the cushion is still heard as a gap, once.
- **A surplus is played fast, not dropped.** The engine's clock and the sound card's differ; past the target plus
  `SLACK` (20 ms) the next push is resampled up to 3 % faster (linear interpolation, no step) until the cushion is back.
  Nothing is cut except by the safety limit (a listener that stopped taking sound: the last 0.5 s is kept, `dropped`;
  0 in every run).
- Latency: 60 ms in the generator by default (it was 8 ms on average), so about 52 ms more, on top of the engine's own
  5 ms chunk and the sound card's buffer; up to 200 ms after a bad stall, back in a minute or so. A rack carried by a
  track (the built-in engine with a track chosen) does not use this path. Lower `RackCushion.TARGET` to trade safety
  for latency.
- `RackVoice.direct_stats()` reports fill, skips, underruns, hurried and dropped frames. `tools/rack_pump_probe.tscn`
  plays a preset to the real driver for a while and prints them (usage in its header, `docs/tools.md`).

## Power and the song clock

- **The big ON/OFF key** (left of PLAY on the wall) is the room's `power` in `studio.rack_row` (next to `track`, not in the
  patch, so it is not saved with it and the rack is on at launch). It is the `power` rack op (`RackHost._rack_apply`; no
  argument flips, `true`/`false` sets), so a guest's press is the host's and every player's key shows it. Off, the host stops
  the engine process (silence, no processor, held notes let go), `_rack_wake` refuses to start it, and the patch is kept; on,
  the next key or take wakes it as before. The control tool is `rack_power`.
- **The clock follows the song closely.** `RackVoice` tells the engine the song's place (`sync BEATS`) every 50 ms while it
  plays. The engine jumps if it is more than a quarter beat off (a seek or a loop) and otherwise eases the difference away at
  up to 2 % of the tempo, so no pulse is cut or doubled. CLOCK's **OFFSET** knob (ms, -100..200) runs its pulses early to
  cancel the rack's delay behind the mix (the cushion, above): set it by ear against a click.

## How to extend it

- **A new module from existing ones (composite)**, **a skin**, **a preset**: a mod folder, `docs/mods.md` 9 "How to
  add a mod". No code.
- **A new engine module (native DSP)**: C++ in `native/rack/` against a pinned submodule, register it in the engine,
  regenerate `core/music/rack/modules.json` from `rack --describe`, add a manifest entry (`sound.kind: engine`) with
  a skin, add a notice to `THIRD_PARTY_NOTICES.md`. Run `_test_a_rack_catalogue_is_the_engines_own_description`
  (needs the built engine).
  A module that needs vendored sources lists them in `native/rack/libs/<name>.txt` (globs under
  `vendor/mutable-eurorack/`) and lives in `native/rack/modules_<name>.cc`, and `tools/rack_build.sh` picks both up
  (`RACK_ONLY="warps braids"`, `RACK_BUILD_DIR` and `RACK_BIN` build a few modules into a private binary while
  others are being written; a source named in two lists is compiled once).
- **After adding an engine module** run `tools/rack_sync_manifest.py` (it rewrites `modules.json` from `rack --describe`,
  and gives each module no mod dresses yet a skin entry in the mod of the library its DSP comes from: `OWNER` in the
  script, daisysp by default; taglines from `tools/rack_taglines.json`; a module with fewer than two knobs gets no
  `pad_knobs`). Then write its `core/music/rack/help/<type>.json`. Skins must be unique per type (a test).
  The 30 modules of `native/rack/modules_daisy.cc` are the rest of the pinned DaisySP that is not already a module;
  MARBLES (`modules_marbles.cc`) is Mutable's random sampler. Not used: FRAMES (fixed-point, hardware-timed), YARNS
  (KEYS covers it), GRIDS and EDGES (GPL-3.0).
- **Screens** (SCOPE, SPECTRUM, VECTOR, METER, PLASMA): a module whose `Module::scope` fills 96 numbers, sent to the
  room every third tick and drawn by `ScopeScreen` in the mode `ScopeScreen.mode_of(type)` gives (wave, bars, X-Y,
  level bars, plasma). They are always processed, heard or not (`Rack::rebuild`), and are four columns wide
  (`RackLayout.SCOPE_WIDE`). A new one: a mode in `ScopeScreen`, an entry in `mode_of`, a branch in `Rack::rebuild`.
- **AIRWINDOWS** is one module for all of Airwindows' effects (`vendor/airwindows`, MIT). `tools/airwindows_gen.py`
  writes, at build time, a wrapper per plugin that compiles it in its own namespace against `native/rack/aw/audioeffectx.h`
  (a small host stand-in, not Steinberg's header) and the table the module reads; nothing of the plugins is copied.
  The module has the effect knob and twelve parameters A..L (an effect with more takes the first twelve).
  `core/music/rack/airwindows.json` (from `rack --describe-airwindows`) holds each effect's parameter names and
  starting values; a test holds it to the engine. Moving to a new Airwindows commit: bump the submodule, check its
  LICENSE and file headers, rebuild, regenerate that file and `modules.json` (the effect knob's names).
  Each effect is also a rack module of its own: `tools/airwindows_mods.py` writes `mods/builtin/airwindows/mod.json` with
  532 composites (`builtin.aw.<effect>`: the engine module with EFFECT and the starting values set, knobs named for the
  effect's parameters, kinds and text from `airwindows_help.json`); `--check` is what the test runs. The engine's own
  `builtin.airwindows` stays as their base, in the hidden group `Internal`. Rerun it after either JSON file changes.
- **Finding a module**: 532 effects do not fit on palette keys, so the AIRWINDOWS key (the finder on that group) and the MODULES key (the finder on every module) open
  `RackFinderScreen` (search by name, kind, knob or blurb; group and kind filters; ADD). The ranking and filtering are
  `RackFinder` (tested apart from the screen). A group named in `RackWallKeys.FINDER_GROUPS` opens the finder, not keys.
- **A custom face** (`out`, `scope`, `seq` are built in): a `face` kind in the module entry, drawn by
  `RackWallModules`; user mods may only use `standard`.
- **A new op on the patch**: add it to `RackPatch.answer`, handle it in `RackVoice` if it reaches the engine, and add
  the verb arguments only if the `rack` verb's shape changes (`SessionBase.ROOM_VERBS[&"rack"]` is `[op, args]`).

## Tests

`tests/rack_stream_tests.gd` (the render stays clean, the reader takes the whole stream, the cushion), `tests/rack_mod_tests.gd`, `rack_composite_tests.gd`, `rack_gaps_tests.gd`, `rack_patch_file_tests.gd`,
`sample_mod_proof_tests.gd`, and the `_test_*rack*` groups in `tests/run_tests.gd`. Known failure on this branch:
RackWall "no two faces share a plane" (42 checks, `docs/refactor_loop.md`). `tools/rack_probe.sh` renders one Plaits
note from the submodule; `tools/rack_build.sh` builds the engine; `tools/patchbay_stress.tscn` stresses the patch
wall.
