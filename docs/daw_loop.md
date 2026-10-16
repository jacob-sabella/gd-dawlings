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
