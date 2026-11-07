# The rack: the modular room, the rack wall, the registry

The modular room is a rack of synth modules patched with cables, in a room of its own built onto the side of every
venue. A module is a mod entry (`docs/mods.md`); the patch is a file; the sound is a separate process on the host.
Design history and the saved-patch rules are in `docs/mods.md` 6; the older description of the room is
`docs/architecture.md` ("The modular room"). This page is the map.

## Files

| Layer | Files | What |
|---|---|---|
| Mods | `mods/builtin/{core,daisysp,mutable,presets}/mod.json`, `core/mods/` | the 29 modules, their skins and 17 presets as manifests; the registry |
| Description | `RackCatalogue`, `RackSkin`, `RackModuleDef`, `RackCurves`, `core/music/rack/modules.json` | what modules exist, their jacks and knobs (from the engine snapshot), how they look, composite resolution |
| Patch (data) | `RackPatch`, `RackPatchFile`, `RackAutosave`, `RackGaps`, `RackExpansion`, `RackLayout`, `RackMood` | the patch as a dictionary `{modules, cables}` and every edit as one `answer(op, args)`; v2 file format; `user://patches/_current.patch.json`; what this machine cannot show; composites expanded to engine modules; where modules sit in the case (`COLS` x `ROWS`); the glow per venue |
| Sound (host only) | `RackVoice`, `RackEngine`, `native/rack/` | the engine as a process (`rack` binary built from pinned `vendor/` submodules by `tools/rack_build.sh`), told the patch as text lines, heard back as stereo float32; played through a track of the song |
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

## How to extend it

- **A new module from existing ones (composite)**, **a skin**, **a preset**: a mod folder, `docs/mods.md` 9 "How to
  add a mod". No code.
- **A new engine module (native DSP)**: C++ in `native/rack/` against a pinned submodule, register it in the engine,
  regenerate `core/music/rack/modules.json` from `rack --describe`, add a manifest entry (`sound.kind: engine`) with
  a skin, add a notice to `THIRD_PARTY_NOTICES.md`. Run `_test_a_rack_catalogue_is_the_engines_own_description`
  (needs the built engine).
- **A custom face** (`out`, `scope`, `seq` are built in): a `face` kind in the module entry, drawn by
  `RackWallModules`; user mods may only use `standard`.
- **A new op on the patch**: add it to `RackPatch.answer`, handle it in `RackVoice` if it reaches the engine, and add
  the verb arguments only if the `rack` verb's shape changes (`SessionBase.ROOM_VERBS[&"rack"]` is `[op, args]`).

## Tests

`tests/rack_mod_tests.gd`, `rack_composite_tests.gd`, `rack_gaps_tests.gd`, `rack_patch_file_tests.gd`,
`sample_mod_proof_tests.gd`, and the `_test_*rack*` groups in `tests/run_tests.gd`. Known failure on this branch:
RackWall "no two faces share a plane" (42 checks, `docs/refactor_loop.md`). `tools/rack_probe.sh` renders one Plaits
note from the submodule; `tools/rack_build.sh` builds the engine; `tools/patchbay_stress.tscn` stresses the patch
wall.
