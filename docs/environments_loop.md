# Environments loop

The brief for iterating on the world the studio stands in. Read it at the start of every pass,
do ONE item from the queue at the bottom, and leave the queue truer than you found it.

Started with `/loop iterate on environments: follow docs/environments_loop.md`.

## Where this is going

A real production studio, not a mixing desk floating in a skybox. Many environments, each with
variations in its structure, and room in every one of them for the things people will do there
besides mix. Those activities are coming later and are NOT built by this loop, but every
environment built now has to leave them somewhere to go:

| Activity | What it is | Room it needs |
|---|---|---|
| Brick MIDI editor | Notes as bricks on a table you build a phrase out of | a waist-high table about 2 x 1 m, walk-around clearance |
| Matrix sequencer | An N x N x N lattice of cells you light to sequence | a clear volume about 3 x 3 x 3 m, viewable from all sides |
| Drum kit | A virtual kit you play with hands or sticks | a riser about 2.5 x 2.5 m, ideally treated / separable |
| Vocal mics | A mic that appears where you want to sing, on demand | a booth or a dead corner about 2 x 2 m, ideally behind glass |
| Synth | A keyboard and modules to play and patch | a stand about 1.5 m wide against a wall or a rack wall |

The mix position, the console and the gear's working footprint (`Venue.footprint_corners()`,
`Studio.ROOM_WIDTH` x `Studio.ROOM_DEPTH`, widened with the desk by `SessionLayout`) stay where
they are. Activity space goes AROUND it: a live room through a window, a booth off one side, a
riser behind, a mezzanine above. A venue declares these as **zones** -- named, sized, empty and
dressed so they read as "something goes here" (a riser, a booth with a stand, a cleared floor
with marks), never as a broken empty corner. When the first pass needs zones, give `Venue` a way
to report them (e.g. `func zones() -> Dictionary` of id -> AABB in studio space, the activity
kinds above as ids) and test that every venue has all five and none overlaps the footprint.

## What "good" looks like

- **Dark and moody, lit like a room people work in at night.** Light comes from things that are
  lights: lamps, practicals, screens, LEDs, a window. No flat fill, nothing white-hot, no pools
  of glare on the gear. `tools/light_check.sh` must pass for every venue on every pass; it is the
  measurement of "the lights are too bright", which is the one complaint already made twice.
  Never raise its limits to make a pass go green -- turn the light down.
- **Every environment distinct at a glance**, from the seat and from across the room. A palette,
  a material language and a silhouette of its own.
- **Structure varies, not just paint.** Ceiling height, walls vs open, a window into a live room,
  a booth, a mezzanine, columns, a raised floor, where the light comes in. A venue can have
  variants (a seed or a variant id) that rearrange its structure while keeping the footprint and
  the zones' contract. A variant is part of the room the host keeps: it travels in
  `Session.room` beside the venue, and only the host chooses it.
- **Looks right without the rich renderer.** A headset runs the mobile renderer: no SDFGI, no
  volumetrics. `rich` is false there; check the venue still reads (shoot once with the rich
  path off if the change leans on it).
- **Cheap.** Keep the frame budget: `tools/budget.sh` before and after anything heavy (many
  meshes -> MultiMesh / MeshBank; animated things -> shaders, not per-frame GDScript).

## Ideas to draw from

Environments: a live room + control room behind glass (the real thing); a converted warehouse
loft at night with a city through tall windows; a cabin in snowy woods; a rooftop at dusk; a
desert under stars; an underwater dome; a space station with a planet below; a cathedral hall; a
jazz club after hours; a forest clearing with fireflies; a vaporwave mall; a neon arcade; a barn
studio; a zen garden. Variants for the studio venue: control room only; control room + live room
through glass; + vocal booth; + machine room; high ceiling with clerestory light; a lounge end.

## One pass

1. Read this file and `docs/venues.md`. Pick the FIRST unchecked item in the queue. If it needs
   the user (a taste call between options, anything outward-facing), park it in
   `docs/loop_backlog.md` under "Waiting on the user" with what is needed, and take the next.
2. Build it. Venues live in `core/venues/`; follow `docs/venues.md` "Adding one" (IDS, make,
   make_title). Shaders in `core/venues/shaders/`. Match the surrounding code's comments and
   naming; no magic numbers without a line saying why.
3. Look at it. `tools/light_check.sh <venue>` (pictures land in
   `~/.cache/reaper-3d/shots/light_check/`), plus any framing that shows what changed
   (`SHOT_CAM=yaw,pitch,dist,tx,ty,tz`, `--no-hud`, `--place timeline=studio`). Read the pictures
   and judge them honestly against "what good looks like"; iterate until they are.
