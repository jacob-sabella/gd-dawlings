# Documentation index

## Where do I add X

| To add | Do this | Page |
|---|---|---|
| a mod (module, skin, preset, effect) | a folder with `mod.json` under `mods/` (or `mods_examples/` as the model), no code for a composite | `mods.md` ("How to add a mod") |
| a native rack module | C++ in `native/rack/`, regenerate `modules.json`, manifest entry, notice | `rack.md` |
| a piece (a thing that stands in a room) | `PieceDef` data, a builder in `PieceBuilders.BY_NAME` if it needs code | `layouts.md` ("How to add a piece") |
| a venue | layout JSON + shell class in `ShellBuilders.BY_NAME` | `venues.md` ("Adding one"), `layouts.md` |
| a room-scale piece | a piece with a footprint in the layout, `LayoutEdit` ops if the host may move it | `layouts.md` |
| an rpc verb (a guest asks the room) | `ROOM_VERBS`, an arm in `RoomRows._on_room_asked`, `room_state`/`apply_room` | `session.md` ("How to add an rpc verb") |
| a raw network message or channel | a `Session*` helper, the `@rpc` delegate in `session.gd`, a constant in `SessionBase` | `session.md` |
| behaviour in the studio | the helper that owns it; a new `RefCounted` helper only for a new responsibility | `studio.md` ("How to extend it") |
| an item kind (a thing to hold) | `ItemRoom.make` arm, `ItemRoom.KINDS` | `item_room.md` |
| a pad deck feature | | `pad_deck.md` |
| a tool or probe | script with a header, `offscreen_run` for windows | `tools.md` |
| a test | a `_test_*` function, called from `run_tests.gd` | `testing.md` |

Every new public class, signal and non-trivial function gets a `##` comment; `tools/quality_check.sh --docs` lists
what lacks one.

## Pages

**How the game is built**

- `architecture.md` - the whole game: layers, the DAW backends, the rooms, the modular room (older, long).
- `studio.md` - `Studio` and its helpers; how a launch builds the room.
- `session.md` - the session autoload and its helpers; how a change to the room flows; adding a verb.
- `multiplayer.md` - the ways in (LAN, address, join code) and what is shared.
- `realms.md` - every game a realm: the lobby, visiting and going home, copying a rack, room or song between realms.
- `transport.md` - the DAW/Reaper wire.
- `colocation.md` - the physical-room frame for AR.
- `rack.md` - the modular room, rack wall, engine.
- `mods.md` - the mod registry, manifests, composites, patch file, the MODS screen (F5); decisions; how to add a mod.
- `layouts.md` - layout data, pieces, made rooms, deltas, sharing; decisions.
- `venues.md` - the venues, their shells and light; how one is made and added.
- `pad_deck.md` - the pad deck (the Tv surface and its pads).
- `item_room.md` - the item room and item kinds.
- `sampling_station.md` - sampling from a take or an item.
- `singer.md` - CHIMERA's voice: the vocal booth's singer, the rack's VOICE, the bestiary.
- `workshop.md` - the Workshop (Claude building in the room).
- `mcp_assistant.md` - the control API (an MCP server in the game) and the room's assistant.
- `discord.md` - the Discord bridge.

**Doing things**

- `tools.md` - every script under `tools/`.
- `testing.md` - the suite, targeted runs, CI, known failures.
- `performance.md` - measured numbers, hot spots, what was and was not done.
- `session_walkthrough.md`, `walkthrough/`, `playtest.md` - walking through the game by hand.

**Plans, loops and history** (working notes; read for why, not for the current state)

- `refactor_loop.md`, `refactor_state_map.md` - the refactor queue, log, decisions, known failures.
- `daw_loop.md`, `daw_parity.md`, `desktop_first.md`, `flat_loop.md`, `spatial_loop.md`, `spatial_ideas.md`,
  `environments_loop.md`, `roulette_loop.md`, `items_loop.md`, `loop_backlog.md`, `patchbay_backlog.md`,
  `perf_backlog.md` - the loops and backlogs behind each area.
