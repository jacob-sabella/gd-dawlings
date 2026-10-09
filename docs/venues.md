# Venues

A venue is the world the studio stands in. The gear, the stands and lamps, wherever each has been
pushed, and what is focused all belong to the studio. They are identical in every venue. A venue
supplies everything else: the floor, what lies past it, the sky, the air, the key light and the
colour the lamps shine.

| id | Title | What it is |
|---|---|---|
| `studio` | Studio | The control room: parquet, treated walls, downlights, a rug. Through its open back, a taller live room with a slatted walnut wall holds the activity zones: a carpeted riser, a glass booth with a mic stand, an LED-and-brass square for the lattice, an oak table under a pendant, and a keyboard stand under a rack of module lights. The default. |
| `grid` | Grid | Synthwave. A mirror floor ruled in neon, wireframe mountains, a striped sun at dusk, and two wire solids turning in the sky. The zones are black glass edged in neon; the lattice is a faint violet cube. |
| `chalk` | Chalk Zone | A blackboard the size of the world. Neon chalk doodles hang at every distance and there is dust in the air. The working floor is outlined in chalk. Each zone is taped out on the floor in its own colour, with what will stand there sketched in the air. |

## Changing it

- **V** cycles the venues.
- **Tab** opens the stage manager; its first row picks a venue.
- `--venue <id>` on the command line applies for one run only and is not saved.
- Otherwise the choice is saved in the layout profile (`[profile] venue`) and comes back next session.

On your own the choice is yours. In a session it is the host's: the venue is part of the room
everyone stands in (`Session.room`), a guest is shown it and cannot change it, and the guest's own
choice comes back when it is on its own again. In AR there is no venue at all, because the room
is the real one.

Iterating on venues has its own brief: `docs/environments_loop.md`. `tools/light_check.sh` is the
light budget every venue must stay within.

## Contract

`Venue` (`core/venues/venue.gd`) is a `Node3D` the studio adds as a child. Before it enters the
tree, `Studio.set_venue` does three things:

1. Builds a fresh `Environment` with the house defaults (glow, SSAO) and hands it to
   `dress(env, key)`. The key light has already been reset to the house key there. A venue states
   only what differs.
2. Restyles each floor lamp through `lamp_colour` and `lamp_energy`. The lamps are furniture;
   their light belongs to the venue.
3. Sets `rich` when the full desktop renderer is running (SDFGI, SSR, volumetrics). A venue must
   still look right without it, because a headset runs the mobile renderer.

Every frame the studio feeds the master level (0..1) to `pulse()`:

- The grid brightens and ripples out from the desk.
- The chalk glows harder.
- The doodles near the desk jump.

Every venue keeps the same working footprint (`Venue.footprint_corners()`), because the furniture's
floor plan is that rectangle. A venue without walls marks the footprint instead: a lit border on
the grid, a chalk outline in the chalk zone.

### Activity zones

Every venue also leaves room behind the mix position for the activities that are coming: the
brick MIDI editor, the matrix sequencer, the drum kit, the vocal booth and the synth.
`Venue.zones()` returns them as `id -> AABB` in studio space. The ids are in `Venue.ZONE_IDS`
and the layout at the base width is in `Venue.ZONES`. When the desk widens the room, each zone
steps outward on its own side.

A venue dresses each zone as one node named `Zone_<id>`, standing at the zone's floor centre.
The dressing shows what will stand there without building it. `ZoneKit`
(`core/venues/zone_kit.gd`) has the shared shapes: riser, booth, table, keyboard stand, mic stand,
floor tape, box edges, and a zone light with its fitting. Each venue supplies its own materials.
The studio puts its zones in a live room: `LIVE_ROOM_HALF` either side, back to `LIVE_ROOM_BACK`,
`LIVE_ROOM_HEIGHT` tall.

You can walk to the zones in every venue. `Venue.back_of_house()` is the floor behind the
footprint, and the walker's walls stand round the footprint and that floor together
(`Walker.walkable`, `Walker.outline`). Where the two meet there is an open doorway. Furniture
still stays inside the footprint.

What stands in a zone is solid where it looks it. `Venue.zone_solids()` hands the walker
footprints with a height (`Walker.fixed`). The studio's riser, table, keyboard stand and booth
walls are solid, and the booth has a doorway. The grid's riser, table and stand are solid, but its
booth is only neon edges, so it has no walls. The chalk zone's sketches are walked through. The
walker steps up onto anything no taller than `Walker.STEP_HEIGHT`, which includes the riser.

## Adding one

1. Subclass `Venue` and override `venue_id`, `dress`, and optionally `lamp_colour`,
   `lamp_energy` and `pulse`.
2. Build the geometry in `_ready`. It must include a floor plane at y = 0 at least as wide as the room.
   It must also dress all five zones (see above) and keep its scenery out of them.
3. Add the id to `Venue.IDS`, `Venue.make` and `Venue.make_title`.

`_test_venues_change_the_world_and_not_the_setup` then covers it automatically:

- no gear moves
- nothing else is added or lost
- there is a floor
- the choice persists

The z-fight scan runs over it too. `_test_every_venue_leaves_room_for_the_activities` checks
that every zone is there, is big enough, clears the footprint and the other zones, and is
dressed, at the base width and at a widened one.

## Chalk

`Chalk` (`core/venues/chalk.gd`) turns polylines into stroke meshes. `chalk_stroke.gdshader`
widens them on the GPU, either toward the eye or flat along the ground. Every stroke shares one
material, so the whole zone can be pulsed with a single uniform. The doodle alphabet includes
star, spiral, cloud, moon, lightning, heart, planet, note and sparkle. Each is drawn twice with a
smooth wobble, as a hand would draw it.
