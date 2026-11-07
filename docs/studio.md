# The studio

`Studio` (`scenes/studio.gd`, 781 lines) is the room: a `Node3D` built in code, never a `.tscn`, because nothing in
it has a fixed shape (the console is as wide as the project has tracks, the rack as tall as it has plugins). It
holds the single-owner state and one `RefCounted` helper per responsibility. The helpers hold `var studio: Studio`,
keep no state of their own beyond a few caches, and the studio keeps a one-line delegate only for a name another
file, a string (`call`, `has_method`) or a probe reaches. Inside the studio and its helpers, calls go straight to the
helper (`studio.surface_host._build_surfaces()`), not through a delegate.

## How it starts

`scenes/bootstrap.gd` (switches in `scenes/bootstrap_args.gd`) decides what this launch is (solo, host, guest, AR,
VR, flat, headless), starts `Session` and the DAW backend, creates `Studio.new()`, sets `medium`, `xr_bootstrap` and
`ergonomics` before it enters the tree, and adds it. `Studio._ready()` then builds, in order: the environment
(`VenueLook`), the venue (`VenueSwitch`), the anchors (`SurfaceHost`), the furniture (`FurnitureHost`), the surfaces
(`SurfaceHost`), the point-and-mark pad (`StationHost`), the walker (`PlayerHost`), the items (`ItemHost`), the Tour
case (`TourRoom`), the Rig Roulette station (`RollRoom`), the pads (`ViewHost`). AR builds only the items and the
passthrough: the room is the real one.

The three anchors a surface hangs from are `screen_stage` (follows the head), `room_anchor` (a calibrated physical
frame) and `studio_set` (the virtual room); `SurfaceMount` (`core/presentation/`) picks one per viewer.

## The helpers

All in `core/room/` unless noted. Field name on `Studio` in brackets.

| Helper (field) | Owns |
|---|---|
| `SurfaceHost` (`surface_host`) | the anchors, the surfaces built on them (console, timeline, patchbay, rack wall, tape deck, stage table, TV ...), fingertips and chord hand, lamp stands, looms |
| `FurnitureHost` (`furniture_host`) | the control room's trolleys (stage, EQ wall, deck, rack, patch stand), the levels niche, the TV mount, the live pieces, hood signs |
| `RoomRows` (`room_rows`) | the room on the wire: `room_state` (what the host publishes), `apply_room` (what a guest adopts), `_on_room_asked` (every verb a player asks of the room) and the prediction that goes with it |
| `StationHost` (`station_host`) | sitting, walking to a seat or station, the station board, the desk wing, point-and-mark |
| `TabletHost` (`tablet_host`) | plugin tablets and track racks: tear off the wall, stand in the room, put back, remember |
| `SignalViews` (`signal_views`) | the signal view, look-solo, tracing a signal to its source |
| `RackHost` (`rack_host`) | the rack and the modular room: building, the annex, world sockets, `ask_rack`, recording the rack, its keys |
| `SamplerHost` (`sampler_host`) | arming the sampler, sampling a take from an item, platter and scratch, other players' hits |
| `MixFollow` (`mix_follow`) | the personal mix and the head: phones, listening, the track under a ray, clap, lean |
| `PlayerHost` (`player_host`) | the player's own hands and body: debounced saves and publishes, headphones, pockets, the walker |
| `InputHost` (`input_host`) | `_unhandled_input`, the keys it reads, the fast-path hit voices |
| `ViewHost` (`view_host`) | `_process`, gliding surfaces, text scale, the camera and viewport, the desk pads |
| `VenueLook` (`venue_look`) | environment and house light, studio lamps, ceiling, where the player may walk |
| `VenueSwitch` (`venue_switch`) | set/choose venue, the roulette room and its door, venue and set transforms, role change, fitting the stand and the room to the session |
| `ItemHost` (`item_host`, `core/items/`) | the room's items: homes, building, minting cassettes, giving to a peer |
| `PatchHost` (`patch_host`, `core/session/`) | jacks and patching, who is told, wrist jacks, patch lines, ON AIR |
| `TourRoom` (`tour_room`, `core/tour/`) | what the room does for a Tour run (`Tour` autoload owns the run) |
| `RollRoom` (`roll_room`, `core/rig_roulette/`) | Rig Roulette: the wheels, the roll board, rolling and undoing |
| `PieceHost` (`pieces`, `core/layouts/`) | standing the layout's pieces (see `docs/layouts.md`) |
| `LayoutEdit`, `RoomDeltas` (`layout_edit`, `room_deltas`, `core/layouts/`) | the host's edits of the room and the room's saved delta |

Single-owner state that stays on `Studio`: the venue, the floor plan, the mount, the camera, the walker, the DAW
surfaces, the live pieces and their ids. Other classes the studio uses directly: `FloorPlan` and `Trolley`/`Caster`
(what stands on the floor and can be pushed), `Neighbourhoods` (stations in named clusters, from the layout's
`groups`), `SessionLayout` (where the furniture stands for this session size), `Stations` (the station rows).

## How it fits

- **Down to the venue**: `VenueSwitch` makes `Venue.make(id, variant)`; the venue answers spots and walkable rooms.
- **Up to the session**: a player's ask goes `Session.ask_room(verb, args)` to the host, which emits `room_asked`;
  `SurfaceHost` connects that to `RoomRows._on_room_asked`; the host's studio changes the room and publishes it,
  guests adopt it in `apply_room`. See `docs/session.md`.
- **To the audio and the DAW**: surfaces read and write through the `DAW` autoload; the rack goes through
  `RackHost` to `RackVoice` (`docs/rack.md`).

## How to extend it

Add behaviour to the studio:

1. Does it belong to an existing responsibility above? Add the method to that helper, calling `studio.<state>`.
   Only if a file outside the studio, a probe or a string call reaches it by name, add a one-line delegate on
   `Studio`.
2. A new responsibility: add a `RefCounted` class with `var studio: Studio` and `_init(of: Studio)`, a field on
   `Studio` (`var thing := Thing.new(self)`), and move the body in whole. Keep `studio.gd` under the 800-line
   limit (`tools/quality_check.sh`).
3. A new piece of furniture or a thing that stands in a room is a piece, not a studio method: `docs/layouts.md`
   ("How to add a piece").
4. A new room verb: `docs/session.md` ("How to add an rpc verb").
5. Add a doc comment to every new public function and signal; `tools/quality_check.sh --docs` lists the ones
   missing.

## Tests

`tests/run_tests.gd` builds real `Studio` instances (`Studio.new()`, `_floor_studio()`), so a targeted run such as
`DAWLINGS_TESTS=_test_you_walk_into_the_room_and_not_through_it` is the check for most helpers. See
`docs/testing.md`. Probes: `tools/probe/walk_map.tscn` (floor and walls of every venue), `tools/layout_dump.tscn`.
