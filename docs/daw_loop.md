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
