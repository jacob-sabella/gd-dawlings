# DAW parity checklist

What a professional DAW (Reaper, Ableton, Logic, Pro Tools) does, against what the built-in engine
and the Reaper bridge do. Marked from the code, not from the docs: **done**, **partial**, **missing**.
One item per loop iteration, most-used first, smallest first. Items needing hardware that cannot be
tested here are left out.

First audit 2026-10-14, from `DAWBackend`'s verbs (core/daw/daw_backend.gd) and `MixState.ItemState`.
Not yet verified by use: anything marked partial from reading alone.

## Transport and tempo
- [x] play, stop, record, seek, loop range, punch, metronome, count-in, pre-roll
- [x] tempo, tempo map, time-signature map
- [ ] tap tempo (missing)
- [ ] swing / groove templates (missing; `swing` appears only in the toy/venue code)

## Audio and MIDI editing
- [x] select, move (across tracks), split, delete, duplicate, trim with source offset
- [x] item gain, fade in/out (linear), loop points on an item
- [x] item mute (2026-10-14)
- [ ] crossfades between overlapping items (missing)
- [ ] copy / paste of items (missing; duplicate only)
- [ ] item reverse, normalise (missing)
- [ ] time-stretch, warp, item pitch shift (missing)
- [ ] ripple edit, snap/grid settings for moves (partial: quantise only for notes)
- [ ] item locking (missing)

## Piano roll
- [x] transpose, quantise with strength, note insert through takes
- [ ] velocity editing, CC / pitch-bend lanes, legato, humanise (missing)

## Mixer
- [x] volume, pan, mute, solo, arm, monitor, input, master, colour, rename, add/remove track
- [x] folders (depth is kept through renumbering)
- [ ] VCA / group faders, track groups (missing)
- [ ] track delay compensation (missing)

## Routing and sends
- [x] sends with level and pan, sidechain, remove send
- [ ] send automation, pre/post-fader sends (missing)

## Automation
- [x] lanes with points, modes (read/touch/latch/write passes)
- [ ] automation on sends and plugin bypass (missing)

## Plugins and FX
- [x] add, remove, move/copy between tracks, bypass, wet, presets, parameters, plugin window
- [ ] parameter modulation / macros (missing)

## Comping and takes
- [ ] take lanes and comping (missing)
- [ ] track freeze (missing)

## Markers and regions
- [x] markers add/edit/remove
- [ ] regions (missing)

## Export
- [x] mix and stems render
- [ ] render formats and dither choice (missing)

## Undo and project files
- [x] undo/redo with one step per edit, save/open/new (DAWproject)

## Performance and latency
- [ ] latency report and compensation (missing; see `tools/budget.sh` for frame cost only)