4. Test it. Add a check for each new behaviour in `tests/run_tests.gd` (zones exist and clear the
   footprint, a variant keeps the floor plan, a new venue cycles, and so on). Then
   `tools/verify.sh` (0 failed, no SCRIPT ERROR) and
   `flock ~/.cache/reaper-3d/shared.lock tools/session_probe.sh` (host and guest 0 failed; the
   audio-timing checks occasionally flake -- rerun before believing them).
5. Commit: a small plain-English message saying what was wrong or missing and what is there now.
   No attribution lines. Never push.
6. Send the user one or two pictures (`magick x.png -quality 82 x.jpg`, SendUserFile, a one-line
   caption).
7. Tick the item off below, add anything the pass taught you to the queue, and update the venue
   table in `docs/venues.md`.

## Rules that do not bend

- Windows offscreen (`tools/shot.sh` / `tools/offscreen.sh` do it). Never move the user's
  workspace. Never kill a godot this loop did not start.
- Audio: `PULSE_SINK=reaper3d_null PIPEWIRE_NODE=reaper3d_null` on every run, and nothing that
  plays through the speakers. Never touch the user's volumes or mutes without asking.
- Never write the real `user://layout_profile.cfg`, `user://ghost_look.cfg` or `user://body.cfg`
  (no `--height` in shots). Tests use a test save path.
- Never touch `~/.config/REAPER`. Wrap rig use, probes and shots in
  `flock ~/.cache/reaper-3d/shared.lock`. Outputs under `~/.cache/reaper-3d/`.
- `hardware/` must not reference `Session`, `Presentation.`, `Medium.`, `XRServer`,
  `is_authority` or `multiplayer.` in code lines.
- The gear and its footprint do not move for a venue; `_test_venues_change_the_world_and_not_the_setup`
  must stay green.

## Queue

- [x] Zones: give `Venue` the activity-zone contract above, and dress all three existing venues
      with all five zones (empty, but each reads as a place for its activity). Test it.
      (`Venue.zones()`, `ZoneKit`, a live room behind the studio's control room; `light_check`
      grew a `back` view of the zones.)
- [x] Walk into the zones. The walker's walls are still `floor_plan.bounds`, which is the
      footprint, so every zone can be seen but not reached on foot. Give the venue a walkable
      outline (the footprint plus its zones' space; in the studio, the control room plus the live
      room) and build the walker's walls from it. Furniture stays in the footprint.
      (`Venue.back_of_house()`, `Walker.walkable` / `Walker.outline`.)
- [x] Make the zone dressing solid where it should be: you walk through the booth's glass, the
      table and the keyboard stand, and straight through the riser instead of up onto it. Give a
      zone's dressing footprints the walker collides with (the booth's walls with its doorway,
      the table, the stand) and make the riser a step you can walk up onto.
      (`Venue.zone_solids()`, `ZoneKit.solids`, `Walker.fixed`, `Walker.STEP_HEIGHT`.)
- [x] Little things seen from inside the booth: the empty mic stand's boom crosses your eyes when
      you stand in the middle of the booth (stand it nearer the glass, boom toward the room), and
      the stand is not solid.
      (`ZoneKit.MIC_AT` / `MIC_YAW` / `MIC_HEIGHT`: by the glass, boom reaching in, clip at mouth
      height; solid in the studio and the grid; the chalk sketch matches.)
- [x] The studio's live room is very dark from the opening (`light_check` back view, mean 0.02,
      against about 0.18 for the open venues). It reads as moody up close, but the corners are
      black. Add one or two practicals (a wall sconce by the booth, a lamp by the keys) rather
      than more ceiling cans.
      (Four brass sconces washing up and down the walls, two of them grazing the slats. The back
      view's mean went from 0.018 to 0.026; most of that frame is the unlit ceiling. It reads as
      a room at night now, not a void.)
- [x] Venue variants: a variant id on the venue, chosen by the host, carried in `Session.room`,
      saved in the host's layout; the stage manager's venue row grows a variant picker.
      (`Venue.VARIANTS` / `variant` / `variant_titles`, `Studio.choose_variant`, the room's
      `variant`, `LayoutProfile.venue_variant`, `--venue grid:1`, the stage manager's "arranged"
      row. The first one with two is the grid: Highway and Downtown, a city drawn as one
      MultiMesh. `light_check` shoots every arrangement.)
