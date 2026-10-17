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

### C. A door in every venue

`RouletteDoor` (hardware/rig_roulette/roulette_door.gd): a frame in the venue's own carpentry (`Materials.furniture`) with brass inlay
round a felt-green portal, a RIG ROULETTE sign (BACK TO THE BAND inside the room), a lit button and its own spot lamp. A dumb door:
it emits `used`, and `Studio._on_roulette_door_used` enters or leaves (host only; refused during a Tour run). Where there is no wall
(open venues) it stands as a gate. `Venue.rig_roulette_door()` (default: the right-hand end of the front wall, mirrored from the
roulette panel) and `Venue.door_solid()` (a walker footprint, as solid as the prop shelf, so the chalk zone is still walked through);
`Studio._hang_the_roulette_door` hangs it under each venue (it goes with the venue), and `_door_footprint` keeps furniture out of it
through the floor plan. The default spot is clear in all 14 venues and every arrangement, so no venue needed an override yet.
Test `_test_every_venue_has_a_clear_door_to_the_roulette_room` (303 checks: venue x arrangement + the room: has a door, where the
venue says, walkable floor in front, no solid in or before it, no gear in it, clear of the roll board and the panel, no z-fight on
the door, and using the doors goes in and back to the loft). Door styling per venue is the venue's furniture finish only; a venue
that wants its own door look (a hatch, a cave mouth) is a polish item. Seen in the studio and the grid (shots/door_studio.png,
door_grid.png). Suite 11099, 0 failed.
Open: the wall panel stays where it is for now (D moves it into the room).

### D1. The setup wall moves into the room

Decision (the open one from the plan): the wall panel **goes from the venues**; the door takes its place, and the panel (`RigRouletteStation`)
now stands only in the Rig Roulette room, on its front wall (`Venue.rig_roulette_spot`), as a child of the venue. Reason: setup belongs
in the room, and the venues' walls were already crowded. What the host has set lives in `Studio.roll_settings` (a `RollSettings`), not in
the panel, so it outlives the panel: the wheels start from it and write back through the panel's new `changed` signal, a roll
anywhere reads it, and leaving and re-entering the room finds the wheels as left. The big board that writes up a roll stays in each
venue, so the band reads it while playing; its BIG SCREEN wheel is on the panel, so it is chosen in the room.
`_roll_rig` no longer needs the panel. Tests updated (`_test_rig_roulette_rolls_outside_tour`, `_test_the_big_board_shows_any_surface`,
the room test) and extended: a venue has no wall, the room's wall is built, settings kept across leaving and entering. Suite 11105, 0 failed.
Honest state: the panel is still the old small one (20 x 32 cm), readable up close, not yet a "wall". The settings are still local to
each client: a guest's wheels are their own and only the host's ROLL reaches anyone. Both are next: D2 = a large setup wall the whole
room reads, settings replicated from the host (guests read-only), and the ROLL ceremony.

### D2a: the roll's settings come from the host

`Session.roll_setup` (host-authoritative, sent whole, sent again to a guest admitted later, like
`roll`) carries `RollSettings.to_dict()`. The host's wall publishes it on every change; a guest's
studio takes it through `RollSettings.from_dict` (clamped) and the wall's wheels show it
(`RigRouletteStation.apply_settings`). A guest who nudges a wheel has it put back and is told only
the host changes the roll. Full suite 11113 checks, 0 failed; session probe host 53 / guest 47, 0 failed.

Still to do in D2: the large setup wall and the ROLL ceremony. The wall is still the small 20x32 cm panel.

### D2b: the ROLL ceremony

A roll the board has not shown yet no longer appears at once: `RollBoard.show_roll(roll, true)` hides
the writing and lands it part by part every 0.7 s (the track count, each pedal, the key and the foot),
each with a small drop-in. `landed(step, of)` makes `Studio` play a board thud, pitched higher
each time, and spin the room's floor wheel up (`pulse`). Guests see and hear the same, off the same
`Session.roll`; a roll sent again (a guest admitted late, a venue change) is written up plainly.
Full suite 11118 checks, 0 failed. Not yet looked at in a screenshot, and the wheel on the floor is
the only wheel; the setup wall is still the small panel.

Still to do in D2: the large setup wall.

### D2c: the setup wall is big, and stands where the seat sees it

In the room the setup wall is 3.4 times the panel it was (about 0.7 x 1.1 m) on a post of its own
(`RouletteRoom.rig_roulette_spot`, with a walker solid): the room's walls are taken by the same
gear every venue has, and a panel hung on the left wall was hidden behind the patchbay and rack from
the seat. It stands at x -2.2, z -1.5, turned toward the seat, with its foot at 1.5 m so the rack does
not hide the ROLL button. Full suite 11118 checks, 0 failed.

Honest limit, seen in the 720p shot from the seat: the plate reads from there, but the words inside
the wheel windows are still too small and dim at that range. Next: lettering for the wheels sized for the
wall (they were made for a panel stood at), then the options.

### D2d: the wheels read from the seat

The labels fade out past the distance they could be read at for a panel of their own size, and that
range ignored the wall's 3.4x scale. `RigRouletteStation._letter_for_the_scale` stretches each
label's range by the scale. Looked at in a 720p shot from the seat: PEDALS, the pool, SCREEN, LOCK KEY
and ROLL all read. Full suite 11118 checks, 0 failed. D2 is done; next the options (E).

### E1: pool presets

