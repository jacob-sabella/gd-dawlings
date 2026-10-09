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

- [ ] Zones: give `Venue` the activity-zone contract above, and dress all three existing venues
      with all five zones (empty, but each reads as a place for its activity). Test it.
- [ ] Venue variants: a variant id on the venue, chosen by the host, carried in `Session.room`,
      saved in the host's layout; the stage manager's venue row grows a variant picker.
- [ ] Studio: a live room behind glass beside the control room, holding the drum riser and the
      vocal booth zones. Make it the studio's second variant.
- [ ] Warehouse loft at night: brick, steel, tall windows on a city, a mezzanine for the matrix.
- [ ] Cabin in snowy woods: timber, a stove's glow, snow past the windows, the synth by the window.
- [ ] Rooftop at dusk: parapet, water tanks, a city skyline, string lights.
- [ ] Space station: a ring corridor, a planet through the floor glass, the matrix in zero-g.
- [ ] Underwater dome: caustics, kelp, light from above, a sub bay as the booth.
- [ ] Jazz club after hours: stage with the drum riser, booths, a bar, one spot.
- [ ] Pass over every venue: shoot them side by side and even out anything that drifted (light,
      scale, how distinct they are).
