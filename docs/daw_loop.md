# DAW gaps loop

Closes the "missing" items in docs/daw_parity.md, one slice per iteration, in this order. Engine and
project model in dawkit (`vendor/dawkit`, repo ~/Projects/dawkit), the DAW-agnostic layer in
`core/daw/`, surfaces in `hardware/` as tokens and pages on the desk. Every slice: dawkit tests
(`tools/test.sh`), the dawlings suite at 0 failed, a shot when visual, a parity-doc tick, one commit
(dawkit first, then the pointer).

## Plan

1. **Take lanes, comping, freeze.**
   - *Model (dawkit):* `DawKitClip.lane` (0 is the first take) and `DawKitTrack.comp`, a list of
     `[start, end, lane]` sections choosing which lane sounds where. Lanes on a track with no comp
     all sound, as stacked clips do today, so old projects play unchanged. `DawKitTrack.playing_clips()`
     is the clips as they sound: each cut to its comp sections and the rest dropped. Round-trips
     through `to_dict`/`from_dict`; DAWproject carries lanes as Lanes in the track's lane, comp in
     `dawkit/extras.json`.
   - *Engine:* `DawKitLane` is fed `playing_clips()`, so a comp is heard without new playback code.
   - *Host:* `core/daw/` ops: new take on record (lands in the next lane over a recorded range),
     choose a lane for a range, flatten a comp into plain clips. Undo is one step each.
   - *Desk:* a TAKES page on the timeline's track page: lane count, a token per lane, SWIPE a range
     to choose it.
   - *Freeze:* bounce the track's lane through its effects to a new file (dawkit already renders the
     mix) and swap the clips for it, restorable. Last of this item.
2. **CC and pitch-bend lanes.** Controller events beside `notes` in a MIDI clip (`cc` array of
   time, number, value; bend as number 128), played by the instrument path, drawn under the roll.
3. **VCA faders, group override.** A VCA is a track with no audio whose fader scales the gain of the
   tracks that name it (`vca` id on a track); the override is a per-move modifier on a grouped fader.
4. **Automation on sends and plugin bypass.** `send:` lanes already exist in the model; bypass is a
   new `fx:<effect>:bypass` target, and the surface gets a way to record and draw each.
5. **Track delay compensation, latency report.** Report each effect's latency (plugins already say),
   delay the other tracks to match; a latency page on the desk.
6. **Groove templates.** Extract timing and velocity offsets from an item, apply as quantise.
7. **Render to FLAC and MP3.** FLAC encoder in dawkit (decoder exists); MP3 only if a licence-clean
   encoder is available, else marked blocked.
8. **Project templates.** Save a project's tracks, routing and effects with no clips; new from one.
9. **Time-stretch, warp, pitch shift.** A phase vocoder or WSOLA in the native core; last, heaviest.

Reaper paths go through the ReaScript bridge where Reaper has the feature, and are marked "not run
against a live Reaper" until they are.

## Slices

### 1a. Take lanes and the comp in dawkit (dawkit 01ecaaf)

`DawKitClip.lane`, `DawKitClip.slice(from, to)`, `DawKitTrack.comp`, `lane_count()`, `set_comp(from, to,
lane)` (joins neighbours, splits what it lands in) and `playing_clips()`. A fade stays only on an end
that is still the clip's own; a MIDI slice keeps the notes in its window. Lane and comp survive the plain
form and the DAWproject file (clip extras and `tracks.<id>.comp`). dawkit suite 417 checks, 0 failed.
Not yet reached by the desk: dawlings mirrors items in `MixState`, so 1b threads `lane` and the comp
through `MixState.ItemState`/`TrackState`, `ProjectBridge` (both ways) and `LaneEngine.clips_for`.

### 1b. The built-in engine plays the comp

`MixState.ItemState.lane` and `TrackState.comp`; `ProjectBridge` carries both ways; `LaneEngine.clips_for`
restricts an item to the stretches the comp names for its lane (`LaneEngine.comp_spans`), and only an item
of the same lane lies over it. No comp: unchanged. Test `_test_a_comp_picks_which_take_the_lane_plays`
(4 checks); full suite 10617, 0 failed. Open for 1c: the wire (guests do not see lanes yet), the desk's
TAKES page, record into a lane, flatten.

### 1c. Lanes and the comp are edited, undone and replicated