`RollSettings.Pool` gained TIME_BASED (delay, reverb, chorus, phaser) and DIRTY (drive, low-pass,
compressor) beside CHARACTER and EVERYTHING; `RollSettings.kinds_of(pool)` names the kinds and
`RigRoll.pool_of` filters by them. They are wheel positions on the setup wall's pool wheel and travel on
the same replicated settings (the wire carries the same `pool` int, so no probe run). An out-of-range pool
from the wire is held to the last one. Against Reaper's live list (no kind to filter by) every
position still means "whatever's there". Tests: each pool draws only its own kinds, a DIRTY roll lands
only dirty pedals. Full suite 11119 checks, 0 failed.

Not done yet in the pool: per-kind toggles, weights, a Reaper allow/ban list, and a custom preset.

### E2: how much

Pedals per roll is 0 to 6 (was 1 to 3); a CAP wheel lets one track take up to 3; NO REPEATS keeps two
pedals of the same kind out of one roll (the roll stops short rather than repeat when the pool
runs out). All in `RollSettings` (`count`, `per_track_cap`, `no_repeats`, clamped on the wire) and
`RigRoll.plan`, which with the defaults draws exactly what it did before, so seeds still replay. The
board's pedal lines tighten to fit six. The setup wall grew a row (CAP) and a NO REPEATS button; the
post is a little lower (1.4 m). Looked at in a 720p shot from the seat: all rows read. Full suite
11157 checks, 0 failed (the settings dict only gained keys, so no probe run).

Not done: whole mix vs per track, and which tracks are eligible. Both need a notion of track roles,
so they are a later slice.

### E3: key and scale

The rolled key can be drawn from MAJOR OR MINOR (as before; the draw order is unchanged so seeds replay),
ANY MODE (the seven), or PENTATONIC + BLUES; and a NEAR wheel keeps the new root within 1 to 6 semitones
(either way round the circle) of the key the last roll named, from `Session.roll`. LOCK KEY is as before. Settings
`scales`, `near` are clamped on the wire. Two honest notes: "NEAR" needs a last roll to be near (the
first roll is free), and the key is still only named, never applied, because the rolled project is empty.
Setup wall now has rows for scales and nearness (the panel is 0.52 tall; checked in a 720p seat shot).
Full suite 11165 checks, 0 failed.

Not done in key: a separate root-only lock (LOCK KEY covers the whole key).

### E4: seed and re-rolls

Every roll now runs off a seed of its own (`RigRoll.seed_for`: fresh 1 to 99999, or the last roll's when the
SEED wheel says REPLAY THE LAST ROLL), written on the board's foot and in the roll's dictionary, so any roll
can be replayed: the same tracks, key and pedals land (tested). A RE-ROLLS wheel limits how many times the band
may roll again after the first in one visit to the room (as many as it takes, none, 1 to 3); none is the Riff
Randomizer rule, and the board says "No re-rolls: write the song with this." or how many are left. A new
visit to the room starts the count again. The wall gained two rows (now 0.58 tall, post at 1.3 m); a
720p seat shot reads. Full suite 11174 checks, 0 failed.

Honest limits: a seed cannot be typed (no keyboard in VR; a numeric dial is a later idea), only
replayed from the last roll; and a single-wheel re-roll (change just the pedals or just the key) is not built.

### E5: knobs

A KNOBS wheel on the wall: SAFE DEFAULTS (as before) or CHAOS 25/50/75/100%. Each landed pedal's knobs are moved
toward a random position by that fraction (`RigRoll.knob`) off the roll's own generator, so a replay of a
seed throws them the same; the board's foot says "Knobs thrown". Setting `chaos` is clamped on the wire.
Honest limit: the built-in stand-in engine's pedals (and Reaper's first answer) report no
parameters, so a roll there throws nothing; the throw is tested on a pedal given knobs, and has not been
heard on a real engine or Reaper. Wall is 0.62 tall; seat shot reads. Full suite 11179 checks, 0 failed.

### E6: presets

`RollPresets` (core/rig_roulette): three that ship, RIFF RANDOMIZER (2 character pedals, no re-rolls), GENTLE (1
time-based pedal, key within 2 semitones, safe knobs, 2 re-rolls), CHAOS (5 pedals of anything, 2 a track, any mode,
knobs at 100%), and three saved slots in `user://roll_presets.cfg`. A PRESETS wheel on the wall loads one (host only;
it is published like any change, so guests see the wheels move; the wheel goes back to resting) and a SAVE button keeps
the room's settings in the first empty slot, then the oldest. Full suite 11197 checks, 0 failed. A preset never
carries a seed.

Honest limit: naming. Nobody can type in VR, so a saved preset is named by what it does ("5 DIRTY PEDALS, PENTATONIC,
CHAOS"), not by a name the host chooses; a keyboard-free naming dial is not built. The wall is 3.0x with the
post at 1.45 m now (0.66 tall panel, top under the 3.6 m ceiling) so ROLL clears the rack from the seat.

### E7: history and undo

Before each roll the project as it stands is kept aside as a DAWproject copy (`user://roll_history`, up to 8; a run's
leftovers are swept on the first roll of the next), and the board's foot lists the three rolls before the one on show
("BEFORE: #2 4 tracks, 2 pedals, D minor ..."), carried in `Session.roll["past"]` so guests read it too. An UNDO button on
the wall (host only) brings the project back as it was before the last roll (tracks, tempo, its own file name; clean),
puts the board back to the roll before without a ceremony, and can be pressed again to go further back. Refused with
unsaved changes, as a roll is. Full suite 11208 checks, 0 failed (one test run left files behind: fixed by the sweep).

Honest limits: only the built-in engine and its stand-in own project files, so against Reaper a roll cannot be
undone (the button says so); an undone project is read back from a DAWproject file, so anything that format does not
keep is not kept; and the UNDO label is small in the seat shot (the button and its row are there, the word is hard to
read at that range). History is not saved across sessions.
