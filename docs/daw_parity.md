# DAW parity checklist

What a professional DAW (Reaper, Ableton, Logic, Pro Tools) does, against what the built-in engine
and the Reaper bridge do. Marked from the code, not from the docs: **done**, **partial**, **missing**.
One item per loop iteration, most-used first, smallest first. Items needing hardware that cannot be
tested here are left out.

First audit 2026-10-14, from `DAWBackend`'s verbs (core/daw/daw_backend.gd) and `MixState.ItemState`.
Not yet verified by use: anything marked partial from reading alone.

Iterations done: 47

## Transport and tempo
- [x] loop to the selected items (2026-10-14)
- [x] play, stop, record, seek, loop range, punch, metronome, count-in, pre-roll
- [x] tempo, tempo map, time-signature map
- [x] tap tempo (the tape deck, `tapped_bpm`; the first audit listed it missing in error)
- [x] swing quantise (2026-10-14; off-beats up to a triplet's third late, a rail beside QUANTISE on the ITEM page; Reaper path not run against a live Reaper)
- [ ] groove templates: quantise to the feel of another item, swing on playback (missing)

## Audio and MIDI editing
- [x] select all items (2026-10-14), select all items on one track (2026-10-14, TRACK page), select, move (across tracks), split, delete, duplicate, trim with source offset
- [x] item gain, fade in/out (linear), loop points on an item
- [x] item mute (2026-10-14)
- [x] rename an item (2026-10-14; NAME on the ITEM page, on the keypad or monitor; saved as the clip name; Reaper take name through the bridge, not run against a live Reaper)
- [x] crossfade between two overlapping items on a track (2026-10-14; equal-power since iteration 27, one edit)
- [x] copy items to the playhead (2026-10-14; no clipboard, the selection is copied where the song is; Reaper path not run against a live Reaper)
- [x] item normalise (2026-10-14; from the file's overview, through `set_item_gain`)
- [x] item reverse (2026-10-14; audio items, not looped ones; a token on the ITEM page; Reaper's take reverse through the bridge, not yet run against a live Reaper)
- [ ] time-stretch, warp, item pitch shift (missing)
- [x] drags snap to the beat unless fine (`TimelineLanes.snap`; the first audit missed it)
- [x] a choosable grid: bar, beat, half and quarter beats, or free (2026-10-14; each person's own, not saved)
- [x] ripple delete (2026-10-14; per track; Reaper path not run against a live Reaper)
- [x] ripple move and ripple trim (2026-10-14; per track, a toggle each player has on the tools; the drag preview does not yet show what follows moving; Reaper path not run against a live Reaper)
- [x] item locking (2026-10-14; Reaper's C_LOCK through the bridge, not yet run against a live Reaper)

## Piano roll
- [x] transpose, quantise with strength, note insert through takes
- [x] velocity: whole-item harder/softer (2026-10-14)
- [x] humanise (2026-10-14; time and velocity, seeded from the notes; a token on the ITEM page; Reaper path not run against a live Reaper)
- [x] per-note velocity: NOTE VELOCITY rail sets the note at the playhead (done)
- [x] delete a note: the one sounding at the playhead (2026-10-14, DELETE NOTE on the ITEM page; Reaper path not run against a live Reaper)
- [x] move one note in pitch: a semitone, an octave when fine, the note sounding at the playhead (2026-10-14, NOTE UP and NOTE DOWN on the ITEM page; Reaper path not run against a live Reaper)
- [x] add a note: a beat long at the playhead, at the pitch of the one beside it (2026-10-14, ADD NOTE on the ITEM page; Reaper path not run against a live Reaper)
- [x] Legato: each note held until the next begins (done, ITEM page)
- [x] Staccato: each note cut to half its length (2026-10-14, ITEM page; Reaper path not run against a live Reaper)
- [x] Even velocity: every note at the item's average (2026-10-14, ITEM page; Reaper path not run against a live Reaper)
- [x] Retrograde: the notes of a MIDI item played backwards (2026-10-14, ITEM page; Reaper path not run against a live Reaper)
- [ ] CC / pitch-bend lanes (missing)

## Mixer
- [x] volume, pan, mute, solo, arm, monitor, input, master, colour, rename, add/remove track
- [x] duplicate track (2026-10-14; settings, effects and theirs, sends, items and lanes, under the same name, not armed; a token on the TRACK page; Reaper's 40062 through the bridge, not yet run against a live Reaper)
- [x] equal-power fades (2026-10-14; per item, both ends, linear or a quarter sine, played by dawkit's lane, drawn as a curve, saved; a token on the ITEM page; Reaper's C_FADEINSHAPE 1 through the bridge, not yet run against a live Reaper)
- [x] more fade shapes (slow, fast, S-curve), a shape per end (2026-10-14; five shapes, each end its own token on the ITEM page, played by dawkit's lane, drawn, saved; Reaper's C_FADEINSHAPE/C_FADEOUTSHAPE 0/1/2/3/5 through the bridge, not yet run against a live Reaper)
- [x] nudge the selection by the grid (2026-10-14; a bar, a beat or part of one along the tempo map, ten milliseconds with no grid or fine; two tokens on the ITEM page; Reaper path not run against a live Reaper)
- [~] glue items into one (partial, 2026-10-14: MIDI items, and the pieces of one cut recording that follow on, made one; a GLUE token on the ITEM page; other audio needs a bounce to a new file, which the built-in engine does not do; Reaper glues anything through its own 40362, not yet run against a live Reaper)
- [x] clear all solos / clear all mutes (2026-10-14)
- [x] folders (depth is kept through renumbering)
- [x] track groups (2026-10-14; four, a GROUP token on the TRACK page; faders by the same decibels, mutes and solos as one; saved; desk-side on Reaper, not in its project)
- [ ] VCA faders: a fader that moves its group without passing audio (missing)
- [ ] a group overridden for one move (Reaper's modifier on a grouped fader) (missing)
- [ ] track delay compensation (missing)

## Routing and sends
- [~] audio-device patchbay wall (partial, 2026-10-14: `PatchWallSurface` draws this machine's PipeWire graph in the venue's palette, hung on the studio side room's back wall; ports are dragged jack to jack to patch, onto a patched port to cut; the machine's own, not shared; see the backlog)
- [x] sends with level and pan, sidechain, remove send
- [x] send automation (the first audit missed it: `send:<track>` lanes, played, saved in dawkit and dawproject)
- [x] pre/post-fader sends (2026-10-14; a PRE button on each strip while the desk is flipped to a return; Reaper's I_SENDMODE through the bridge, not yet run against a live Reaper)

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
- [x] markers add/edit/remove (2026-10-14: removing the last one now reaches guests and clears a Reaper cache)
- [x] regions: add from the loop, loop one, remove (2026-10-14; drawn in the ruler's loop band; saved; Reaper's regions through the bridge, not yet run against a live Reaper)
- [x] regions: rename, move and resize, the region list (2026-10-14; NAME on the keypad, FIT to the loop range, and a GO TO rail through them in order, on the REGION page; Reaper's SetProjectMarker through the bridge, not yet run against a live Reaper)

## Export
- [x] mix and stems render
- [x] render bit depth, with dither (2026-10-14; 16 or 24-bit dithered, 32-bit float; a token on the RENDER page; Reaper's RENDER_FORMAT and RENDER_DITHER, not yet run against a live Reaper)
- [x] normalise on render (2026-10-14; the mix to a -1 dBFS peak, each stem by the mix's gain; a token on the RENDER page; Reaper's RENDER_NORMALIZE through the bridge, not yet run against a live Reaper)
- [x] render sample rate: 44.1, 48 or 96 kHz (2026-10-14; a token on the RENDER page; built-in resamples linearly from the engine rate; Reaper's RENDER_SRATE, not run against a live Reaper)
- [ ] render file types other than WAV (FLAC, MP3) (missing)
- [x] render a region: LOOP on the REGION page, then a render, renders just that region (render follows the loop range)

## Undo and project files
- [x] undo/redo with one step per edit, save/open/new (DAWproject)
- [x] a reopened project's audio is drawn (2026-10-14; it opened as blank blocks before)
- [x] autosave (2026-10-14; the host keeps a copy in user://autosave five minutes after the first unsaved change, never while the transport runs, never over the project's own file; the save token's card says when)
- [x] crash recovery (2026-10-14; a RECOVER token by SAVE lights when an earlier run left an autosave copy newer than the project, and opens it in its place, unsaved; host only)
- [x] earlier autosave copies kept: the newest and four before it (done; recovery token opens the newest)
- [x] undo history list: jump to any step (HISTORY rail on the timeline tools, each step named; on Reaper the card says "step N")
- [ ] project templates: a new project from a saved layout of tracks, routing and plugins (missing)

## Performance and latency
- [ ] latency report and compensation (missing; see `tools/budget.sh` for frame cost only)