`DAW.set_item_lane(track, item, lane)` and `DAW.set_comp(track, from, to, lane)`: verbs through the
usual `_do`/intent path, one undo step each (the undo snapshot now carries the comp under "c<track>"),
validated from peers (a malformed `set_comp` is refused; a lane past `MixWire.LANES_MAX` 15 is the
last). On the wire an item's lane rides in its optional extra dictionary (only when not 0) and the
comp is its own address, `/track/N/comp`, flat triples. Reaper backend: no-op (not implemented, not
run against a live Reaper). Test `_test_lanes_and_the_comp_are_edited_undone_and_replicated` (11
checks); suite 10631, 0 failed; session probe 47 guest checks, 0 failed. Open for 1d: the desk's TAKES
page, record into a lane, flatten, then freeze.

### 1d. LANE and COMP tokens on the ITEM page

Two tokens beside REVERSE (new glyphs `lane`, `comp`): LANE puts the selected item on the next take
lane (past one more than the others use, back to the first), COMP makes the track play that item's lane
across that item's stretch (`DAW.set_comp`). Out of reach while the item is locked. Shot:
shots/lane_tokens2.png. Test `_test_the_item_page_has_lane_and_comp_tokens` (6 checks); suite 10637,
0 failed. Open for 1e: record into a lane (a new take lands on the next lane over what it covers),
show lanes in the timeline, flatten a comp; then freeze.

### 1e. Flatten a comp (dawkit 5517ec3)

`DawKitTrack.flatten_comp()` and `DAW.flatten_comp(track)` (`DAWBackend.item_slice`,
`_locally_flatten_comp`): each item cut to the stretches that name its lane, all on the first lane, no
comp; one undo step; a malformed intent refused. A FLATTEN token beside LANE and COMP. Tests: dawkit
418 checks; dawlings `_test_flattening_a_comp_makes_plain_items` (7); suite 10641, 0 failed; session
probe host 53 / guest 47, 0 failed. Open: record into a lane, lanes drawn in the timeline, then freeze.

### 1f. A new take on a comping track goes on a new lane

`DAWBackend._land_in_lane`: on a track that already has a comp, a recorded take (audio or MIDI) lands on
the lane above any it lies over and the comp is made to play it where it was recorded (newest take
plays); on a track with no comp nothing changes (a newer item over an older, as before). One undo step,
the comp riding in the snapshot. Test `_test_a_take_recorded_on_a_comping_track_goes_on_a_new_lane`
(5); suite 10649, 0 failed. Wire unchanged. Open: lanes drawn in the timeline; then freeze.

### 1g. Lanes in the timeline

`TimelineSurface.comp_silent(track, item)`: on a track with a comp, an item whose lane the comp names
nowhere across it is drawn dark (as a muted one is); a take sounding for only part of it is not. No comp,
nothing dark. Test `_test_a_take_the_comp_never_plays_is_drawn_dark` (3); suite 0 failed. Wire unchanged.
Open: a Reaper path for lanes; track freeze.

### 1h. Track freeze, the model (dawkit df163d1)