- [x] Studio: a live room behind glass beside the control room, holding the drum riser and the
      vocal booth zones. Make it the studio's second variant.
      ("Live room beside": `StudioVenue.BESIDE`, a 6 m side room through a window and a door,
      `Venue.rooms()`. The walker now takes its old walls out of the tree at once, or a room
      rearranged mid-frame kept them standing in its new doorways.)
- [x] The studio's side room is lit but its walls are bare plaster in the dark (inside view mean
      0.04). Give it treatment of its own (bass traps in the corners, a cloud over the kit) so
      it reads from the door; and `light_check` has no view of it yet -- add one for `studio:1`.
      (Three corner traps, solid; four panels in rust and slate; lighter warm plaster and
      brighter sconces, because fabric drinks the light. `light_check`'s `side` view, 0.051.
      No cloud: it would have shaded the kit's own spot.)
- [x] Warehouse loft at night: brick, steel, tall windows on a city, a mezzanine for the matrix.
      (`LoftVenue`: one walkable room round the desk, columns and a ladder you walk round, a
      gallery with festoon bulbs along the back wall, under-gallery grazers on the brick.)
- [x] Loft: the gallery is scenery. Let the walker climb the ladder onto it and look down on
      the lattice (a second floor level in the walker), or add a "Loft, gallery" arrangement.
      (The ladder is a stair of solids, each a step high (`LoftVenue.stair_steps`); the deck and
      its rail are solids too. The walker's walls were 4 m tall and you walked over them off the
      gallery: they are 20 m now. `--walk x,z,yaw,pitch,y` stands you on a floor above the ground.)
- [x] Cabin in snowy woods: timber, a stove's glow, snow past the windows, the synth by the window.
      (`CabinVenue`. First venue with real models: a stove and firs scripted in Blender, a
      rocking chair and lanterns from Poly Haven, all in `tools/blender/`. `ShellKit` now holds
      the wall-with-windows both the loft and the cabin use. `VENUE=` on `tools/budget.sh`.)
- [x] Cabin: the back view is the darkest of any venue (0.034). A second wall lantern pair or
      a lit shelf of jars along the back wall; and a rug under the rocking chair.
      (A shelf of Blender-lathed jars with candles in some, two soft washes under it, and a
      braided rag rug of five rings. Back view 0.034 -> 0.045.)
- [x] Cabin follow-up: the candle jars read as flat white blocks up close; give the candle
      glass a warm tint with a brighter wick inside, and let the candle washes flicker with the
      fire.
      (Open jars of smoky glass, a stub of wax and a flame in each; the washes gutter, each to
      its own beat. The preserves' glass roughened so it stops flaring white.)
- [x] Rooftop at dusk: parapet, water tanks, a city skyline, string lights.
      (`RooftopVenue`, a `dusk_sky` shader, `water_tank.glb` scripted in Blender. The city's
      tall towers stand back from the building and out of the line to the sunset, so the view
      over the railing is over lower roofs into the afterglow. seat / wide / back 0.143 / 0.083 /
      0.061; 302k primitives wide.)
- [x] Rooftop: variants. "Golden hour" (the sun still up, low, long shadows of the railing on
      the deck) and "Night" (the sky gone dark, the city and the strings doing all the work).
      (`RooftopVenue.EVENINGS`: sky bands, sun and disc, stars, ambient, haze, key and window
      brightness per evening. Golden hour wide 0.22 is the brightest view of any venue, just
      inside the budget; night's back view 0.034 is as dark as the cabin's was.)
- [ ] Rooftop at night: the back view is dark (0.034); a lamp on the stair house is all that
      reaches it. Give the night its own touches -- the strings brighter, a lit window in the
      stair house door, a red aircraft light on each water tank.
- [ ] Rooftop: the deck reads red-brown under the strings; a greyer board texture (or a
      Poly Haven decking) would read as weathered hardwood. And the roof beyond the terrace is
      one flat black: gravel ballast, a few vents and a skylight would give it something.
- [ ] Space station: a ring corridor, a planet through the floor glass, the matrix in zero-g.
- [ ] Underwater dome: caustics, kelp, light from above, a sub bay as the booth.
- [ ] Jazz club after hours: stage with the drum riser, booths, a bar, one spot.
- [ ] Chalk zone arrangements: chalk has only one. A second, e.g. the board as a ceiling-high
      wall behind the zones, or the doodles gathered into a room-sized sketch of a studio.
- [ ] Pass over every venue: shoot them side by side and even out anything that drifted (light,
      scale, how distinct they are).
