# Rig Roulette room: loop log

Goal (the user, 2026-10-16): Rig Roulette is its own room, every venue has a way into it, and the roll has many options
(effect pool, how many, instruments, key and scale, tempo, seed, knobs, presets, history). Loop: cron e607c889, every 10 min.
Not pushed, no release.

## Survey (iteration 1)

- Today: `RigRouletteStation` (hardware/rig_roulette/) is a wall panel on the control room's back wall at
  `Venue.rig_roulette_spot()`, with a roll board (`roll_board.gd`, `board_feed.gd`). Studio builds it in
  `_build_rig_roulette_station`; the roll is `Studio.roll_rig` behind host-only `_on_rig_roulette_roll_requested`. Settings
  (count 1-3, pool CHARACTER/EVERYTHING, key lock, eligible tracks) are local to each client; only the host's ROLL reaches anyone.
  Tour rolls pedals off the run's seed in `TourProject.song_for` (`rig_count_for`) and must stay as it is.
- Places: the venue is one node, replaced by `Studio.set_venue(id, persist, variant)`; the host chooses it
  (`choose_venue`) and it is part of the room the host replicates (Session, "the room everyone is standing in").
  There is no way for two players to be in different places at once.

## Decisions

1. **The room is a place the whole band enters together.** Entering swaps the venue node for a `RouletteRoom`, the same way
   `choose_venue` does, so replication, avatars and walking already work and nobody is stranded. Honest limit: the band is in one
   place at a time (no one is in the room while others stay in the venue). That suits the use ("get some bois together and roll").
2. `RouletteRoom` is a `Venue` subclass registered with `Venue.make` and `Venue.is_known` but **not in `Venue.IDS`**, so the
   venue chooser and `cycle_venue` never land in it. The studio remembers the venue and arrangement it left; the way back returns
   there, to its door.
3. `Venue.rig_roulette_door() -> Transform3D` on every venue (default in venue.gd, overridden per venue to fit its look and clear
   of the desk, patchbay, roll board and walking paths). The door is a walk-up/click target. A test goes through every venue x
   arrangement for: on the walkable floor, reachable, clear of solids, not z-fighting (the room's probe).
4. The wall panel: becomes the room's setup wall (moved into the room); in the venues it leaves, the door takes its place,
   with the last roll written on the door's sign. The board that writes up a roll keeps working in the venue (it is what the band
   reads while playing); the room shows it large.
5. Roll logic moves out of Studio into core/rig_roulette/ (`RollSettings`: all options, to_dict/from_dict, validated;
   `RigRoll`: seedable, DAW-agnostic roll from settings + a project description). Settings live with the host and are replicated;
   guests see them and only the host changes them. Tour keeps its own path.

## Slices, in order

A. `RollSettings` + `RigRoll` in core/ with tests (today's behaviour reproduced exactly: count, pool, key lock, eligibility).
B. Room scene `RouletteRoom` and the travel (host-only enter/leave, remembered venue, replicated, probe).
C. `rig_roulette_door()` in every venue, dressed to fit, and the all-venue test.
D. The setup wall in the room using the settings; the old panel retired; ROLL ceremony (wheels, landings, sound).
E. Options: pool kinds/weights and presets, how much, key and scale, seed and re-rolls, knobs/chaos, instruments, tempo
   (the tempo roll needs beat-relative item times, so it may end up blocked), presets save/load, history and undo.
F. Polish: sound, easing, shots at 720p and from the seat, docs.

### 1. Survey and plan

Written. No code changed.

### A. Roll settings and the roll as plain logic

`RollSettings` (core/rig_roulette/roll_settings.gd: count, pool, key lock, seed; `to_dict`/`from_dict` hold every field to its
limits) and `RigRoll` (rig_roll.gd: `rng_for` seeded or fresh, `track_count`, `plan`, `pool_of`) work a roll out without applying
it. `Studio._roll_rig` now builds the settings from the panel (`RigRouletteStation.settings()`), plans, then starts the project
and puts the effects on, so the behaviour is as before (the existing `_test_rig_roulette_rolls_outside_tour` passes unchanged).
New test `_test_a_rig_roll_is_planned_from_its_settings` (same seed, same roll; limits; pools; locked key). Suite 10780, 0 failed.
Next: B, the room and its travel.

### B. The room and its travel

`RouletteRoom` (core/venues/roulette_room.gd), a `Venue` with id `Venue.ROULETTE_ID` (`&"roulette"`): known to `Venue.make`/`is_known`
and not in `Venue.IDS`, so cycling and the stage manager never reach it. One closed room the width of the control room, from its
front wall to the live room's back: felt-green walls, brass rail, dark floor, three pendant lamps, a wheel inlaid in the floor that
turns with the mix. `live_room_half` is the room's own half-width so the prop shelf, hoop and Tour case stand inside the walls;
the desk, racks, roll board and roulette panel stand where they always do (no gear moves). `Studio.enter_roulette_room` /
`leave_roulette_room` (host only, a guest is told so): not persisted as the room's venue (a restart opens the venue it was left
from), remembered venue + arrangement come back; guests follow through the room the host already publishes (the venue id).
Test `_test_the_band_goes_into_the_roulette_room_and_back` (16). Seen with `--venue roulette:0` (shots/roulette2.png).
Suite 10796, 0 failed. The wire carries the same fields as before (a venue id), so no session probe was needed.
No door yet, so nothing in the game takes you in: that is C. The room is deliberately plain: lighting, the wheel's look and sound
are for the polish slice.
Next: C, `rig_roulette_door()` in every venue and the way back from the room.