dawkit: `DawKitTrack.frozen`, `freeze(rendered_clip)`, `unfreeze()`, `is_frozen()`: the clips, comp, effects and
the effects' automation are kept as plain data and the track holds the one rendered clip; saved in the plain form
and the DAWproject extras (the stashed clips' media goes in the zip too). dawkit 427 checks, 0 failed.
dawlings: `TrackState.frozen`, `DAWBackend._locally_freeze/_locally_thaw` (items to the rendered item, comp gone,
plugins bypassed; thaw puts all back), `ProjectBridge` carries it both ways (export freezes dawkit's own way;
import thaws then freezes again). Test `_test_a_frozen_track_is_one_item_and_thaws_and_is_saved` (12); suite
10664, 0 failed. No verb or wire yet, so no probe. Next: render a track pre-fader to its file, the verb, the token.

### 1i. Freeze: render, verb, token

`MixRender.pre_fader`, `GodotBackend.freeze_track` (plays 0 to the song's end once, tapping the track after its
plugins and before its fader, 32-bit float WAV into the takes folder, then `_locally_freeze` with that file as
the one item), `thaw_track`; verbs `DAW.freeze_track/thaw_track` (validated from peers); a FREEZE token (glyph
`freeze`) on the ITEM page that freezes or thaws. The wire carries only `/track/N/frozen`. Tests: the freeze renders
to a file and thaws (8, awaited; it waits two frames so the last test's engine has freed its buses); suite 10672,
0 failed; session probe guest 47, 0 failed. Shot: shots/freeze_token.png. Open: the Reaper path. Item 1 is done
but for that; next, CC and pitch-bend lanes.

### 2a. Controller lanes, the model (dawkit fd9f8fa)

dawkit: `DawKitClip.controls` ([time, kind, value, channel]; kind a CC number, PITCH_BEND or AFTERTOUCH), `control_lane`,
`control_at`, `set_control_lane`, `clean_controls`; kept through `slice`, the plain form and the DAWproject extras.
dawkit 435 checks, 0 failed. dawlings: `ItemState.controls`, the wire (optional `controls` in an item's extra dictionary,
at most 8192 events, cleaned on arrival), split / trim / glue / flatten via `MidiTake.controls_between`, the project
bridge. Test `_test_a_midi_items_controller_lanes_follow_its_edits` (6); suite 10678, 0 failed; session probe 53 / 47, 0 failed.
Next: a verb to author a lane, playing it, then the piano roll's lane view.

### 2b. The verb

`DAW.set_item_controls(track, item, kind, channel, points)` (`DAWBackend._locally_set_controls`): a lane replaced whole,
events inside the item only, one undo step (the lanes snapshot carries them), peer intent validated (kind, channel, finite
pairs, the count), refused on a locked item. Test `_test_a_controller_lane_is_edited_undone_and_refused_when_bad` (7);
suite 10685, 0 failed; probe 53 / 47. Next: play pitch bend and CC, then the lane on the piano roll.

### 2c. Playing them (dawkit c53408d)

`DawKitTine.render_notes(..., controls)`, `pitch_bend`, `control`: the wheel (+-2 semitones), CC 64 / 7 / 11; other
controllers are ignored; channels are not told apart. dawkit 440 checks. dawlings: the item's controls go to
`render_midi` and into `midi_key`. Test `_test_a_midi_items_pitch_bend_is_in_its_sound`; suite 10687, 0 failed. Hosted plugin
instruments are not given the events: that is the native lane's `set_notes` (C++), left for later. Next: the lane view
on the piano roll.

### 2d. Controller events drawn on the item

`TimelineSurface._place_controls` / `control_level`: each event a thin amber post standing up from the bottom of a MIDI
item's block, as tall as its value (a pitch bend from the bottom of its range, centre half way), in the notes' bank, clipped to
the window. Posts stand past the tallest note and are sunk less than one, so none of their faces lies in a note's plane (the
room's z-fight probe caught both). The demo's Rhodes part gets a mod-wheel swell. Test
`_test_controller_events_stand_as_tall_as_their_value` (6); suite 10693, 0 failed. Shot: shots/controls_lane.png. Wire
unchanged. Next: ITEM-page tokens to put a lane on an item (a ramp, a clear), then recording from a controller.

### 2e. Controller tokens

ITEM page: a CC token (glyph `cc`) cycles the controller, a RAMP token (glyph `ramp`) writes it as a 16-step rise, then a
fall, then removes it, through `set_item_controls` (so one undo step, host-validated). Out of reach for audio and locked
items. `TimelineItemPage.lane_shape` / `ramp_points`. Test `_test_the_controller_tokens_ramp_a_lane` (8); suite 10701, 0 failed.
Shot: shots/cc_tokens.png. Wire unchanged. Open: single-event editing, recording from a controller, hosted plugins, Reaper.
Item 2's remaining pieces need hardware (a MIDI controller) or the native lane, so the loop moves to item 3 (VCA faders).

### 3a. A group overridden for one move

`DAW.group_free` (armed by a FREE token, glyph `group_free`, on the TRACK page beside GROUP): `set_track_volume`, `set_track_mute`
and `set_track_solo` skip the group's mates while it is armed; a fader's release (`Fader._on_grab_end`) or a mute/solo spends it.
Desk-side only, nothing on the wire. Extended `_test_grouped_tracks_move_together` (+4); suite 10705, 0 failed. Next: VCA
faders (a project-level trim per group, dawkit model first).

### 3b. VCA trims per group

dawkit c5f1668: `DawKitProject.vca` (dB per group), in the plain form and the DAWproject extras. dawlings: `MixState.vca` /
`vca_db` / `set_vca_db`, verb `DAW.set_vca` (clamped -60..+12, validated from peers, one undo step), `/vca/N` on the wire
(snapshot only for non-zero), `GodotBackend` adds it to a grouped track's bus level, ProjectBridge saves it. A VCA token (glyph
`vca`) on the TRACK page steps the picked track's group through 0, +3, -3, -6, -12 dB. Test `_test_a_vca_trims_its_group` (10);
suite 10715, 0 failed; probe host 53 / guest 47, 0 failed. Open: a real fader for it, and a Reaper path (kept desk-side).
Item 3 done apart from that; next, item 4 (automation on sends and plugin bypass).
