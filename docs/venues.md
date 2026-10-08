# Venues

A venue is the world the studio stands in. The gear, the stands and lamps, wherever each has been
pushed, and what is focused all belong to the studio. They are identical in every venue. A venue
supplies everything else: the floor, what lies past it, the sky, the air, the key light and the
colour the lamps shine.

| id | Title | What it is |
|---|---|---|
| `studio` | Studio | The control room: parquet, treated walls, downlights, a rug. The default. |
| `grid` | Grid | Synthwave. A mirror floor ruled in neon, wireframe mountains, a striped sun at dusk, and two wire solids turning in the sky. |
| `chalk` | Chalk Zone | A blackboard the size of the world. Neon chalk doodles hang at every distance and there is dust in the air. The working floor is outlined in chalk. |

## Changing it

- **V** cycles the venues.
- **Tab** opens the stage manager; its first row picks a venue.
- `--venue <id>` on the command line applies for one run only and is not saved.
- Otherwise the choice is saved in the layout profile (`[profile] venue`) and comes back next session.

The choice is per participant and never replicated. Two people at one console can stand in
different worlds; nothing about the mix depends on the scenery. In AR there is no venue at all,
because the room is the real one.

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

## Adding one

1. Subclass `Venue` and override `venue_id`, `dress`, and optionally `lamp_colour`,
   `lamp_energy` and `pulse`.
2. Build the geometry in `_ready`. It must include a floor plane at y = 0 at least as wide as the room.
3. Add the id to `Venue.IDS`, `Venue.make` and `Venue.make_title`.

`_test_venues_change_the_world_and_not_the_setup` then covers it automatically:

- no gear moves
- nothing else is added or lost
- there is a floor
- the choice persists

The z-fight scan runs over it too.

## Chalk

`Chalk` (`core/venues/chalk.gd`) turns polylines into stroke meshes. `chalk_stroke.gdshader`
widens them on the GPU, either toward the eye or flat along the ground. Every stroke shares one
material, so the whole zone can be pulsed with a single uniform. The doodle alphabet includes
star, spiral, cloud, moon, lightning, heart, planet, note and sparkle. Each is drawn twice with a
smooth wobble, as a hand would draw it.
