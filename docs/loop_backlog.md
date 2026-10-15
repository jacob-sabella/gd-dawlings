# Backlog

What is actually finished, what is scaffolded, and what has not been started. Kept honest
because a scaffold that reads as a finished project wastes the next person's afternoon.

## Working, verified

- **Guest audio takes.** A guest's microphone records onto the host's track, placed by the song
  position the guest heard and kept there by a rate loop against clock drift. Within 1ms of the
  click offline and on Reaper (`tools/session_probe.sh`). Drawn as a waveform on the timeline,
  played by the built-in engine, placed through the bridge on Reaper.
- **DAW abstraction.** `core/daw/` holds the backend contract, the mix cache, the wire
  vocabulary and the autoload; `core/reaper/` holds only what is Reaper's. Capability queries
  and the fader taper are per-backend, and `OfflineBackend` is a peer rather than a fallback
  branch. Adding a second DAW is implementing one class.
- **OSC link.** Codec (encode, decode, bundles, padding), UDP peer, echo guard. Headless
  checks green via `tools/verify.sh`.
- **State cache.** Tracks, FX, sends, transport parsed into `MixState`.
- **Console.** A strip per track: fader, pan, rec/mute/solo, VU with real ballistics, colour
  chip, dB readout. Built from live track count.
- **Tape deck.** Transport buttons, position counter, tempo, reels that turn only while Reaper
  says it is rolling. The tempo is set from the deck: a knob beside the BPM readout (40-240) and a TAP key
  (three taps or more, averaged over the run). `DAW.set_tempo` is clamped to Reaper's 1-960 on
  both sides of a session, is undoable offline, and goes to Reaper as `/tempo/raw`. A guest's
  tempo reaching a live Reaper and coming back is checked by `session_probe.sh --reaper`.
  A CLICK key opposite TAP switches the metronome (`DAW.set_metronome`, `/click` on the wire).
  Reaper's `/click` is a toggle like `/repeat` -- checked on the rig: 1 flips it, 0 is ignored,
  and Reaper answers with the state -- so a press is sent only when it would change something.
  `live_check` reads the metronome back through the bridge's GetState (action 40364's toggle
  state), and checks a send level and pan the same way.
  A locator between the reels: the section the playhead is in (the last marker at or before it)
  under the counter, and PREV / MARK / NEXT keys. MARK is `DAW.add_marker` -- undoable offline,
  the bridge's `AddMarker` in Reaper (one "Insert marker" undo point), so it needs the bridge
  (`Capability.MARKERS`). PREV inside 0.4s past a marker goes to the one before it, so pressing
  it while rolling is not pinned in place. Checked by the suite, `session_probe.sh` (a guest's
  marker reaches the host, also `--reaper`) and `live_check` (Reaper's marker list has it, and
  one undo takes it out). Reaper's markers keep their beat, so a tempo change moves them in
  seconds -- seen on the rig when the probe's guest tempo moved its own marker.
- **Send level and pan.** `DAW.set_send_volume` / `set_send_pan` (a send is a track and its
  1-based slot, as OSC numbers it; a guest's intent is checked and clamped on the host), undoable
  offline, `/track/N/send/M/volume|pan` to Reaper. On the desk as SENDS ON FADERS: the master
  section's SENDS key flips every strip's fader and pan to its send to one return, then the next,
  then back. Fixed on the way: the bridge's sends were 0-based against OSC's 1-based (two
  half-sends per real one), and `/send/M/volume/str` was parsed as the level. Verified by the
  suite, `session_probe.sh` (a guest's send level reaches the mix and comes back) and
  `session_probe.sh --reaper`; Reaper was seen to take an OSC send write (-11.0dB, 50%L back).
- **Input monitoring.** `DAW.set_track_monitor` (Reaper's I_RECMON numbers: 0 off, 1 on, 2 auto;
  clamped on both sides of a session), undoable offline, `/track/N/monitor` to and from Reaper --
  which, checked on the rig, sends and takes one float despite its config listing a b/ and an
  i/ pattern there. A fourth key on every strip under MUTE steps off -> on -> auto; its lamp is
  a green dot, steady for on and blinking for auto. `live_check` checks both directions against
  GetState's I_RECMON; `session_probe.sh` (also `--reaper`) has a guest set it.
- **FX racks.** 19" units, one per FX slot, in Reaper's own order. Knobs are the plugin's first
  eight real parameters with Reaper's names.
- **Patchbay.** Jacks per track, hanging cables for existing sends, drag-to-patch gesture.
- **Presentation split.** Three anchors, per-viewer layout profile, runtime reparenting.
- **Room calibration.** Two-point maths, gravity flattening, drift detection. Tested.
- **Multiplayer.** A host-owned roster with colours, avatars, and pointers addressed by control
  key. The host arbitrates holds, so a control has one hand. Late echoes are ignored after
  release. Sessions are found by LAN discovery and managed from the session panel (**M**). A
  goodbye is sent on leave, and a guest falls back to solo when its host is gone. An optional
  session code admits only those told it; nothing reaches a guest until it is admitted. Verified
  by `tools/session_probe.sh` (also `--reaper`) and `tools/session_shot.sh`. Still open: XR
  calibration across participants is untested, and nothing is encrypted.
- **The mix's sound, to guests.** Reaper's outputs are tapped through PipeWire and sent over
  UDP to admitted guests, with an adaptive jitter buffer and clock-drift correction. Measured at
  46ms end to end by `tools/audio_latency.sh`. Still open: no codec (1.5Mbit/s per listener),
  picture ~45ms ahead of sound, and Linux/PipeWire hosts only.
- **Recording a guest (MIDI).** Every mix packet carries the host's song position. The guest
  stamps each note with the moment it heard, monitors on a local electric piano, and sends a take
  as one `insert_midi_take` when it hears recording stop. The take is placed offline (undoable,
  replicated) or in Reaper through the bridge, and drawn as a piano roll on the timeline. MIDI
  keyboards, or the computer keyboard by opt-in. Verified by `tools/session_probe.sh`
  (also `--reaper`): notes land within 0.25ms offline, and within 2.2ms against Reaper after a
  take's first second (~5ms in it). See docs/architecture.md, "Recording a guest".
- **Offline stand-in.** 12-track synthetic mix with moving meters, so everything above is
  developable and photographable with no DAW running.
- **Arrange timeline.** A lane per track with the track's colour and flags, a bar ruler from
  the tempo whose label spacing follows the zoom, section markers, the blocks on each lane, and
  a playhead that moves without rebuilding the panel. An overview bar underneath scrolls with
  its body and zooms by either end; the view pages forward on its own while the transport
  rolls and leaves the window alone while it is stopped. Defaults to SCREEN in every medium,
  including AR. The window arithmetic, the clipping, the follow rule and the item wire format
  are tested. A ROAD key beside 3D swaps the lanes for the same arrangement as a highway into
  the playhead (`TimelineHighway`): a view for watching a song arrive, not for editing it.
- **Track banking.** `MixState` knows which slice of the project its indices mean, moving the
  bank drops the cache rather than leaving the previous bank's names on this bank's faders,
  and the desk grows a BANK module saying "65-90 OF 90" when there is more project than bank.
  A bank asked for while a hand is on a control is deferred until the hand lets go. Tested,
  but never photographed or run against a project big enough to need it -- the stand-in has
  twelve tracks and correctly builds no bank module at all.
- **Capture harness.** `tools/shot.sh`, with reproducible camera framing on the command line.
- **Presentation switching, both ways.** The flat overlay (Tab) for the screen participant, and
  a grab handle clipped to each surface for everyone else: tap to cycle anchor, drag to place.
  Both call the same `SurfaceMount.set_mode()`. The tap/carry split and the anchor cycle are
  tested; the headset half of it has never met a runtime, like the rest of the XR path.
- **Guest replication.** Host buffers changes by address at 20Hz, split durable/volatile for
  opposite delivery guarantees, with a full reliable snapshot on join. Verified two ways: the
  snapshot round-trip is asserted field by field in the suite, and `tools/session.sh` brings up
  a real headless host and a real guest that renders what it was sent.

## Built-in DAW

The loop started 2026-10-09: make the built-in engine (`core/built_in/`, `--built-in`) a DAW people
can finish music in, saving DAWproject. Steps, in order:

0. **Done 2026-10-09.** `tools/session_probe.sh --reaper` was not broken. It had been run with
   the rig down, so the host fell back to the 2-track stand-in. The probe now starts the rig
   itself (and stops it if it started it). The guest's take window was one missed click from
   failing (1 settle + 3 clicks in about 4.6 s). It failed 2 runs in 6 once and then not in 21.
   The host now records 1 s longer. The cause of the missed click was not found: watch for
   `take: click` lines in the probe output if it comes back.
1. **Done 2026-10-09.** The engine is a separate product, **dawkit**, at the user's request
   ("build this daw project layer separate from the game. I may sell it on its own later"). Its
   own repository at `~/Projects/dawkit` is proprietary ("All rights reserved"), and this game
   holds it as a submodule (`vendor/dawkit`, symlinked to `addons/dawkit`). It has a project
   model: `DawKitProject`/`Track`/`Clip`/`Effect`/`Send`/`Marker`, with a plain form that comes
   back identical, and `problems()` for broken references. dawkit has 23 checks of its own. The
   game's side is `ProjectBridge`, which captures and loads round-trip exactly in the suite, and
   a project opened mid-session reaches the guest whole (`session_probe.sh --built-in`). Clips
   gained fades and gain, which cross the wire and survive a split.
2. DAWproject save/load.
   - **Done 2026-10-09, in dawkit:** `DawKitDawproject.save/open`. The output is valid against
     the official XSD (checked with xmllint in dawkit's tests), and dawkit's own files come back
     identical. A file without dawkit's extras (as another DAW re-saves it) opens with
     everything the XML holds, and the project.xml from Bitwig's README opens (beats converted
     to seconds, an audio event flattened out of its nested clip, a CLAP plug-in kept).
   - **Done 2026-10-09, the game's engine side:** `DAW.save_project()` (any participant, since
     the host saves where the project already is), and `save_project_as`, `open_project` and
     `new_project` for the host only. Capabilities: `PROJECT_SAVE` and `PROJECT_FILES`; Reaper
     has save only, through its own action 40026. `ProjectFiles` copies takes into the file and
     renders each demo part to a WAV once, so each demo item becomes a looped clip of its part
     at the point the song's loop had reached. On open, the media are unpacked to
     `user://open_project` and the engine is told where each file is (`OfflineBackend.media`).
     Clips (dawkit) and items (the game) gained loops. Verified: the demo is saved, reopened
     and saved again identically in the suite, and in `session_probe.sh --built-in` a project
     saved and reopened mid-session reaches the guest, which hears it play from its own files.
   - **Done 2026-10-09, the controls:** a SAVE key beside SPLIT on the timeline (the tape deck
     has no room left that would not crowd its keys), Ctrl+S, and a PROJECT section on the
     session panel: Save, Save As…, Open… and New, with a native file dialog and a confirmation
     before New. Every save, open and new is told to the whole room, and a refusal only to
     the person who asked. Verified in the suite (panel, Ctrl+S, timeline key, guest
     refusals) and in `session_probe.sh --built-in`, where the guest presses save, the host's
     file is written and both sides are told.
   - **Done 2026-10-10:** the project's title and file name reach guests: `/project/name`
     [title, file name] in the snapshot and as a change whenever a save, open or new changes
     them (`OfflineBackend.name_project`; the file's name only, never the host's folders).
     `DAW.project_title()` and `DAW.project_file_name()` answer the host's on a guest; the
     guest's panel shows "<title>" and "<file>, on <host>'s machine". Probe: the guest knows
     the file name after its save. Under Reaper too, **done 2026-10-10:** GetTimeline
     reports `project_name` (the .rpp's, without the extension) and `project_file` (its name
     only), and the ReaperBackend publishes them as `/project/name`; the host's panel names the
     file ("rig.RPP, saved by the DAW."). Probe (`--reaper`): the guest knows "rig", "rig.RPP".
3. **Done 2026-10-09.** Audio file import. dawkit's `DawKitAudioFile` reads WAV (8/16/24/32-bit
   integer, 32/64-bit float, plain or extensible), AIFF and AIFF-C, Ogg and MP3, folds more than
   two channels to stereo, and brings a file into the takes folder: copied untouched when the
   engine plays it as it is, otherwise written as a 32-bit float WAV (lossless from 24-bit).
   `DAW.import_audio` (host only) places it like a recorded take, so Reaper with the bridge takes
   it too. The panel has "Import audio…" (several files at once) and a track chooser, which
   defaults to the selection's track, then an armed one, then the first track that is not a
   folder. Files dropped on the window go the same way, one after another from the playhead,
   each one an undo step, and the room is told. `--bring-in <file>` does it at launch. dawkit
   checks each encoding to its last bit, and Ogg/MP3 by measured frequency and level.
   - **Done 2026-10-10 (3d), a guest's own files:** a guest's panel offers "Send audio to <host>"
     (and drops on the window or a lane), and `FileSend` (Session.files) sends each file as it
     is, in 32 KB slices on ENet channel 6, at most 256 MB; the host writes them to
     user://incoming, and once a batch is in brings it in through `DAW.import_audio_files`
     (tagged with the guest's name, which the room is told), deletes its copies, and tells the
     guest of any file that would not come in. Measured: the probe's guest sent a second of WAV
     and a FLAC onto Strings at 30 s: the host placed them at 30.0 and 31.0 s, a second and
     0.2268 s long, and the room was told 70 ms after sending began; on Reaper too.
   - **Done 2026-10-10 (3c), FLAC:** dawkit's `DawKitFlac`, written from RFC 9639 (no library):
     constant, verbatim, fixed and LPC subframes, both Rice codings and their escapes, wasted
     bits, left/side, side/right and mid/side, 4-32 bits, any channel count. A file is checked
     against its own STREAMINFO MD5, so one that decodes decoded exactly; a flipped bit and a cut
     file are refused, the cut one saying it ends short. 11 fixtures from the reference `flac`
     1.5 (-0, -5, -8, -8 -e -p -m -l 32 --lax, 192-sample blocks, 8/16/24/32-bit, wasted bits,
     six channels) decode equal to their source WAVs to the last bit, and an ffmpeg-encoded
     3-minute file passes its MD5. Speed: 3 minutes of 24-bit stereo in 8.7 s, on the import
     worker (3b), the LPC sum per sample being most of it; native code would be the cure, which
     is the GDScript-vs-GDExtension question waiting on the user. The import dialog offers .flac.
   - **Done 2026-10-10 (3b), importing off the main thread:** `DAW.import_audio_files` reads and
     writes each file on a WorkerThreadPool task and places it on the main thread when it is in,
     one undo step each, one file after another (so each starts where the last ended), batches
     queued behind each other; `audio_imported` per file, `audio_import_done` per batch. The
     panel says "Bringing in…" at once, a failure when it happens, and tells the room at the end.
     A track removed meanwhile turns the file away and deletes what was written. Measured in the
     suite: a minute of 16-bit stereo comes back from the call in 0.3 ms, read in 250 ms with 38
     frames drawn meanwhile. `import_audio` (synchronous) stays for scripts.
   - **Done 2026-10-10 (3a), dropping onto a lane:** files let go with the cursor over the
     timeline's lanes go onto that lane's track from the beat under the cursor (the time itself
     with shift), one after another; anywhere else they go as before. `MouseInteractor.under_cursor`
     casts at the moment of the drop, since a drag in from the desktop moves no cursor the game
     has seen; `TimelineLanes.drop_spot` answers [track, seconds]. Tested (the spot, fine, off
     the lanes, the file landing there and not on the import box's track) and photographed.
4. Host recording.
   - **Done 2026-10-09, the microphone and the click:** the built-in engine plays a metronome
     (dawkit's `DawKitMetronome`: one bar of clicks, kept on the bar grid, into the master, so
     guests hear it too). On a DAW that does not record its own inputs (the new capability
     `RECORDS_OWN_INPUTS`: true for Reaper, false for the built-in engine), the host's
     microphone is recorded by the guest's recorder in host mode (`Session.host_audio`). It is
     timed against `Session.host_heard`, which is the playhead less the output latency, and
     placed onto the chosen track or the armed one, through the same take path as a guest's,
     from the host's own id. The panel shows the host YOUR MIC on the built-in engine.
     Measured: `session_probe.sh --built-in` records the null sink's monitor (PULSE_SOURCE,
     never the machine's own microphone) while the click plays, and finds every beat's click.
     Over 8 runs, each take was within 0.9 ms of its own average, and the averages were
     between -6 and +5 ms of the beat (the limit is 10 ms). The run-to-run part is the engine's
     frame-driven clock and the click's 60 ms re-seek allowance, which step 7 replaces.
   - **Done 2026-10-09, the keys (4b):** GuestMidi plays for a host whose DAW does not record its
     own inputs (`host_records`). Takes go onto the chosen track or the armed one, timed by
     `Session.host_heard` (the clock the microphone's loopback measured), and the monitor synth
     starts when MIDI is opened or the first key is played. The panel shows the host YOUR KEYS.
     `OfflineBackend.records_inputs` lets the suite play a host on Reaper.
   - **Done 2026-10-10, the count-in (4c):** `DAW.set_count_in(bars)` (`/countin` on the wire,
     0-8 bars; COUNT on the tape deck steps 1, 2, 4, off). As in Reaper, a count-in is the
     click's: with the click off, recording starts at once. Recording from a standstill runs the
     transport from that many bars before the playhead (through the tempo map) with only the
     click heard, says it records all the while, and takes from the record point on:
     `MixState.counting_in()` / `taking()`, `count_in_to` (`/countin/to`) where the take begins.
     Takes (the host's own, a guest's audio and keys) follow `taking()`. Reaper counts in
     itself: the bridge's SetCountIn sets the project's metronome flag &16 ("Count-in before
     recording", found on the rig: &8 is before playback) and `projmetrocountin`, GetTimeline
     reads them back; `DAWBackend.follow_count_in` tells the count from the take by where the
     transport stood (a playhead not heard to go back within 0.5 s means Reaper did not count).
     The built-in engine starts the count 50 ms early, as its players sound from the next mix:
     begun on the first click it came out clipped, 5 ms late. Measured: `--built-in`, at the
     master, the bar's four clicks each 3.44 ms after their beat (all within 0.01 ms of each
     other; the same family as the render's unexplained 1.44 ms), nothing between them (-180
     dB, the song silent under the count), the song at -4.6 dB from the record point;
     `--reaper`, Reaper took and read back one bar, ran its playhead from 28.20 s to the record
     point at 30.00 s (a bar is 1.80 s) and took from 30.016 s. The probe's end moved 4 s later
     (host 35.4/36.4, guest 34.5/36.0): the Reaper host's work now ends at 32.5 s.
   - **Done 2026-10-10, punch in and out (4d):** `DAW.set_punch(on)` (`/punch`; PUNCH beside TAP
     on the deck, which moved in to mirror CLICK and COUNT): a recording takes only inside the
     loop range, all of it when there is none. It records throughout and goes on playing past
     the range; `MixState.takes_at(seconds)` says whether a moment is taken (past any count-in,
     inside any punch range). Takes ask it of the moment they hear, not the playhead's: the
     first run punched the host's take in 23 ms early, by the output's latency. `count_in_to`
     is now kept until the transport stops, for the same reason, and Reaper's own count-in puts
     the playhead back at once rather than waiting to hear it (the grace is gone). Reaper:
     the bridge's SetPunch picks its record mode, time selection auto-punch (40076) or normal
     (40252), radio toggles of each other on the rig; GetTimeline reads it back. That is a
     Reaper preference, not the project's, and its time selection is the loop range only when
     the two are linked, as they almost always are. Measured: `--built-in`, my take recorded
     from 0.8 s before a 1.5 s range to 0.4 s after it began 3.6 ms after the range's start and
     ended 8.4 ms before its end (a frame is 17 ms); `--reaper`, the mode set and read back.
   - **Done 2026-10-10, each track's input (4e):** `DAW.set_track_input(track, id)`
     (`/track/N/input`, undoable; IN on the timeline's track keys steps the picked track through
     them and back to none chosen), from the DAW's own list (`MixState.inputs`, `/inputs`): the
     built-in engine's are the default microphone, each input device ("audio:<device>") and the
     keys ("midi"). Saved with the project: dawkit's `DawKitTrack.input`, in the DAWproject
     extras (DAWproject has no word for it; dawkit a578d6f). The host's own recorders go by it:
     the microphone records from the device the take's track names (else the panel's) and not
     onto a track that takes the keys; the keys not onto one that takes a microphone. Reaper:
     I_RECINPUT through the bridge (SetTrackInput, GetTimeline's `inputs` and `audio_inputs`),
     named "none", "in:N", "in:N/N+1", "midi" (every device, every channel), anything else kept
     as "reaper:<code>"; Reaper saves it in its own project. Measured: `--built-in`, a track's
     input survives the probe's save and reopen mid-session, and the guest is told its name;
     `--reaper`, track 3 set to inputs 1 and 2 and read back. The probe's end moved 2 s later
     again (host 37.4/38.4, guest 36.5/38.0): the Reaper host's work ends at 33.9 s.
   - **Done 2026-10-10, more than one input at a time (4f):** with no track chosen in the panel,
     every armed track records, as in Reaper. Each device is offered whole and each side alone
     ("audio:<device>#1", "#2": an interface's inputs 1 and 2). The host's microphone take leads
     on the first armed track that does not take the keys, and goes onto every armed track whose
     input is the same device: one recording, one file per track, each its side (or both,
     averaged), all from the same moment (`GuestAudio.take_plan`; Session keeps a take as parts,
     fed per channel by `send_audio_channels`). Godot opens one input device at a time, so an
     armed track naming another device is left out and the host is told why. The keys go onto
     every armed track whose input is the keys (`GuestMidi.take_tracks`). Measured: `--built-in`,
     the punched take recorded input 1 onto track 3 and input 2 onto track 4, both from
     27.41002 s, each side's click peak 0.841 (the null sink sends both alike).
   - **Done 2026-10-10, the count-in before playback (4g):** `DAW.set_count_in_play(on)`
     (`/countin/play`; a fine press on COUNT, shift on a monitor): playing from a standstill
     runs the same bars of click first and the song starts where the transport stood, stopping
     during the count puts it back. `MixState.counting_in()` no longer needs recording, and
     `follow_count_in` watches the transport starting rather than recording starting, so
     Reaper's own count before playback is followed too (and a record pressed while already
     playing no longer looks like a count). Reaper: the bridge's SetCountIn sets &8 with &16,
     GetTimeline reads it back. Measured: `--built-in`, four clicks 3.46 ms after their beats,
     -180 dB between them, the song at -4.4 dB from the point it stood at, not recording;
     `--reaper`, the flag read back and Reaper's playhead run up from a bar before 30 s, not
     recording.
   - **Done 2026-10-10, pre-roll (4h):** `DAW.set_pre_roll(on)` (`/countin/song`, a guest's
     intent sanitised in apply_intent): the count plays the song under its click, the take still
     from the record point. A fine press on COUNT steps neither, before playback, before playback
     with the song, the song. Built-in: the lanes' hold is lifted (`MixState.song_held`). Reaper:
     the bridge's SetCountIn turns its count-in off and its own pre-roll on ("Pre-roll: Toggle
     pre-roll on record"/"on play", 41819/41818, each checked by name first; `prerollmeas`), and
     reads the toggles back. Measured: `--built-in`, the song -15.6 dB between the count's clicks
     and -7.0 dB from the record point on; `--reaper`, read back, Reaper's playhead from 26.97 s
     (it pre-rolls from the bar line before) and the take from 30.053 s. The probe's end moved 4 s
     later (host 46.4/47.4, guest 45.5/47.0; the Reaper host's work ends at 44.0 s, the built-in's
     at 39.4 s).
5. MIDI playback through a built-in instrument.
   - **Done 2026-10-10 (5a):** dawkit's `DawKitTine`, the tine voice of the monitor synth as an
     instrument, renders a clip with every note on its own sample. `GodotBackend.midi_stream`
     renders a MIDI item on a worker thread (keyed by its notes and length; silent until it is
     ready, and waited for when the engine goes away) and plays it locked to the item, through
     the track's bus, fader, effects and sends. The demo's Rhodes, which is MIDI, now plays its
     own notes. In a project the track gets a `BuiltinDevice` instrument (`dawkit:tine`,
     `deviceRole="instrument"`), and on opening, instruments stay out of the desk's chain.
     Measured: in the suite, a render is silent up to its first note, which starts on its own
     sample. In `session_probe.sh --built-in`, the host's loopback take of a MIDI item with a
     note on every off-beat finds each note 2.4-4.6 ms after the off-beat on average (about 2 ms
     behind the clicks, which is the tine's attack) and within 0.8 ms of that average.
   - **Done 2026-10-10 (5b):**
     - MonitorSynth's voice is now DawKitTine, one copy, sample for sample.
     - On the built-in engine the host's keys play through Godot onto the bus of the track they
       go onto (`DAW.monitor_bus`), so its fader, effects and folder apply. Sends do not: a send
       is a second player of an item, not a tap.
     - An instrument from another DAW's file is kept for its track (`OfflineBackend.instruments`)
       and saved back. Its notes play through the tine meanwhile.
     - Renders of items no longer there are pruned past 32.
   - **The engine's clock (from step 7, pulled forward):** the playhead now moves by the sound card
     (`GodotBackend.audio_time`, a silent looping player), not by the frame. Players start against
     it and are put back only on a real stall: a player's first reading after it is mixed is its
     baseline, and only a change of more than one mix step counts. Before, a 60 ms allowance let
     the playhead and the music part by up to that. After, 0 re-seeks in a take.
     Measured by the loopback over 5 runs:
     - clicks average 2-3 ms early, notes within 1.3 ms of the beat, each take within 1.4 ms of
       its own average;
     - the host's live key within 1.5-7.3 ms of where its note was stamped, after the monitor
       latency gained the mix step it waits for (it was 12 ms out).
     - The limit: Godot starts a player at the next mix step and cannot be told where in it, so
       sources started in different frames can be up to a step apart (10.7 ms here). The probe's
       absolute limit is 15 ms for that reason.
   - Seen once: the default probe's guest missed a click in its timing check (frames 33661,
     129615: one gone). It passed the next 4 runs. Like step 0's flaky click, watch for it.
     Seen again 2026-10-10 (34296, 130254: one gone at the same place), the next 2 runs clean:
     twice now, on the guest's headless dummy driver, which mixes in 85 ms lumps.
     Again 2026-10-10 with the bigger room, 3 of 14 runs (0 of 7 without it, within chance),
     always the click at ~82000 and every packet delivered: the host's song clock stood still a
     second, not the feed. A probe with a frame-timing _process added never failed in 8 runs.
6. Editing.
   - **Done 2026-10-10 (6a), items:** DAW verbs `delete_selected`, `duplicate_selected` (the
     copy goes right after the original and takes the selection; a looped item carries on where
     it left off), `trim_item(track, item, start, end)` (an audio item cannot start before its
     file; notes keep their place in time), `set_item_gain` (-60 to +24 dB) and `set_item_fades`.
     All go through `DAW._do` and are sanitised there, so guests can ask for them. Each is one
     undo step on the built-in engine. On Reaper each is a bridge call (`DeleteSelected`,
     `DuplicateSelected`, `TrimItem`, `SetItemGain`, `SetItemFades`), and GetTimeline now reports
     fades and gain. Fades of 11 ms or less are taken to be Reaper's anti-click default, not a
     fade. The built-in engine plays an item's gain and fades as its player's volume, and they
     already went into DAWproject. `session_probe.sh --reaper` trims, turns down and fades the
     guest's take, and checks that Reaper reads the edits back.
   - **Done 2026-10-10 (6b), notes:** `transpose_item(track, item, semitones)` (each note kept
     within 0-127, at most 48 semitones a time) and `quantize_item(track, item, grid_beats,
     strength)` (a grid from a 128th note to four bars; a note keeps its length and stops at its
     item's start). They are undoable, guests can ask for them, and they are saved as the item's
     notes. The built-in engine renders the item again because its notes key the render. The
     preview counts the grid at one tempo; Reaper's `QuantizeItem` uses its own tempo map, and the
     next timeline brings that back. The `--reaper` probe transposes and quantises the guest's MIDI
     take and reads Reaper's notes back: each lands within 0.14 ms of the beat (PPQ rounding).
   - **Done 2026-10-10 (6c), tracks:** `add_track(at, name)`, `remove_track(index)`,
     `rename_track(index, name)` (names capped at 64 characters for guests). A renumbering
     (`DAWBackend._locally_renumber`) keeps sends going to the same tracks, drops the sends to a
     removed track, and numbers the rest from 1. A removed folder's children move out a level,
     and the track before a removed last child closes the folder. The built-in engine's effect
     kinds and kept instruments follow their tracks, and the buses are rebuilt. One undo step each:
     undo puts the same track objects back where they were. The room gets the whole mix again
     (`project_replaced`). On Reaper: bridge `InsertTrack`, `DeleteTrack` and `RenameTrack`, then a
     surface refresh and a structure poll. The preview is drawn only when the whole project is in
     the bank.
   - **Fixed on the way:** Reaper's undo and redo now go through the bridge (`Undo`/`Redo`), in
     line with the edits. Over OSC, an undo sent straight before a bridge edit was served after
     it and took the edit back instead (seen in the `--reaper` probe). OSC is the fallback with
     no bridge.
   - **Done 2026-10-10 (6e), what is kept by track number follows a renumbering:** backends emit
     `tracks_renumbered(old -> new)` (and DAW relays it) for an add, a remove, and the undo or
     redo of either. The host remaps its own and its guests' chosen take tracks
     (`GuestAudio`/`GuestMidi.follow_renumber`, sent to guests as `_tracks_renumbered`) and the
     takes on their way in; a take whose track is gone is refused when it lands. Plugin tablets
     follow their track by number rather than finding the plugin again by name, since another
     track may have one of the same name; the profile and the room are updated after. On Reaper
     the map comes from the edit; an undo of a track edit in Reaper sends none.
   - **Not yet:** holds are by control and last one gesture, so they are left alone. A demo-song
     track's part was its name's, so renaming one changed what it played: **done 2026-10-10,**
     the part is the track's (`TrackState.part`, set as the stand-in's song is made), kept
     renamed and moved, and a new track named "Kick 2" no longer plays the kick. Seen once: the default
     probe's guest did not hear the host's head (2 checks), then passed 3 runs in a row.
   - **Done 2026-10-10 (6d), keys:** COPY and DEL on the timeline, in the corner under the track
     names, lit while items are selected. Dragging an item's edge (the last 4 mm of it, at most a
     quarter of it) trims that edge, snapped to the beat unless fine. The block is drawn at its new
     edges while the contents stay put. With exactly one item selected, a strip hangs under the
     panel (`TimelineItemStrip`): GAIN (-24 to +12 dB), fade IN and OUT (squared, up to the
     item's length) on knobs that edit when let go, so a turn is one undo step and one bridge
     call; `-`/`+` transpose a semitone (fine: an octave) and `Q` quantises to the beat (fine:
     sixteenths), lit for MIDI items. Tracks: a press on a name in the header picks it (lit
     amber; this desk's own, not the DAW's selection), and `TimelineTrackStrip` under the
     panel's right end has ADD (after the picked track, or at the end), DEL and NAME. NAME opens
     a `NamePrompt` on the monitor. **Done 2026-10-10 (6b):** in a headset, NAME opens a
     `TypingPad` in front of the panel instead: digits, letters and a few marks on the desk's
     own keys, SHIFT (on for the first letter), SPACE, DEL, LEAVE and OK, pressed by hand like
     any key; the first key types over the old name, DEL first clears it, OK on nothing names
     nothing, one pad at a time. `TimelineSurface.type_on_desk` opens it on a monitor too.
     Tested by a hand pressing its keys, and photographed; not yet tried in a real headset,
     like the rest of the XR path. Still to come: fades played as curves rather than a flat volume per frame (needs
     the engine's own mixing, see "Waiting on the user"). **Done 2026-10-10:** a fade is dragged by its
     handle on the item, where its line meets the block's top (the top corner for no fade, the
     top 5 mm of the block; the rest of the edge still trims), snapped to the beat unless fine,
     drawn as it goes and set in one undo step when let go; the hover card reads "fade in 0.50 s".
   - **Done 2026-10-10 (6e), drawn on the item:** each fade is a line from silence in the
     block's bottom corner to full level where the fade ends; the gain, when not 0 dB, is
     written under the strip between the fades; a take's waveform is drawn as heard, through
     its gain and fades (`MixState.ItemState.level_db`, which the built-in engine plays by too).
     They follow a trim and a move. Tested (line ends and slope, readout, a flat take's columns
     low at the fade's start) and seen in a shot. The z-fight scan now looks only at a bank's
     drawn instances, as the unused fade slots lie folded at the origin.
7. Sample-accurate timing, post-effects sends, tempo map.
   - **Done 2026-10-10 (7a), post-effects sends:** a send's bus now holds the track's pan, then
     the track bus's own effect objects (one knob turns both; a bypass reaches both), then the
     send's own pan, which used to be ignored. The player still plays at the send level times
     the fader: post-effects, post-fader, as Reaper sends by default. A send patched or pulled while
     the engine runs gets or loses its bus at once (`_built_sends`); before, that waited for the
     next full rebuild. The cost: each send runs the track's effects again, because Godot routes
     a bus to one place, so a send cannot tap the track's output. The same input with the same
     settings gives the same sound, but stateful effects (delay, reverb) keep their own tails per
     send. Checked by structure (same objects, order, bypass, pans); not measured, because the
     sound itself is Godot's effect processing.
   - **Done 2026-10-10 (7b), a tempo map:** dawkit's `DawKitTempoMap` (points of beat, tempo,
     held or ramped in a straight line; ramps integrated exactly, with the inverse) is
     `DawKitProject.tempo_points`, written to and read from DAWproject's `TempoAutomation`, and
     checked against the schema. Opening a file that counts in beats now puts every time into
     seconds through the map, measured from where it starts, so a clip across a tempo change is
     as long as it sounds (tested on Bitwig's example with a held and a ramped change). In the game:
     `MixState.tempo_points` with `tempo_map()`, `beat_at`, `seconds_at_beat`. `bar_beat`,
     `bar_to_seconds`, the ruler's bars, the loop band's bar, the snap and quantise all go through
     it. `DAW.set_tempo_map` is one undo step, replicated (`/tempo/map`) and in the snapshot, and a
     guest's map is checked (each point a later beat at 1-1000 bpm, from beat 0). With a map the
     click is a 32 s window of the song's own clicks (`DawKitMetronome.span`), made again near
     its end or on a seek; one tempo keeps the looping bar.
   - **Done 2026-10-10 (7c), Reaper's tempo map, and two kinds of ramp:** GetTimeline reports
     Reaper's tempo markers in quarter notes, and `SetTempoMap` replaces them as one undo point.
     The `--reaper` probe found Reaper's gradual change is a straight line in time, not in beats:
     a marker sent at the seconds dawlings' beat-ramp gave landed at quarter note 16.32, not 16.
     So `DawKitTempoMap` has three shapes: HOLD; RAMP_BEATS, DAWproject's `linear` and dawlings'
     default; and RAMP_SECONDS, Reaper's. Both ramps are exact with exact inverses. The file
     writes `linear` for either and keeps which one in dawkit's extras. Reaper's ramps are read
     as RAMP_SECONDS, and a map sent to Reaper has its ramps made RAMP_SECONDS and its markers
     placed by that map, so Reaper's markers land on the beats sent, exactly (probe:
     [[0, T, hold], [8, T/2, time ramp], [16, T, hold]] back as sent; undo restores one tempo).
   - **Done 2026-10-10 (7d), the click measured across a tempo change:** the `--built-in`
     probe's own take now runs through a tempo map: held, then ramped (in beats) to three
     quarters over four beats, mid-take. Its clicks and off-beat notes are placed and measured
     through the map. The first run found the click 4-17 ms late: its 32 s window was made in the
     frame that started it, so it began behind the song by the time that took, and the drift
     check took that as its baseline. Now the window is made while stopped (or, mid-play, started
     that much further on). Over 4 runs, each take's clicks average -7.9 to +6.8 ms from the beat
     and notes -0.7 to +10.9 ms, each within 1.9 ms of its take's average. That is one Godot
     mix step either way, the start granularity the 15 ms limit is for.
   - **Done 2026-10-10 (7e), the tempo's changes on the desk:** `TimelineTempoStrip` under the
     middle of the timeline acts on the change the playhead is under: BPM (40-240, set when let
     go), ADD (at the start of the playhead's bar, at the tempo there), RAMP (glide to the next
     change, in beats), DEL. Each is one undo step. The ruler marks each change with its tempo
     (`/` before it when the tempo glides into it), and redraws when the tempo or the map changes.
   - **Done 2026-10-10 (7f), time signature changes:** dawkit's `DawKitMeter` (points [beat,
     numerator, denominator], a bar of n/d being n counts of 4/d beats; a change starts a new
     bar, the one before it cut short when it falls inside it, as in Reaper), on
     `DawKitProject.time_signature_points`, written as DAWproject `TimeSignatureAutomation`
     (`TimeSignaturePoint`s in beats, valid against the schema, read back without dawkit's
     extras too), and the click counts it (`DawKitMetronome.span_clicks` takes a meter: a click
     on every count, the bar's first accented). dawkit fcbae59. In the game: `MixState.meter()`,
     `beat_unit` and `time_signature_points` (`/timesig`, `/timesig/map`), so bar.count numbers,
     bar starts, the count-in, the ruler (which marks each change, `6/8`, in the SIG key's colour)
     and the tempo strip's bars go through it; `DAW.set_time_signature_map`, sanitised on the
     host, one undo step; SIG on the tempo strip steps the playhead's bar through 4/4, 3/4, 6/8,
     2/4, 5/4, 7/8, 12/8, a change equal to the one before it going. The built-in engine's click
     is a window of the song's own clicks whenever the meter is not one x/4. Reaper: the bridge's
     GetTimeline reads each tempo marker's signature (TimeMap_GetTimeSigAtTime for the first),
     SetTimeSignatures clears every marker's and puts the new ones on markers at their places
     (new ones at the tempo there; one inside a ramp breaks the ramp in two), and the backend
     drops a marker that only holds a signature from the tempo map; a tempo map edit, which
     rewrites every marker, puts the signatures back after. Measured: `--built-in`, past the
     song's end, a bar of 4/4 then one of 6/8: 10 clicks, each 3.48 ms after its count (the same
     constant as the count-in's), the bars' first counts at 0.600 against at most 0.476;
     `--reaper`, 7/8 from bar 3 set, read back (beat 8.5 is 3.2.00) with the tempo map unchanged,
     and taken away. Found on the way: a window of clicks made under the audio lock was put
     ahead by the time it took (a probe's doing; in play it is made while the song moves). The
     Reaper probe's extra checks now run after the takes' undos (they are Reaper undo points of
     their own), and the end moved 2 s later again (host 39.4/40.4, guest 38.5/40.0; the Reaper
     host's work ends at 35.6 s).
   - **Done 2026-10-10 (7g), the demo song through the tempo map:** with tempo changes a part no
     longer loops: it plays windows of itself (`DemoSong.render_window`: from 4 beats before a
     loop to two loops on, every note where the map puts its beat and as long as the map makes
     its beats, at the looped part's level), rendered and encoded on worker threads and
     collected on the main thread (every task waited for, as MIDI renders are), the next one
     asked for halfway through a loop, so one is there when the playhead crosses into it. At
     one tempo a window is the loop sample for sample. Measured: `--built-in`, a track named for
     the kick, soloed, with an empty item past the song's end, through a ramp down by a quarter
     over four bars: 5 kicks across a window change, each 3.75-4.29 ms after its beat (the last
     would be 420 ms out at the first tempo); windows ready 0.7-0.9 s after the map is set. The
     first try crashed the host at exit (double free): window tasks were left running and a
     static Mutex cached levels; both gone. The probe's end moved 3 s later (host 42.4/43.4,
     guest 41.5/43.0; the built-in host's work ends at 37.4 s).
   - **Done 2026-10-10 (7b), the demo parts in the song's signature:** each bar is played in its
     own signature (`DemoSong.pulses`: every count in x/4, dotted beats in 6/8, 9/8 and 12/8, twos
     with a three at the end in 7/8 and 5/8), kick on the bar's top and its middle pulse, snare on
     the backbeats (2 and 3 of a waltz), the bass walking the pulses, the tune stretched to fill
     its bar; 4/4 is as written. One signature loops (cached per signature); with changes the
     parts play windows of BARS bars through the meter as through the tempo map. The suite finds
     a 3/4 loop's kicks and a 4/4-then-6/8 window's on their beats' samples.
   - **Not yet (7b):** a tempo edit
     leaves the parts silent until their windows are rendered (under a second here). The
     loopback probe measures the click at one tempo only.
8. Automation.
   - **Done 2026-10-10 (8a), lanes in dawkit:** `DawKitAutomation` (target "volume" dB, "pan",
     "mute", "send:<track id>" dB, "fx:<i>:<p>" normalised; points [seconds, value, HOLD|LINEAR]),
     on `DawKitTrack.automation`. DAWproject `Points` with a `Target parameter=` in the track's
     lane, values in the parameter's unit; the exact points are kept in dawkit's extras.
   - **Done 2026-10-10 (8b), lanes in the game:** `TrackState.automation` (a send named by its
     destination's index), wire `/track/N/automation/<target>` (flat triples, empty = gone, in
     the snapshot, `AUTOMATION_POINTS_MAX` 8192), `DAW.set_automation` sanitised on the host
     through `apply_intent`, one undo step per lane. `OfflineBackend.follow_automation` moves
     each automated control to its lane's value every frame while playing (or when the playhead
     moves while stopped), not as history, replicated as ordinary control changes. Send lanes
     follow renumbering, and structure undo puts them back. ProjectBridge maps send indices to
     track ids and the desk's fx index to the project chain's (which counts the instrument).
   - **Done 2026-10-10 (8c), written from the desk:** `TrackState.automation_mode` (Reaper's
     I_AUTOMODE numbers: 0 read, 2 touch, 4 latch; anything else is read), wire
     `/track/N/automode`, `DAW.set_track_automation_mode`, and an AUTO key on the timeline's track
     strip that steps the picked track through them. On the host, a fader, pan, mute, send level
     or effect parameter moved while playing on a touch/latch track opens a pass instead of an
     undo step: the lane stops moving that control, the moves are collected, and when the pass
     ends they replace that stretch of the lane (holding what came before, gliding back over
     `RETURN_SECONDS` after) as one `set_automation` step. Touch ends after `GESTURE_MS` still
     (the wire has no "let go"; a hand's grab/release would be better); latch at the stop.
     Guests' moves arrive as intents and are written the same way.
   - **Done 2026-10-10 (8d), Reaper's envelopes:** the bridge's GetTimeline reports each
     track's active envelopes with points (volume, pan, mute, each send's volume, plugin
     parameters by asking each envelope whose it is) and I_AUTOMODE; SetEnvelope replaces one
     whole (one undo point), SetAutomationMode sets the mode. Found on the rig: a track's own
     envelopes exist from the start, inactive, and must be made ACTIVE (GetSetEnvelopeInfo_String)
     before their points or Reaper does not play them; a new envelope starts with a point at 0
     that DeleteEnvelopePointRange leaves, so points go one by one; the pan envelope is inverted
     (+1 left) and the mute envelope is "playing" (1 heard); a send's envelope is
     `P_ENV:<VOLENV`. In Trim/Read (0, Reaper's default) envelopes play under faders that stay
     put, so a lane written to a track in 0 moves it to Read (1), and the desk's read is
     Reaper's Read. Probe: three lanes on track 1 read back, Reaper's own faders measured
     following them while it plays (-6 dB, hard left, -18 dB and muted further on), a send's and
     a plugin's lane read back, latch read back, five undos and every envelope gone. The probe's
     end moved 3.5 s later for it.
   - **Interpolation:** dawkit ramps volume in dB; Reaper ramps in its fader scaling. Held
     points agree exactly; a ramp's middle differs. Write a ramp as dense points on the way to
     Reaper if it matters.
   - **Done 2026-10-10 (8e), lanes on the timeline:** a LANE key on the track strip steps the
     picked track through its volume, pan, mute, each send and any other lane it has, then
     none; the shown lane is drawn over the track's own lane (one ImmediateMesh, stepped where a
     point holds, a dot per point; levels straight in dB from -48 to +12, because the fader's
     taper put -4 and -18 dB a millimetre apart). On that lane a press adds a point (snapped to
     the beat unless fine) and drags it, a drag moves a point, a click toggles hold/ramp, a fine
     click removes it, the wheel over a point nudges it; each is one `set_automation` step. The
     hover card names the lane and reads the point.
   - **Done 2026-10-10 (8f), measured:** the `--built-in` probe's off-beat notes' track has a
     volume lane (held, then -9 dB over three seconds); each note's power over its first 90 ms
     in the host's own take, against the notes before the ramp, is the lane's value in the
     middle of that window to within 0.1 dB (4 runs; the limit is 0.5 dB). It used to take the
     loudest sample against the lane at the note's start, which drifted to 1.06 dB and failed.
   - **Done 2026-10-10 (8f), the master's lanes:** `MasterState.automation` (volume, pan),
     wire `/master/automation/<target>`, `DAW.set_automation(0, ...)` (track 0 is the master;
     a guest's master target other than volume or pan is refused), followed like a track's,
     the project's master lane both ways, and Reaper's master envelopes (its `<VOLENV2` like any
     track's; the bridge's track 0). Probe: a master lane read back from Reaper and its master
     fader following it while it plays.
   - **Done 2026-10-10:** the master's lanes on the timeline: with no track picked, LANE steps
     through the master's volume and pan, in an automation row under the last track named
     "MASTER  VOLUME"; points are added, dragged and removed as on a track's
     (`DAW.set_automation(0, ...)`), and picking a track puts the master's lane away. Found on
     the way: finishing a point fetched `DAW.state.track(picked)`, which for the master made a
     phantom track 0 in the mix; it compares with the lane as shown now. **Done 2026-10-10,
     touch/latch for the master:** `MasterState.automation_mode`, `/master/automode`,
     `DAW.set_track_automation_mode(0, ...)` (a guest's intent for track 0 is now accepted); the
     master's fader and pan write passes as a track's do, onto the master's lanes; the AUTO key
     with no track picked steps the master's mode. Reaper: the bridge's SetAutomationMode takes
     track 0 as the master and GetTimeline reports `master_automode`. Probe (`--reaper`): the
     master set to latch, forgotten here, comes back from Reaper's next report as latch. **Done 2026-10-10:** the shown lane has a row of
     its own under its track, 42 mm tall (2.5 lanes), with its name where the track names are;
     the lanes below move down while it is open, and a press on the track's own lane is an item
     press again. Tested (row, spacing, press, closing) and seen in a shot. dawkit ramps volume in
     dB, Reaper along its fader: a ramp's middle differs between them.
9. Mixdown and stems.
   - **Done 2026-10-10 (9a), the built-in engine's render:** `DAW.render(stems)` (anyone may ask;
     the host renders; Capability.RENDER, false for the stand-in) writes the loop range while it
     loops, else the whole song, as 32-bit float stereo WAVs in "<title> renders" beside the
     project (user://renders when it was never saved): "<title> - mix.wav" and, with stems,
     "<title> - <track>.wav" each. `render_finished` says what was written; the room is told.
     In real time (MixRender), as Godot mixes no faster than the card takes it: captures at the
     end of the master and each track bus, which hear the bus before its fader (Godot applies a
     bus's volume as it sends), so each block is multiplied by the fader it was mixed with, and a
     muted track is silence. Lined up by emptying the captures, starting the transport and the
     engine's players inside one hold of the audio lock. Looping is off for the render.
     Measured (`--built-in` probe, 3 runs): a track of notes rendered as a stem, each onset
     1.44 ms after its place in the song, the same in every run and every note (after the
     instrument's own 1.04 ms attack); a 12 dB automated drop measured as -12.00 dB.
   - **Done 2026-10-10 (9b), on the desk:** MIX and STEMS keys under the timeline, between the
     tempo's keys and the tracks' (TimelineRenderStrip); the hover card says what will be written
     (the loop, or the whole song and its length); dark where the DAW cannot render and while a
     render runs.
   - **Done 2026-10-10 (9c), Reaper's render:** the bridge's RenderProject renders the same range
     offline through Reaper's own render (action 42230) as 24-bit WAVs in "<project> renders"
     beside the .rpp: the master as "- mix.wav", and with stems every track (all selected for
     it, the selection put back). The project's render settings are saved and put back, and a
     render replaces the last one's files. Its files are found by name (EnumerateFiles answers
     from a listing half a second old). ScriptBridge calls take their own timeout now; a render's
     is ten minutes. The rig: mix and 40 stems of two seconds in 0.65 s. Probe: two renders of
     the same two seconds, with a volume lane on Kick Out and without; its stem is -6.00 and
     -18.00 dB down, exactly the lane. (The rig's DRUMS folder renders 0.7 dB short of its lane:
     something in that folder is not under its fader; not looked into.) The probe's end moved
     3 s later again (host 26.4/27.4, guest 27.0).
   - **Done 2026-10-10 (9e), the tail:** a render rings out after its range, up to
     `DAWBackend.RENDER_TAIL_SECONDS` (4 s). Built-in: at the range's end the transport stops and
     the capture goes on until every bus has been below -80 dB for 0.2 s, and the files are cut
     at their last sound (a dry render ends where it did); up to a frame (~17 ms) of what follows
     the range can be in the tail's first moment, as the players stop on a frame. Reaper: its
     own render tail (RENDER_TAILFLAG for the custom bounds, RENDER_TAILMS), fixed at 4 s, the
     project's settings put back after. Measured: `--built-in`, a reverb return kept in the
     probe's opened project and the render's notes sent to it, the tail 2.88 s, falling from
     -24 to -80 dB with no rise over 3 dB (no note begins); `--reaper`, its files 2 s + 4.000 s.
     The probe's end moved 5 s later (host 31.4/32.4, guest 32.0): the Reaper work now ends at
     28.8 s, and the host prints when it does.
   - **Not yet (9d):** the 1.44 ms is unexplained (a resampler's delay?) and could be taken off;
     faster than real time waits on the engine mixing itself. A default probe run once lost one of the guest's clicks ("its clicks
     a second apart"), then passed 3 times running.
10. **Done 2026-10-10.** Interchange proof against the official examples. The examples are what
   bitwig/dawproject's own tests write (DawProjectTest at ee4dcdd, run with Gradle 9.8.1 on Java
   26, as 8.11 does not run there): 20 projects, kept in dawkit as fixtures
   (`tests/fixtures/dawproject/reference`, MIT, with the one WAV they embed).
   - **Found:** every audio example opened with no clips and no word: dawkit read clips only from
     a lane per track (Bitwig's own layout), and the examples put `Clips track=` straight under
     the arrangement. MIDI CC and pitch-bend automation were dropped silently, an alias clip
     (`reference=`) was empty, a warped clip's start in its file was lost, and a clip playing a
     file outside the project failed in the game (ProjectFiles joined its absolute path onto
     the unpacked media).
   - **Done, in dawkit (8bb6e02):** lanes are read as deep as they nest, each knowing its track
     and time unit from around it; aliases play their content; a warp at the song's own speed
     is no change, its start in the file kept. Said, not dropped: automation of MIDI expression,
     automation inside clips, scenes, video, a stretch (played at the file's speed), plug-in
     state missing from the file, an external file not on this machine. dawkit's tests open each
     example (its clips' starts, lengths, offsets, fades, notes, and its one expected warning),
     save it, check the save against the official schema, and reopen it the same, also with
     dawkit's extras stripped as another DAW's re-save would. Two projects now count as the same
     when their numbers differ only in the last bits (beats written and read back as seconds).
   - **Done, in the game (3dbd09f):** the suite opens each example through `DAW.open_project`
     on the built-in engine: dawkit's warnings exactly, its clips as the items, every sound a file
     the engine can play; the game's save of it is valid against the schema and reopens the same.
     The demo song's save is checked against the schema too.
     And a file that opened with something left out told the host "You could not open it": the
     panel took any sentence back as failure. It opened when the project's path is the file's
     now (DAWBackend.open_project says so); the room hears "opened it, but: ...".
   - **Not carried, and said when met:** MIDI expression lanes (CC, pitch bend, pressure),
     automation in clips, clip launcher scenes, video, time stretching, other DAWs' plug-in
     state when it is not in the file. Not tried: a file from Studio One or Cubase themselves
     (only Bitwig's README example and the reference implementation's), and no other DAW here
     to open what the game saves.

Which DAWs open the result is in `docs/architecture.md` ("Its file format: DAWproject"): Bitwig,
Studio One and Cubase natively, Reaper through ProjectConverter, Live and Logic by stems only.

The main suite took about a minute; **done 2026-10-10**, now about 33 s (verify's limit 90 s).
Timed test by test: half of it (35 s) was "no two faces in the room share a plane", which scans 14
venue variants. Each scan ran the separating-axis overlap on 284,000 coplanar pairs, almost all
faces in the same plane nowhere near each other (floor tiles); a world-box separation check in
front of it is exact and took a scan from 2.4 s to 0.33 s. The scan had no test of its own that it
finds anything: one now plants a fight (a turned plate in a tile's top, a bank's instance) and
checks that touching and distant faces in one plane are not one. The jitter buffer's drift test
simulated 20 minutes twice (7.8 s); 5 minutes still drifts 0.3 s uncorrected against a 400-frame
limit, and holds within 41 frames. What is left is about a second per test that builds a Studio.

## Scaffolded — the shape is right, the wiring is not finished

- **Calibration gesture.** `RoomAnchor.mark_origin/mark_forward` work and are tested; nothing
  calls them from a controller yet. Needs a two-step in-headset prompt.
- **ReaScript bridge.** `GetTimeline` is written, parsed and tested against the payload shapes
  it actually produces, and `can(TIMELINE)` now tracks whether the bridge is loaded -- but none
  of it has run against a live Reaper, only against replayed answers.
  `GetProjectStructure` is still not consumed by anything: track colours, folder structure and
  unambiguous send destinations are all sitting there unused.
- **XR session.** The rig is built and wired: `XRRig` instantiates the head, both controllers
  and an `XRInteractor` per hand, the studio builds it instead of the desktop camera when the
  medium is not SCREEN, and the left controller's `by_button` runs the two-mark room
  calibration. Untested against an actual runtime -- there is none on this machine -- so what
  is verified is the arithmetic and the construction, not the tracking.

## Built-in engine (GodotBackend), next

Recording, files, MIDI, the click, monitoring and DAWproject are done: see "Built-in DAW" above.

- **The demo mix, measured 2026-10-10:** not heavy below 150 Hz (8-13% of its energy at the
  master, chorus and verse); mid-heavy (83-87%), dull (3-7% above 2 kHz), and 6-7 dB over full
  scale before the master's limiter, which flattened the whole song. DemoSong trims each part
  (`TRIM_DB`: vocal -6, double -4, snare +4, hat +5, overheads +4) and all of them
  (`LEVEL_DB` -9): the song now peaks at 0.9-1.1 before the limiter, so it shaves under a
  decibel off the loudest moments only. The band shares barely moved (the mids are the bass's
  harmonics, the driven guitar, the Rhodes and the reverb return); a listen by ear is still due.
- **Done 2026-10-14, third-party plugins (Linux):** dawkit hosts CLAP, VST3 and LV2 effects and
  instruments itself (dawkit README, "Third-party plugins"), so the built-in engine no longer
  needs an Ardour or Tracktion behind it. `PluginCatalogue` lists what is installed, scanned by
  dawkit's scanner (one process per file; cached in user://plugin_scan.json by file and time),
  and the rack offers it beside Godot's effects ("VST3: NAMix", "CLAPi: ..."). A slot carries its
  plugin by a key (`FXState.host_key`, `HostedPlugins`), so moves, copies (a fresh instance with
  the same state) and undo keep the same plugin and its window. Its parameters are the plugin's
  automatable ones (Gojira's 2219 become 139: the MIDI CC slots are left out); a knob turned in
  its own window reaches the desk as a value. Its window is on the tablet (HostedPluginWindow),
  embedded off screen by dawkit and worked by every click: NAMix, Gojira through yabridge and LSP
  checked by hand, `tools/probe/hosted_plugin_live.tscn` with real sound (each plugin runs once
  a mixed block, however many buses it is on). An instrument plugin in a track's chain plays its
  MIDI items in its lane, note for note, and the host's keys through it while the track takes
  them. Projects keep each plugin by format, id and state (a VST3's as a .vstpreset); one this
  machine lacks is kept as it came and saved back unchanged. `--add-plugin T:NAME` puts one on a
  track for a capture. Still to do: a fully hidden display for windows (install xorg-server-xvfb; the off-screen window is used meanwhile),
  plugin wet/dry and presets, an LV2 window drawn in GTK or Qt (only X11 ones show), and a
  plugin this machine lacks keeps its saved state only while it stays in its slot (a move loses it).
- **Done 2026-10-14, plugins on Windows:** dawkit hosts CLAP and VST3 on Windows too (no LV2),
  with the scanner shipped beside dawlings.exe. Plugin windows go in an off-screen tool window
  read by PrintWindow, and clicks are posted to them (dawkit README, "Windows").
  `PluginCatalogue` runs the scanner with `--out` and its own 60 s limit, not `timeout`. Checked
  under Wine 11 with the mingw build: the scanner finds the Windows VST3s, and Gojira X loads,
  plays, keeps its state and draws off screen. A click on its page tabs and a drag on its INPUT
  knob work, and the host hears about the knob. Still to do: a run on real Windows, in the game
  itself. A JUCE window there depends on the WindowFromPoint redirect, and GPU-drawn windows on
  PrintWindow's full-content mode; Wine checked neither. Mantra under Wine drew nothing and made
  no sound (likely not activated in that prefix).
- **Done 2026-10-14, plugin dropdowns on Linux:** a plugin's menus are drawn over its picture and
  worked from the tablet, kept off screen. dawkit (d85de37) does it for plugins in the built-in
  engine (Gojira's preset menu and submenu checked); `native/plugin_view.c` does the same for
  windows read from Reaper (ReaEQ's Type dropdown checked, outside click closes it). On Hyprland a
  rule, on for 4 s after each click, parks Wine's and Reaper's menus on `special:dawkit` unfocused;
  `reaper_pointer.c` tells Reaper its window has the focus on a sent press (Reaper closes menus
  otherwise). Other window managers leave those menus on the desktop. Probe:
  `tools/probe/reaper_menu_live.tscn`. Still to do: a Wine plugin (Gojira) inside Reaper opens no
  menu from a click (not diagnosed); a private Xvfb for plugin windows would make this work on
  every desktop and stop Reaper's plugin window flashing on the real one; Windows menus.

## 1.0 for friends (2026-10-10)

The user's scope: the backlog, and what a 1.0 to send some friends needs, on Windows and Linux,
over the internet.

- **Done:** Linux and Windows exports (export_presets.cfg, tracked); dawkit's native core
  cross-built for Windows with MinGW (needs only Windows' own DLLs) and as release builds; an
  exported build opens on the built-in engine (`--stand-in` for the silent one); a note for the
  testers (docs/playtest.md, packed as the zips' README: hosting over Tailscale or forwarding UDP
  7332 and 7334); a welcome card on a sent-out build's first launch, and on F1 (WelcomeCard), and
  a short header there; the demo mix's gain staging (above). Checked: the Linux export renders
  and is silent until play; the Windows export starts clean under Wine. Not yet run on a real
  Windows machine.
- **Fast keys by default: not for 1.0.** The native helper is built on the player's machine from
  native/keys.c, which is not in an export, and needs a C compiler and PipeWire headers; on
  Windows it never existed. So a friend's keys always go through Godot, as late as the song,
  and their takes land where they were played. It stays a developer's option.
- **Known:** the built-in session probe has exited 1 with every check passing, about one run
  in five on 2026-10-10, not reproduced in three runs after; a process ending badly at shutdown
  is the guess. The exports are 181 and 190 MB zipped, most of it the venues' 2K textures.

## Tour

Tour (core/tour/, the chained case in core/items/tour_case.gd) as a roguelike worth coming back
to, for one person alone or a band of eight online: a run is a gig, a song in trouble and a crowd
that wants it fixed, winnable solo and busier with every friend who joins. Everyone has a job
every minute, no two runs are alike, the game plays and sings back, and now and then it all goes
gloriously wrong and you survive anyway.

- **A song to rescue. Done 2026-10-10.** Every brief hands the band a full role-named loop
  (TourProject.song_for: a tine stab lane and the ten DemoSong parts, eight bars looped at a
  tempo drawn from the run's seed) with something wrong in it, and the brief is to fix it before
  the clock runs out. Six flaws (TourFlaws: a buried vocal, a muddy bass EQ, a dragging keys lane,
  a muted Rhodes, a hard-panned guitar, a kicked tempo), each judged live off the desk's own
  numbers or the Timing measure and ticked off on the HUD as it is fixed; one flaw solo, two for
  2-3 players, three for 4-5, four for 6-8, one more at the boss (Session.participants.size()).
  Found on the way: a DawKitProject carries no parts, so a project loaded through ProjectBridge
  had none (a silent band, and a silent stand-in after every run's restore) -- Tour now passes
  its band's parts to the load and its snapshot carries the real project's back; giving every
  loaded track a part by name instead sounded the band under the built-in probe's count-in and
  after its render's range. The Timing measure's eighth grid capped at 0.0625
  beats so the pocket check could not fail; the master limiter (-0.3 dB) sits above the loudness
  ceiling (-1 dB) so the levels check could not pass. The master-bus bars are off until measured.
- **Playing briefs: a part per player. Done 2026-10-10.** A job per player on top of the flaws:
  a backbeat, a wall of eighths, a stab on the one -- played, not mixed, so nobody stands around
  while one person works the desk. New lane, Stage (TourProject.STAGE_TRACK == 1; Keys moved to
  track 2), armed and MIDI, where every part's notes land -- both HitRecorder and GuestMidi land
  a take on the first armed track regardless of who is playing, so one shared lane is the only
  one that can ever take one; who holds a part is HUD/run state, not anything on the lane, so a
  part is told apart from another by its instrument's channel and pitch (TourPart, TourParts,
  the catalogue in core/tour/tour_parts.gd: tamb_backbeat/tamb_four/tamb_last, shaker_eighths/
  shaker_offbeats, keys_one/keys_one_three). Judged by a new TourMeasure.Rhythm, on-grid vs. off
  against each part's own beats/grid and window, counted rather than averaged so flailing fails a
  `clean` ratio rather than passing by volume. One instrument of each kind exists in the room
  (shaker, tambourine, keytar), so INSTRUMENTS=3 caps a brief at three note-making parts no
  matter the band; solo and a duo hold one at a time so a run alone stays winnable
  (TourParts.count_for). A part nobody takes blocks the pass exactly as an unfixed flaw does
  (TourBrief.judge's new "parts" block); someone leaving opens their part for anyone else to pick
  up, and TourParts.reassign hands it to whoever holds fewest after PART_GRACE (8s) unplayed.
  Found on the way: a take only ever lands while the transport *records* (HitRecorder/GuestMidi's
  `follow`, gated on `DAW.state.takes_at`), so a brief now starts with `DAW.transport_record()`
  instead of `transport_play()`, with the count-in forced to 0 for the run's length and restored
  after (a brief needs none, and a run is not the place to leave somebody's own setting changed).
  And a take only commits when recording *stops*, so nothing a part does shows on the HUD until
  the brief ends, unless the recorder rolls one take into the next on its own -- the one opt-in
  change to either recorder's default behaviour, `roll_every` (0.0 keeps the old behaviour
  exactly; Tour sets it to a bar's worth, `Tour.take_roll_seconds`, for the brief's duration via
  scenes/studio.gd). `_place_take` tells the room a notice per take, which during a part-heavy
  brief is one every bar per player -- noisy; see below. Reviewed the same day: the path was
  traced end to end on both sides (a hit -> HitRecorder.hit -> insert_midi_take on the first
  armed lane, Stage, through DAW._do on the host and Session._place_take for a guest -> Rhythm
  -> `played`), and a suite test now runs the real brief tick over it; the HUD says YOU, in ink,
  on this player's own line; and an open part is handed on only once ITS grace is out, not the
  moment any other open part's is. Not built, by the room's own limit: eight parts on eight
  lanes. One shaker, one tambourine and one keytar is three note-making jobs, so a band of eight
  gets its eight things to do as five flaws and three parts, not eight parts.
- **A guest's chosen track swallows their part.** GuestMidi.take_track honours a guest's own
  `target_track` first, so a guest who picked a lane in their keys panel before the run plays
  their keytar part onto that lane, not Stage, and it never ticks. Tour could say so on the HUD
  when a holder's keys are going elsewhere, or the panel could clear the choice for a run.
- **A stale count-in point.** `MixState.count_in_to` is reset only when the transport stops
  while still counting in; a counted-in recording that ran past its point and then stopped
  leaves it set. `transport_record` without a count-in (what a brief does) does not touch it,
  so a host who recorded with a count-in before breaking the case open starts a brief whose
  `takes_at` is false, and whose lane engine holds, until the song reaches that old point --
  past the end of an eight-bar loop, a brief whose parts can never land. Read from the code,
  not reproduced; engine-side (core/daw), so not changed for Tour.
- **Quiet take notices during a brief. Done 2026-10-10.** `Session._place_take`'s "X played N
  notes onto Stage at B.B.00" is right for an ordinary take, but with `roll_every` ticking a part
  every bar it was a notice a bar per player playing one; held back while `Session.tour` is
  non-empty, the HUD's part lines being the word on it.
- **The keys part without a keytar.** `keys_one`/`keys_one_three` are judged on channel, not on
  who is holding what, so they will take notes from a host's computer keyboard too, but nothing
  turns those keys into the keytar's input unless the item is actually in hand (KeyCatcher wires
  the keytar's own keys). Worth a path that lets the host (or anyone without a keytar to hand)
  take a keys part from the computer keyboard directly.
- **A sing part.** The mic's take is audio, not notes -- no judge for it headless, and opening a
  mic in the test suite is off-limits -- so a vocal double stays mixed only, never played. A part
  judged on an audio take's presence/level on Vox Dbl is the natural next one, once that is safe
  to measure without a real microphone.
- **Instruments as draft cards. Done 2026-10-10.** Three new kinds -- cowbell, woodblock, drum
  pad (core/items/cowbell_item.gd, woodblock_item.gd, pad_item.gd, ~80 lines each off
  InstrumentItem, models from tools/blender/spill_percussion.py, sounds from
  Foley.cowbell/woodblock/pad) -- spill out of the case as draft boons (`spill_cowbell` etc.,
  repeatable cards) and seed a big band's first brief (TourParts.first_spill: band 4 gets one,
  5 two, 6-8 all three). Two findings shaped it: (1) the judge tells parts apart only by
  (channel, pitch) on the shared Stage lane, so a second copy of a kind is a decoy unless it
  records a different pitch -- every kind got a second voice ("the low one", its own GM pitch:
  cowbell 56/68, woodblock 76/77, pad 47/45, `InstrumentItem.voice`/`pitch_scale`), giving 3
  room + 3 kinds x 2 voices = 9 instruments, enough for 8 parts. (2) the host never hears its
  own `Session.tour_changed` (`publish_tour` only RPCs out), so the host spawns a spilled
  instrument off a new `Tour.instrument_spilled` signal while a guest spawns off
  `Session.tour`'s `instruments` array (`TourRun.instruments`/`instrument_curses`/
  `instrument_bound`, `scenes/studio.gd`'s `_spill_instrument`/`_sync_spilled`) -- the same
  split `_on_tour_run_ended`/`_on_session_tour_changed` already used for the case itself. Cursed
  spills ride along: sour/low detune the sound only (`curse_pitch`, the recorded pitch stays
  true so the part is still winnable); a marked spill binds one peer (`Item.bound_to`/
  `may_hold`, refused in `Interactor.pick_up` and, on the host, by `Session._grant` itself
  through a new opt-in `Session.holdable` callable the studio sets -- unset, holds behave as
  before -- so a hand that was not told is refused all the same; the mark cleared when that
  peer leaves, in any run state). Twelve new catalogue parts (core/tour/tour_parts.gd), six
  new cards (core/tour/deck.gd), `TourDeck.draw` now takes `band_size`/`spilled` so a band
  bigger than the room's own three is always offered an instrument while it still wants one.
  Cut: a kazoo-ish second keys voice -- `GuestMidi` lands all keys on one channel and the
  keytar part is "channel -1 = any but 9", so a second keys instrument cannot be told from the
  keytar without touching the recorders, which is engine-ish, not opt-in; parked below. Found
  on the way: two Tour tests that built a Studio and `await`ed a frame before their own session
  setup, run back to back, interleaved badly enough (GDScript resumes a suspended coroutine only
  when its awaited signal fires, so a test dispatched in between can run its whole body while an
  earlier one is still paused) to leave a stray `Session.role` visible to a synchronous test
  sandwiched between them, and once to a freed `DAW.backend` outliving the `DAW.use()` that
  should have replaced it -- both tests now free their Studio immediately (`remove_child` +
  `free()`) instead of `queue_free` + `await`, matching `_test_only_the_host_can_break_the_case`'s
  existing pattern, and a part-judging test now sets its own session role explicitly rather than
  trusting whatever a neighbour left. `tools/verify.sh` ends clean; `shots/tour_spill.png`
  (band 8, the open case with a cowbell and a woodblock landed around it), `shots/tour_draft.png`
  (a Drum Pad boon offered) and `shots/tour_instrument.png` (a cowbell close up) are the
  record; `shots/tour_brief_band8.png` shows the six-part, four-flaw card at 11pt. The review
  pass then found and fixed: `ItemRoom.kind_of` stripped the digit off the darts' own ids
  ("dart1" -> "dart"), so a ghost carrying a dart would have carried nothing (KINDS ids are now
  left alone); the host enforced a mark only by a `go_home` in `Presence._apply_items` that the
  same pass's `follow` undid a line later (gone, replaced by the `_grant` refusal above);
  `Tour._on_participant_left` returned early outside a brief, so a leaver during the draft kept
  their mark on the run while the host's own item lost it; guests got neither the case's toss
  nor the toast on a spill (both now ride `_sync_spilled` as a guest spawns its copy); and a
  spill during `_start_brief` published a half-laid-out run (new flaws over the old brief's
  parts) a frame before the brief's own publish (held back by `_laying_out` now). Not chased:
  a brief whose song fails to load mid-run nulls the run without `run_ended`, which would leave
  the host's spilled items in the room until the next run ends -- the pre-existing failure path,
  one `_end_run` would also count as a loss.
- **A second tambourine/shaker from the case.** The room's own three instruments get no second
  voice today -- only the three spill kinds do. A cowbell-shaped curse spill could instead hand
  out "the room's SECOND shaker", voiced the same way, once the band is big enough to want one.
- **Chaos: a marked instrument's holder leaves mid-bar.** `Tour._on_participant_left` clears
  `run.instrument_bound` and `scenes/studio.gd`'s own handler clears the real item's `bound_to`,
  but nothing currently re-offers it as a part if it was already assigned and dropped -- it
  becomes an ordinary unmarked instrument sitting wherever it fell, exactly like any other open
  part. Worth a pass to confirm that reads as "freed up", not "lost", on the HUD.
- **Per-instance pitch table lives twice.** A spilled instrument's GM pitch is declared once in
  the real item (`CowbellItem.PITCHES` etc.) and once in the part catalogue
  (`TourParts._build`'s literal pitches) -- kept honest today only by
  `_test_tour_new_parts_are_judged_by_their_instruments_pitch`'s agreement check. The fourth kind
  (the triangle, see "Way more instruments" above), the fifth (claves), the sixth (hi-hat) and the
  seventh (bongos) all joined the case without doing this fold -- a deliberate scope call each
  time, to keep those iterations to one new instrument rather than a new instrument plus an
  architecture change -- so the duplication is now live across seven kinds, not three, and worth
  doing properly before an eighth joins and makes it eight places to keep honest by hand instead
  of one.
- **Way more instruments, each medium its own.** (The user, 2026-10-10.) A wide instrument
  catalogue -- hand percussion, mallets, a drum kit, blown things, strings, noise-makers --
  limited only by what each medium can actually play: a desktop mouse (clicks and shakes, one
  hand), a headset with controllers (two hands, real strokes and velocity), a headset with
  tracked hands in passthrough (pinches and taps, no buttons), and a browser build if one is
  ever exported (no WebXR today; the exports are Linux and Windows). Each instrument says which
  media can play it and how (InstrumentItem's stroke/click model, one per medium), parts are
  drawn only from instruments the holder's medium can play, and the draft offers what the band
  present can use. Several iterations' worth; start with the gestures each medium already has.
  First one in: **a triangle. Done 2026-10-11.** A fourth hand-percussion kind, same stroke/click
  gesture as the other three (InstrumentItem.feel already reads any medium's `shake_point`
  uniformly -- mouse, controller or tracked hand -- so this needed no new per-medium code, only
  a new instrument within the gesture the room already supports; the wider "mallets, blown
  things, strings" catalogue the user actually asked for still needs its own gesture work and
  stays open). Modeled procedurally in the user's live Blender via the Blender MCP (a subagent,
  at the user's own request, iterating visually with `look` rather than built blind from math --
  three rod segments and two rounded corner joints, a small open gap at the apex the way a real
  triangle is left open so it rings rather than being damped by its own suspension point;
  material named "rod", origin at the shape's own vertical middle, the same convention
  cowbell/woodblock/pad already use), then folded into `tools/blender/spill_percussion.py`'s
  headless build as a fourth section and re-verified to reproduce the interactive result exactly
  (`blender --background --python tools/blender/spill_percussion.py`, 426 faces, same bounds).
  Recorded as the General MIDI open triangle (81) or, its low voice, the muted triangle (80) --
  `Foley.triangle`, four high inharmonic partials ringing and beating against each other for 1.6s
  (the shimmer a bent rod's bend points give it, not one clean pitch), with a bright click at the
  beater's landing. Two rhythm patterns each voice (`triangle_turnaround`/`triangle_shimmer`,
  `mute_triangle_backbeat`/`mute_triangle_eighths`), a `spill_triangle` draft card, and
  `TourParts.SPILL_KINDS` grown to four -- which in turn grew `first_spill`'s big-band seeding
  (band 7 now starts with all four kinds already out, not three) and meant a solo player's odds
  of seeing *any* spill boon at all in a draft needed a second look: each kind still rolls its
  own independent keep-chance in `TourDeck.draw`'s weighting (the comment already explained why:
  deterministic RNG consumption regardless of pool size), but a flat per-card chance means more
  kinds mechanically floods a solo band with more chances to see one at all -- a real regression
  the existing `_test_tour_deck_offers_instruments_to_a_big_band` test caught outright (23 of 40
  seeds, over the test's own "fewer than half" bar). Fixed by deriving the per-card keep chance
  from the catalogue size, originally calibrated to reproduce the exact three-kind odds (see the
  "claves" entry below for why that formula was tightened again at five kinds -- no margin for
  sampling noise -- to a flat ~45%-or-less target regardless of catalogue size instead). Also updated
  `first_spill`'s own doc comment (now stale at "6 and up gets all three") and extended the
  pitch-agreement test (`_test_tour_new_parts_are_judged_by_their_instruments_pitch`) with the
  triangle's own pair -- the "Per-instance pitch table lives twice" duplication below is now
  live across four kinds rather than fixed, a deliberate scope call (see that entry).
  `tools/verify.sh` ends clean (7074 checks, 0 failed, 0 SCRIPT ERROR; needed `godot --headless
  --path . --editor --quit` first, for the new `TriangleItem` class_name); `tools/session_probe.sh`
  default and `--built-in` both green ([host] 53/0 and 79/0, [guest] 47/0 and 42/0, unchanged).
  `tools/tour_probe.sh` at 1, 4, 7 and 8 players all show the triangle spilling, holding, playing
  and judging correctly end to end (e.g. "YOU TRIANGLE: a ring on the one and the three 8/8"); the
  pre-existing "part count matches the catalogue" flake (documented and re-confirmed four times
  now across four separate iterations) turned up again at 7 and 8 players, reconfirmed once more
  by stash/re-run against bare master at 7 -- same failure, same shape, still not this. A new
  `--tour spill` shot state (mirrors `&"win"`/`&"loss"`: calls the real `Tour.spill`, not a mock)
  is now permanent infrastructure for the next instrument this backlog item adds.
  Caught mid-build: `tools/shot.sh` without `--built-in` runs on the offline synthetic-mix
  stand-in, where `Tour.is_available()` is false and every `--tour` state silently does nothing
  (the case stays chained) -- `tools/screenshot.gd`'s own doc comment already says so, but it is
  easy to miss; every future `--tour` shot needs `SHOT_ARGS="--built-in --tour <stage>"`, not
  just `--tour <stage>`. `shots/tour_triangle.png` (the case mid-run, "A triangle fell out of the
  case." and "A cowbell fell out of the case." live on the HUD, SEED shown) is the record of the
  real spill firing; the Blender subagent's own render of the model itself, sent to the user
  separately during the build, is the closer look at the instrument.
  Fifth one in: **claves. Done 2026-10-11.** Same shape as the triangle in every respect: modeled
  procedurally in the live Blender via the MCP (a subagent, iterating visually with `look`, fixing
  the one new gotcha the triangle build hadn't hit yet -- see "Use Blender for models" in this
  session's own memory, a full `read_factory_settings` reset kills the live MCP server's own
  connection, so a live-session build clears only the default Cube/Camera/Light by name instead),
  folded into `tools/blender/spill_percussion.py`'s headless build as a fifth section and
  re-verified to reproduce the interactive result exactly, including the other four still
  rebuilding correctly alongside it. Two parallel offset sticks (`stick()`, the triangle's own
  `rod()` renamed and flattened), material "wood", warm hardwood colour close to the woodblock
  item's own `WOOD` constant. Recorded as the General MIDI claves (75) or, its low voice, the
  vibraslap (58) branded "LOW CLAVES" the same non-literal way the cowbell's own low voice is a
  different instrument (low agogo) wearing the kind's name -- `Foley.claves`, a sharp bright
  impulse with a short near-pitched ring, dry and short next to the woodblock's duller knock.
  Two rhythm patterns each voice (`claves_one`/`claves_backbeat`, `lowclaves_backbeat`/
  `lowclaves_eighths`), a `spill_claves` draft card, and `TourParts.SPILL_KINDS` grown to five --
  `first_spill`'s doc comment updated again (band 7 now gets four kinds out, not all four at six;
  8 gets all five).
  The solo-odds fix from the triangle's own iteration held the wrong kind of steady: it
  calibrated the per-card keep chance to reproduce the *exact* three-kind rate at any catalogue
  size, which is itself only an approximation of the real post-shuffle-and-backfill odds a seed
  sample actually shows -- fine with headroom, razor-thin without it. Five kinds pushed the same
  `_test_tour_deck_offers_instruments_to_a_big_band` check to exactly 20 of 40, failing its own
  strict "fewer than half" bar by landing precisely on the line. Rather than loosen the test
  (the same mistake the triangle's own entry above talks itself out of) or chase a tighter
  closed-form match to one specific 40-seed sample, the formula now targets a flat ~45% ceiling
  regardless of catalogue size -- deliberately short of 50%, so normal sampling noise around the
  target has somewhere to land instead of tipping the test over every time a kind is added. A
  design improvement on top of the fix, not just a patch: a solo player has no real use for an
  instrument no matter which kind exists, so there was never a reason the odds should sit as high
  as the original three-kind number did.
  `tools/verify.sh` ends clean (7090 checks, 0 failed, 0 SCRIPT ERROR; needed the editor's
  `--import` pass again, for the new `ClavesItem` class_name). `tools/session_probe.sh` default
  and `--built-in` both green ([host] 53/0 and 79/0, [guest] 47/0 and 42/0, unchanged).
  `tools/tour_probe.sh` at 1, 4 and 8 players all show claves spilling, holding, playing and
  judging correctly end to end; the pre-existing "part count matches the catalogue" flake
  (reconfirmed a fifth time now, across five separate iterations) turned up again, reconfirmed
  once more at 8 by stash/re-run against bare master -- identical shape, worse that run on master
  itself than with this change applied, still not this. The `--tour spill` shot state (added for
  the triangle) now spills every kind in `TourParts.SPILL_KINDS` rather than a hardcoded pair, so
  it keeps showing the whole case as a sixth kind eventually joins rather than needing an edit
  each time; `shots/tour_claves.png` is the record, all five "X fell out of the case" lines live
  on the HUD at once. The headless rebuild incidentally re-exported `triangle.glb` too (same
  shape, same bounds and face count, byte-different -- some non-determinism in its own rod
  placement math on a second run) and was reverted rather than carried into this commit, since it
  changes nothing about what ships.
  Sixth one in: **a hi-hat. Done 2026-10-11.** A pair of thin bevelled discs, built procedurally
  and headlessly straight into `tools/blender/spill_percussion.py` (two cylinders, no live
  Blender session needed this time -- the shape is as simple as the drum pad's own disc-on-base,
  and every other instrument's own primitive-built body, so there was nothing here a live visual
  pass over triangle or claves needed that this one did not already have precedent for).
  `Foley.hihat` is the first spilled-kit sound built from noise rather than a struck tone --
  closer to the shaker's own hiss than to the cowbell's ring, since a cymbal's own overtone stack
  is dense enough it reads as noise, with a few fast, very-high inharmonic partials riding it for
  the metallic glint a cymbal's attack actually has. Closed hi-hat (GM 42) is the main voice,
  open hi-hat (GM 46) the low one -- the first kind since the triangle where the second voice is
  the SAME physical pair played a different way, not a different instrument wearing the kind's
  name, so "OPEN HI-HAT" needed no awkward branding the way "LOW CLAVES" or "LOW COWBELL" did.
  Two new rhythm-pattern pairs (`hihat_eighths`/`hihat_offbeats`, `openhat_backbeat`/
  `openhat_one`), a `spill_hihat` draft card, and `SPILL_KINDS` grown to six -- `first_spill`'s
  own doc comment now says band 8 (the biggest band there is) seeds five kinds out of six, never
  all of them, since an 8-person first brief can never draw more than `band_size - ROOM.size()`
  and that number tops out at 5 regardless of how large the catalogue itself grows.
  The deck's solo-odds formula (`core/tour/deck.gd`, fixed to be catalogue-size-independent in
  the claves iteration) needed no retuning -- it is derived from `SPILL_KINDS.size()` at read
  time, exactly the point of that fix -- but
  `_test_tour_deck_offers_instruments_to_a_big_band`'s OWN 40-seed sample failed anyway, landing
  on the exact same "20 of 40" boundary it hit at five kinds. Tracing it down: the formula's true
  target (an "at least one of N independent per-kind rolls lands" probability) really is a flat
  ~45% by construction, regardless of N -- the test's repeated near-misses were never the formula
  drifting, they were a 40-sample binomial test with a standard deviation (about 3.15) nearly as
  large as its own 2-seed margin against the `< 20` bar, so an honest 45% roll lands on the wrong
  side of that bar close to a quarter of the time on pure luck, and adding a kind reshuffles which
  seeds land where (the shuffle these cards go through consumes RNG draws too, so a bigger pool
  changes the stream's own state before each kind's roll, not just how many rolls there are). The
  real fix, finally: not retuning the odds again, but fixing the test's own statistics -- 2000
  seeds instead of 40, bar still "under half", now carrying about 4.5 standard deviations of
  margin, so no future kind added to the catalogue can coincidentally land this check on the
  wrong side of its own bar the way three separate iterations in a row just did. Confirmed:
  `tools/verify.sh` 2000-seed version still finishes in the same ~50s ballpark as the 40-seed one
  (pure logic, no engine cost) and now reliably passes regardless of catalogue size.
  `tools/verify.sh` ends clean (7089 checks, 0 failed, 0 SCRIPT ERROR; needed `godot --headless
  --path . --editor --quit` first, for the new `HihatItem` class_name). `tools/session_probe.sh`
  default and `--built-in` both green ([host] 53/0 and 79/0, [guest] 47/0 and 42/0, unchanged).
  `tools/tour_probe.sh` at 1, 4 and 8 players all show the hi-hat spilling, holding, playing and
  judging correctly end to end (`hihat_offbeats` shows up played in the failing runs' own part
  lists below, proof it is scoring, not absent); the pre-existing "part count matches the
  catalogue" flake (now reconfirmed a sixth time, across six separate iterations) turned up again
  at both 4 and 8 players, reconfirmed once more via stash/re-run against bare master at 4
  players three times in a row -- identical signature, same five checks failing on master itself
  with none of this iteration's changes applied, still not this. `shots/tour_hihat.png` is the
  record, all six "X fell out of the case" lines live on the HUD at once, a hi-hat among them.
  Per-instance pitch table lives across six kinds now, not five -- see that note elsewhere in
  this section.
  Seventh one in, and the last for now: **bongos. Done 2026-10-11.** (The user capped the
  catalogue here, mid-build -- "stop after this one" -- so this is the last new instrument
  without a further ask.) A joined pair of drum shells, a smaller one and a larger one, bridged
  by a short wood block the way a real pair's rims are bolted together -- built headlessly
  straight into `tools/blender/spill_percussion.py` again, same call as the hi-hat's: nothing
  about two stacked cylinders with a connecting box needed a live visual pass either.
  `Foley.bongo` is `pad`'s own swept-sine-and-click shape, pitched up and shortened -- a small
  tensioned membrane's quick slap, not a tom's longer boom. Hi bongo (GM 60) is the main voice,
  low bongo (GM 61) the low one, named the same "" / "LOW " way as cowbell, woodblock, pad and
  claves (not the hi-hat's own distinct naming, since GM's own "hi"/"low" pair here maps onto
  that branding cleanly, where "hi-hat"/"low hi-hat" would have read oddly). Two new
  rhythm-pattern pairs (`bongo_eighths`/`bongo_one_three`, `lowbongo_backbeat`/`lowbongo_four`),
  a `spill_bongo` draft card, and `SPILL_KINDS` grown to seven -- `first_spill`'s own doc comment
  now says band 8 seeds five kinds out of seven (unchanged from six, since `band_size -
  ROOM.size()` still tops out at 5 for the biggest band there is; the catalogue has already
  outgrown what any legal band's first brief can draw in full, and will keep outgrowing it from
  here, which is fine -- the point was always "something to do already", not "everything").
  `tools/verify.sh` ends clean (7091 checks, 0 failed, 0 SCRIPT ERROR; needed `godot --headless
  --path . --editor --quit` first, for the new `BongoItem` class_name) -- including the
  2000-seed solo-odds check from the hi-hat iteration, now proven to actually hold at a seventh
  catalogue size rather than merely asserted to. `tools/session_probe.sh` default and
  `--built-in` both green ([host] 53/0 and 79/0, [guest] 47/0 and 42/0, unchanged).
  `tools/tour_probe.sh` at 1, 4 and 8 players: 1 came back fully clean this time (the pre-existing
  "part count matches the catalogue" flake did not fire), 4 and 8 showed it again
  (`bongo_one_three` and `hihat_offbeats` both show up played in the 8-player run's own part
  list, proof the bongo is scoring, not absent) -- the same pre-existing issue reconfirmed a
  seventh time now, across seven separate iterations, still not chased. `shots/tour_bongo.png` is
  the record; only five "X fell out of the case" lines show on the HUD at once (a fixed-size
  notice queue, not a spill bug -- cowbell and woodblock scrolled off before the shot was taken,
  since the case now spills seven kinds in a row for this `--tour spill` state and the HUD was
  never built to hold more than a handful of lines at once; worth a backlog line of its own if a
  future shot of the full case ever needs to show all seven at once). Per-instance pitch table
  lives across seven kinds now, not six -- see that note elsewhere in this section. With the
  catalogue capped here, **this closes the "way more instruments" item for now** -- it stays open
  as a bullet for whenever the user wants another kind, rather than marked fully done, since it
  was never a fixed list to finish.
- **Seed randomness. Done 2026-10-11.** The one draw left rolling its own unseeded
  `RandomNumberGenerator` instead of the run's own stream -- `muted_track`'s pick of which
  sounding track to curse (deck.gd) -- now seeds off `hash([run.attempt_seed, "muted_track",
  run.brief_index])`, the same idiom `spill_cursed` and the draft draw themselves already use;
  the same seed and brief index now mute the same track every time
  (`_test_tour_deck_muted_track_draws_off_the_runs_own_seed`). Checked the rest of the run's own
  draws while in there (deck.gd's card shuffle, tour_chaos.gd's schedule/draw/pick_track/
  pick_sign, tour_parts.gd's draw/assign, tour_flaws.gd's draw/tempo_for/hard_pan/wrong_tempo,
  tour.gd's spill_cursed and crowd-throw rng) -- every one already took its stream as a parameter
  or seeded off `attempt_seed`; `muted_track` was the only one still rolling its own. The case
  now shows the run's own seed on its front panel once broken (`TourCase.show_seed`, swapping
  the RUNS/WINS tally for "SEED <n>" for as long as the run lasts, `reset` putting the tally back
  once it ends) -- every draw a brief or a card makes already comes off `attempt_seed`, so reading
  the number off the case is what "a run can be replayed" means: a number someone can read off and
  hand back. Wired on both sides of the table: the host sets it the moment `start_run()` fires
  (`attempt_seed` is already on `run` by then, same call stack as `run_started.emit()`), a guest
  catching up reads it off `Session.tour` directly rather than `Tour.run` -- `Tour`'s own
  `Session.tour_changed` connection is made with `call_deferred` (core/tour/tour.gd's `_ready`),
  so `Tour.run` is not guaranteed to have caught up yet when a guest's own handler for the same
  signal runs; reading the dict straight avoids depending on which of two plain connections to
  the same signal happens to fire first. `tools/verify.sh` ends clean (7051 checks, 0 failed);
  `shots/tour_seed.png` (the case's own gallery light picking "TOUR / SEED 4203061862" off its
  stencilled panel, the lamp the case was already built with) is the record -- finding a frame
  that actually caught that lamp's narrow 45 degree cone, in a back-of-house nook the key light
  never reaches at all, took more tries than the two-line fix it is a record of.
- **Chaos events. Done 2026-10-11.** Mid-brief trouble on top of a brief's flaws and parts: never
  on the first brief (that one is for learning the band's own flaws), telegraphed 2 s ahead so
  getting hit is never a surprise from nowhere, struck once on the host's own clock, and judged
  live exactly as a flaw is -- a struck event blocks the pass until it is actually put right
  (`TourBrief.judge`'s new "chaos" block), and can be broken again after recovering if the band
  lets it. Six (core/tour/tour_chaos.gd's catalogue, core/tour/tour_chaos_event.gd's shape,
  mirroring TourFlaw/TourFlaws down to the file split): the power flickers and a strip mutes
  (MUTE off recovers it); someone leans on SOLO and the rest of the band drops out (SOLO off);
  the stage box works loose and Stage stops taking the part lane (REC arm it again); the crowd
  throws things and a strip's fader lands on the floor at -30 dB (back between -12 and +3); a
  plugin goes haywire on a strip (bypass, flatten or pull it, judged by a `TourFlaws.eq_clean`
  pulled out of muddy_bass's own judge so the two share one definition of "clean"); the deck's
  belt slips and the tempo lurches +-14 BPM off the setlist (grab it back within 3 BPM) --
  `wrong_tempo`/`dragging_keys` briefs never draw it, so a brief is never judged on the same knob
  twice. 1-2 players see one about six tries in ten; 3-5 always one, often two; 6-8 two, often
  three; the boss adds one more, each in its own `run.chaos_rng(index)` stream (never song_rng's,
  so no existing seed-replay test shifted a single number), scheduled 10 s into a brief's clock to
  8 s before its end, two strikes never closer than 8 s apart, honestly short rather than
  crowded if a `shorter_clock` card leaves no room. Sync rode the schedule, not a verb-by-verb
  wire: once a brief starts, every peer knows the whole schedule (`run.events`/`event_at`/
  `event_track`), so each one's own `Tour.chaos_telegraphed`/`chaos_struck` (the one signal pair
  here that is not host-only) fires off that peer's own `brief_elapsed()` -- the host's exactly,
  a guest's anchored to the host's last publish and re-anchored every one after -- reconciled
  against the actual wire state (`Tour.chaos_shown`) so a late joiner or a long hitch still lands
  on the right line rather than a stale one. The room says so before it happens: the practicals
  flicker and the case rattles on every peer at the telegraph (`scenes/studio.gd`'s
  `_flicker_lights`/`TourCase.rattle`, `Foley.chaos_warning`), `power_flicker`'s strike kills the
  practicals and the venue's own house lights for a bar (`Venue.blackout`, new and a no-op by
  default -- only the studio has fittings of its own to kill) and `crowd_throws` lobs up to three
  of the room's own loose props in from the back of house on the host (`ItemRoom.fly`, seeded, so
  a replay throws the same things at the same spots; a guest sees it through ordinary room
  state, nothing new on the wire for it). `tools/verify.sh` ends clean (7012 checks, 0 failed);
  `shots/tour_chaos.png` (band of one, a struck HAT mute and a telegraphed crowd-throw both on
  the card at once, via a new `--tour chaos` shot state) is the record. Reviewed the same day,
  against the schedule window, recoverability, and sync by hand rather than a second pass (the
  pass itself ran out of session before it could run): the math behind `_tick_chaos`'s "which
  elapsed crosses which threshold" was traced through `TourChaos.schedule`'s own bounds, every
  event's `_recovered` was confirmed to read nothing but `MixState`/`run` (DAW verbs or their own
  schedule, never a surface or a signal), and `_lights_out`/`_flicker_lights` share one tween
  (`_lights_tween`, killed before the other starts one) so a second strike mid-blackout can never
  fight the first over a lamp, with `_relight` on a run ending mid-dark so the room is never left
  that way once there is no brief left to light it back up for. Not chased: `power_flicker` and
  `solo_leaned` can both land on the same strip in one brief (nothing excludes the pairing), which
  reads as one strip in real trouble twice rather than two separate events -- harmless, maybe even
  good, but not an intended pairing; and a venue beyond the studio has no fittings for
  `Venue.blackout` to turn off, so `power_flicker` there is only ever the practicals, never a true
  blackout -- fine today (the studio is Tour's only venue) but worth remembering once a second
  one exists.
- **The crowd's ear. Done 2026-10-11.** Master-bus loudness and balance as two live bars every
  brief with `crowd: true` (every one today) runs on top of its own measures, judged continuously
  rather than sampled once at the end: `TourMeasure.Ear` (new, nested under `TourMeasure` beside
  the per-brief samplers) drops an `AudioEffectSpectrumAnalyzer` onto the master bus for a
  brief's duration and keeps a rolling 2 s average of peak (fader-compensated through
  `DAW.taper_to_db`, same as everything else that reads a strip's level) and three spectrum
  bands; `TourEar` (new, `core/tour/tour_ear.gd`) is pure arithmetic over that reading -- no
  `AudioServer` touched -- judging LEVEL (too quiet / happy / too loud) and BALANCE (thin / clear
  / mud, the sign off `tilt_db`) with hysteresis so a reading on the line does not chatter, and a
  stricter window for the boss brief. `Tour._tick_crowd` reads `_ear.result()` every physics tick
  once `_ear.ready()` (host-only -- real loudness and spectrum measurement needs real audio,
  `is_available()`'s existing rule), publishing `run.crowd_happy`/`crowd_over` only on change; a
  struck bar blocks the brief's pass exactly as an unfixed flaw or an open chaos event does
  (`TourBrief.judge`'s new "crowd" block), but only once the ear has actually heard a full
  window -- `total == 0` gates nothing, so the stand-in backend and every existing OfflineBackend
  test pass exactly as before this existed. The HUD gained two always-present lines (`TourHud`'s
  `_crowd_box`, `_refresh_crowd`) reading "listening..." in dim until heard, then the words in
  INK or ACCENT, and the tag line's `CROWD OK/--` suffix.
  The thresholds were not guessed twice. The first pass at `TourEar.THRESHOLDS` was written
  before the probe that was supposed to measure it ever ran, and failed the probe's own
  self-check 6 of 18 the first time it was actually run: every clean row read "thin" by tens of
  dB, because the built-in engine's own mix sits far brighter in low/mid than top on every clean
  row (DemoSong's own parts, nothing any Tour flaw touches) -- HIGH reads 40-50 dB under LOW/MID
  even with nothing wrong, so the clean band's real spread is ~25 dB, not the single digits the
  placeholder assumed. Re-measured for real (`flock ~/.cache/dawlings/shared.lock
  tools/tour_ear.sh --flaws all --diag --repeat 1`, tempo 84/100/124, clean and every flaw) and
  the thresholds rebuilt off the actual rows: `quiet_db` sits 6 dB under the quietest happy
  average measured (quiet_vox@84), `loud_db` 2 dB over the loudest happy average (hard_pan@124),
  `spread_max_db` 3 dB over the widest happy spread (hard_pan@84) -- each with room to spare
  before the nearest case meant to read trouble (muddy_bass, band_+6, a faded master). The boss
  window halves every margin and is still cleared by every happy row. `tools/tour_ear.sh` (new,
  `tools/probe/tour_ear.gd`) is the tool that measurement came from and the one that re-checks it
  on every future run -- real master-bus audio into the null sink, never a real speaker or mic,
  its own command rather than part of `tools/verify.sh` since it renders real audio to measure.
  Six tests (`_test_tour_ear_reads_inert_off_the_stand_in`, `_test_tour_ear_judges_from_its_table`
  pinning the hysteresis and boss-window arithmetic to the measured table itself so an edited
  threshold fails here before it ever reaches the probe, `_test_tour_brief_judges_the_crowd`,
  `_test_tour_brief_waits_for_the_crowd` end to end through `Tour._physics_process` with a
  `_FakeEar` stand-in, `_test_tour_run_round_trips_the_crowd`, `_test_tour_hud_shows_the_crowd_lines`).
  `tools/verify.sh` ends clean (7048 checks, 0 failed, same harmless pre-existing "already has a
  parent" noise from `DAW.use()`'s swap-and-free pattern that every other `DAW.use` test also
  prints, nothing new); `shots/tour_crowd.png` (a new `--tour crowd` shot state, one bar happy in
  ACCENT, one unhappy in INK, both drawn at once) is the record. Reviewed by hand: the tick is
  host-only and the two bars ride `_publish()` like every other per-run field rather than each
  peer measuring its own local audio, so a guest's HUD reads the host's room, not its own
  speakers; the `total == 0` gate was checked against every existing OfflineBackend-only test
  (chaos, flaws, parts, timing) to confirm none of them now blocks on a crowd that was never
  there to hear anything; `_ear` is let go (`stop()`, nulled) on every exit from BRIEF state
  (`_finish_brief`, `_end_run`, the force-state shot cases, a participant leaving mid-run) so a
  run that ends mid-window never leaves an analyzer on the bus. Not chased: the probe's placeholder
  bug (above) is the kind of thing worth a second probe-shaped feature catching before it ships
  rather than after -- no action taken here, just noted for the next one that measures something
  off real audio.
- **Juice.** The crowd reacts to each fix, the case's stinger, a cheer at the drop, the HUD's
  lines landing with a hit. Three pieces done. **A brief ends on the bar, not the frame. Done
  2026-10-11.** Whatever qualifies a brief to end -- every flaw fixed and part played, a struck
  chaos event put right, the crowd happy, or simply the clock running out -- used to call
  `_finish_brief()` the instant it happened, wherever in the bar that fell; it now holds until
  the song's own next bar (`MixState.next_bar_start`, new, the same two maps `count_in_start`
  already reads -- a tempo map and a meter -- run the other way round: the next bar at or after a
  position, through whatever tempo or time-signature changes lie between, rather than the bar a
  count-in starts before). `run.seconds_left` freezes the instant it qualifies rather than
  ticking further while the song finishes its bar, so the score a player actually earned is
  exactly what it would have been without the hold -- nobody is charged for the wait. A stalled
  transport (nothing playing, no `DAW.state`) is never left hanging: `_BAR_WAIT_CAP_SECONDS` (4 s,
  comfortably past the longest bar any of today's tempos draw) finishes anyway past that. Caught
  on the way: the pending wait (`Tour._finish_at`) is a field on the autoload singleton, so a test
  that hands `Tour.run` a fresh run directly (most of the suite's briefs do, rather than going
  through `start_run()`) would have inherited whichever bar the *previous* test's brief was
  waiting on -- it now clears in `_finish_brief()` and `_end_run()` both, not only where a brief
  normally starts, so nothing a test (or a future caller) does can leave it stuck. Three tests:
  `MixState.next_bar_start`'s own arithmetic through a time-signature change (next to
  `count_in_start`'s own test, same fixture), and `_test_tour_brief_finishes_on_the_bar_not_the_frame`
  driving `Tour._physics_process` end to end -- qualifying mid-bar holds, a tick still short of the
  bar still holds, the tick that reaches it finishes into the draft. `tools/verify.sh` ends clean
  (7057 checks, 0 failed). No new screenshot: this is a timing change, not a visual one --
  `shots/tour_bar_end.png` (the ordinary draft screen) is a sanity check that nothing else moved,
  not a demonstration of the fix itself, which the tests carry.
  **The crowd reacts to each fix. Done 2026-10-11.** A fix landing used to say so only on the
  HUD (the line's already-built flip from INK to ACCENT, `TourHud._refresh_flaws`) -- now the
  room says so too, on every peer, the instant its own copy of `run.fixed` turns a flaw true:
  `Foley.crowd_cheer` (new, a swell of filtered noise with three short upward whoops riding it,
  the bright counterpart to `crowd_rumble`'s low mutter of trouble), played from the back of
  house where the rest of the crowd's sounds already come from. Wired the same not-host-only way
  `chaos_telegraphed`/`chaos_struck` already are (`Tour.flaw_fixed`, new): every peer, host and
  guest alike, watches its own copy of `run.fixed` -- which needs no clock of its own the way a
  chaos event does, since it is already a plain true/false the host publishes -- rather than
  waiting on a signal only the host could ever emit. `Tour._tick_fixed_shown` (new, beside
  `_tick_chaos_shown` in `_physics_process`'s both-host-and-guest block) keeps a per-peer
  `_shown_fixed` so each flaw cheers exactly once, reset at both of `_shown_chaos`'s own reset
  points (`_lay_out_chaos` on the host, `_on_tour_changed`'s key check on a guest) rather than a
  third place of its own, since a flaw's fixed-ness only ever means something for the brief
  `_shown_chaos` is already keyed to.
  Caught on the way: wiring `flaw_fixed` into `scenes/studio.gd` (the same `_play_at` helper
  `crowd_throws`'s rumble already uses) surfaced a latent bug in that helper, not a new one --
  several existing tests `remove_child` a `Studio` once they are done with it but never free it,
  leaving its signal connections live on a node with no `SceneTree` of its own; `flaw_fixed`
  fires often enough (every flaw a test's own brief happens to clear, not just the rare
  `crowd_throws`) that this stale-studio hazard finally got hit. Fixed with the same
  `not is_inside_tree()` guard `_walk_to_seat` already needed for the same reason, in `_play_at`
  itself, so `crowd_throws`'s own rumble is covered by the same fix. One test
  (`_test_tour_flaw_fixed_fires_once_per_flaw_from_the_wire`, mirroring the chaos telegraph
  tests' shape): fires once a flaw off a guest's own wire state, settles on repeat ticks, and a
  fresh brief's already-fixed flaw (even one that reuses a flaw id) fires fresh rather than being
  swallowed as "already shown" -- the same singleton-leak care `_finish_at` needed. `tools/verify.sh`
  ends clean (7059 checks, 0 failed); `tools/session_probe.sh` default and `--built-in` both green
  ([host] 53/0 and 79/0, [guest] 47/0 and 42/0). `shots/tour_cheer.png` (a brief mid-flight, one
  flaw still open) is a sanity check that nothing else moved -- the cheer itself is a sound, which
  the test carries, not a visual the HUD didn't already have.
  Not chased: `tools/tour_probe.sh 8` (and `4`) turned up a real but pre-existing flake --
  confirmed unrelated to this change by running the same probe against master before it (same
  failure shape, "every part played and every flaw fixed ends the brief early" cascading into an
  unscored brief and a skipped draft, roughly every other run at 4 and 8 players) -- real
  multi-process timing, not something this change touched. Worth its own iteration.
  **The lid rattling as the clock runs out. Done 2026-10-11.** Named outright in the goal, and
  still open: a brief's last stretch used to say nothing until it actually ended. `Tour.clock_low`
  (new, third of the not-host-only presentation signals beside `chaos_telegraphed`/
  `chaos_struck`/`flaw_fixed`) fires once a brief, on every peer off its own `brief_elapsed()`,
  the moment `CLOCK_LOW_SECONDS` (10 s, the same idiom as `TourChaos.FIRST_SECONDS`) remain --
  win or lose still undecided, same as a chaos telegraph not knowing which way a struck event
  will go. `TourCase.rattle` (already built for the telegraph's own quick jitter) takes the whole
  ten seconds this time rather than its default 1.6 s -- the room living through the final
  stretch with the band rather than just warning it is coming -- plus a `Session.notice`
  ("Ten seconds. Finish it.") for anyone not looking at the case.
  Caught on the way: the ten-second rattle and a chaos telegraph's short one can land within
  seconds of each other near a brief's end -- both are scheduled off the same last-ten-seconds
  window (`TourChaos.LAST_SECONDS`/`TELEGRAPH_SECONDS` put a strike's telegraph as late as
  `total - 10`, the exact moment `clock_low` fires) -- and two tweens fighting over the lid's own
  `rotation_degrees:x` would have left it stuttering between them. `TourCase._lid_tween` (new)
  kills whichever rattle was already running before `rattle()` starts another, the same
  `_lights_tween` kill-before-start `scenes/studio.gd` already needed for the exact same reason.
  One test (`_test_tour_clock_low_fires_once_near_the_end_of_the_brief`, the host-clock half of
  the chaos telegraph test's own shape): not yet at 15.5 s left, fires once crossing 10 s, settles
  on further ticks. A new `--tour clock_low` shot state (`Tour.force_state_for_shot`, alongside
  `chaos`/`crowd`) forces a brief to 9.5 s left and calls the real tick once, so the screenshot is
  the actual signal path, not a mock of it. `tools/verify.sh` ends clean (7062 checks, 0 failed);
  `tools/session_probe.sh` default and `--built-in` both green ([host] 53/0 and 79/0, [guest]
  47/0 and 42/0 -- unchanged from the last iteration's counts, since neither probe runs a brief
  through a real Studio). `shots/tour_clock_low.png` (the HUD's own card reading "10 s" with "Ten
  seconds. Finish it." on the notice line beneath it) is the record -- the case itself is off
  camera in this framing, so the rattle is what the test carries, the notice is what the shot
  carries.
- **Stakes and rewards.** Reputation that buys something (venues, cosmetics on the ghost, a
  second life). Two pieces done -- a win that is announced to the room, a loss that costs a
  point. **A win that is announced to the room. Done 2026-10-11.** `reputation` has existed on `TourUnlocks` since the run-saving work
  that gave it `runs`/`wins` -- bumped a run a win, saved, never once shown to anyone. A run's
  own end used to say nothing to the room either: `scenes/studio.gd`'s `_on_tour_run_ended`
  dropped its own `won` parameter on the floor (`_won`, unread) -- the case re-chained and its
  tally brought up to date, nothing more. Now it reads: `Session.tell_room` (the same host-only
  broadcast a take's own placement or a file brought in already uses, not
  `Session.notice.emit` alone -- this is host-only, unlike a chaos telegraph's every-peer-
  computes-it-itself pattern, and a guest has no wire state left to read the result off once the
  run is gone, only this one broadcast) tells the whole room "The gig's a hit. Reputation %d." or
  "That one got away. Reputation %d.", the fresh number read straight off `Tour.unlocks`
  (`_end_run`'s own `unlocks.record_run` already ran by the time this fires). Paired with the
  other half of this same moment, which is really juice: `Foley.win_fanfare` (new, a four-note
  rising run voiced in parallel fifths -- bigger than `tour_stinger`'s own three notes, a room
  cheering back rather than a case bursting open) for a win, `Foley.loss_sting` (new, two notes
  falling instead, over almost as soon as they start) for a loss, played from the case the same
  way its burst already is.
  One test (`_test_tour_run_ended_announces_the_result_to_the_room`): a win's line contains the
  fresh reputation and reads as a win, a loss's line contains it too and does not. `tools/verify.sh`
  ends clean (7067 checks, 0 failed); `tools/session_probe.sh` default and `--built-in` both green
  ([host] 53/0 and 79/0, [guest] 47/0 and 42/0, unchanged -- neither probe runs a Tour run through
  a real Studio). A new `--tour win` shot state calls the real `_end_run(true)`, not a mock of it,
  so `run_ended`'s own listeners (the case, the room) fire for real; `shots/tour_win.png` ("The
  gig's a hit. Reputation 1.") is the record.
  Not chased, but checked harder this time: `tools/tour_probe.sh`'s flake (noted two iterations
  back as an 8/4-player thing) turned up at 1 player too, 2 of 3 solo runs -- and reproduces at
  the same rate on master before this change (also 2 of 3, same failure shape), confirmed by
  stashing this iteration's own diff and re-running. Not player-count-dependent, not this (or the
  last) change: a real timing issue in the probe's own real-time multi-process harness, worth its
  own iteration rather than a guess bolted onto this one.
  **A loss that costs a point. Done 2026-10-11.** `TourUnlocks.record_run` only ever added
  reputation on a win; a losing band kept exactly what it had, same as never having played. Now
  a loss costs one point, floored at `maxi(reputation - 1, 0)` so a losing streak never goes
  negative -- a band on a bad run is never worse off than a band that hasn't played yet, only no
  better off. The room's own loss line now says so: `"That one got away. Lost a point --
  Reputation %d."`, the win line's `Foley.win_fanfare`/`loss_sting` pairing unchanged.
  One test (`_test_tour_unlocks_a_loss_costs_a_point_of_reputation`): a loss at 0 stays at 0, two
  wins bring it to 2, a loss brings it to 1, two more losses floor it back at 0 rather than
  -1. `tools/verify.sh` ends clean (7067 checks, 0 failed, 0 SCRIPT ERROR); `tools/session_probe.sh`
  default and `--built-in` both green ([host] 53/0 and 79/0, [guest] 47/0 and 42/0, unchanged).
  A new `--tour loss` shot state mirrors `&"win"`, calling the real `_end_run(false)`;
  `shots/tour_loss.png` is the record -- the restored project, no regression, though the room's
  toast itself sits behind the desk's own arrange panel at this camera's default framing in both
  the win and loss shots, so the line is read off the test's own capture of `Session.notice`
  rather than off the pixels. `tools/tour_probe.sh 1` green; `tools/tour_probe.sh 4`'s known flake
  ("the part count matches the catalogue") checked again by stashing this iteration's diff and
  re-running on bare master -- same failure, same shape, confirmed once more not this (or any
  recent) change.
- **A second boss and a run map.** Two venues, a branching map of briefs with a choice at each
  fork, a boss that plays differently from the first.
- **Rig Roulette: gear off the run's own seed. Done 2026-10-11.** (The user, 2026-10-11, from a
  Riff Randomizer YouTube episode they watched -- two musicians spin wheels for tuning, key,
  tempo, and several rolls each of guitar amp sim, bass amp sim, drum kit, and synth, then have
  to write a real song using whatever the wheels gave them, no re-rolling. Renamed so it's its
  own thing rather than the show's own name.) A brief's seed already rolls tempo, key, and flaw
  (see "Seed randomness" above); this extends the same idea to the signal chain. Decided by the
  user: any instrument/character FX are fair game (not just amp sims and synths -- distortion,
  modulation, reverb character too; utility FX like EQ/compressors/limiters stay out, not a
  "constraint" a band plays around), the pool is built only from what is actually present rather
  than a blind roll that skips a miss, and this runs alongside the flaw system rather than
  replacing it.
  Found on the way, before writing a line of it: Tour only ever runs on the built-in engine
  (`Tour.is_available()` requires `GodotBackend`), and the built-in engine has no amp sims or
  synth patches to spin at all -- its real plugin catalogue (`core/built_in/fx_catalogue.gd`,
  reached through `DAW.state.fx_choices`/`DAW.add_fx`, already used by the existing "Free Effect"
  draft card) is Godot's own generic bus effects: EQ, compressor, limiter, reverb, delay, chorus,
  filter, distortion, phaser. "The host's own install" the user asked for, in a world where Tour
  never runs against a real external Reaper's VSTs (a third-party plugin host was explicitly
  parked by the user 2026-10-10, see "Parked" below), means the built-in engine's own real list --
  so this is built as the honest version of that idea against what is actually there: five of
  the nine kinds read as "character" (`distortion`, `chorus`, `reverb`, `delay`, `phaser`) and are
  the only ones a spin can land; the other four (`eq`, `compressor`, `limiter`, and the implicit
  "nothing") stay out, matching the user's own category call almost exactly without having to
  reopen it.
  Baked the same way a flaw is -- not a card, not judged, not shown on the HUD -- because a
  flaw's own `bake(project, rng, tempo)` writing straight into the `DawKitProject` before it is
  loaded was already exactly the right shape for "real, seeded, audible, replayable, reset for
  free when the run's snapshot restores." `TourProject.song_for` grew two new optional,
  defaulted params (`band_size := 1, brief_index := 1`, both defaulting to values that land zero
  pedals, so every one of the ~20 existing call sites across the suite needed no change at all)
  and, after the flaws loop, rolls `TourProject.rig_count_for(band_size)` pedals (0 for a duo or
  fewer, 1 for four, 2 for six, 3 for eight -- a beat gentler than `TourFlaws.count_for`'s own
  climb, since this is varnish, not difficulty) onto that many distinct, shuffled, non-Stage
  tracks a flaw has not already claimed (so a band never has two different things to listen for
  on the same strip), using the run's own song-seed stream continuing right where the flaws left
  off, never on the first brief (same reasoning as chaos events: the first brief is for learning
  the band's own flaws, not the room's). Each pedal gets the catalogue's own safe defaults
  (`FXCatalogue.defaults(kind)`), not random knob positions -- tasteful variety, not an extra way
  to sound actively bad on top of the flaw the band is already fixing.
  One dedicated test (`_test_tour_rig_roulette_lands_character_fx_on_a_big_enough_band`):
  `rig_count_for`'s own curve; a solo band gets none; a full band gets none on the first brief
  even though it would otherwise qualify; a full band's second brief lands exactly three character
  (never utility) pedals, never on Stage; the same seed lands the same gear twice; a track a flaw
  already claimed never also gets a pedal. `tools/verify.sh` ends clean (7087 checks, 0 failed, 0
  SCRIPT ERROR -- no new `class_name`, so no `--import` needed this time).
  `tools/session_probe.sh` default and `--built-in` both green ([host] 53/0 and 79/0, [guest]
  47/0 and 42/0 -- one unrelated real-time timing flake on the first default run, a one-off,
  confirmed clean on a re-run and unrelated to anything touched here). `tools/tour_probe.sh` at
  1, 4, 5 and 8 players all ran a full real brief correctly with rig roulette live, project
  structure unaffected (still "12 tracks" on arrival); the pre-existing "part count matches the
  catalogue" flake (now reconfirmed five times, across five separate iterations) turned up again
  at 4, 5 and 8, reconfirmed once more at 5 by stash/re-run against bare master -- identical
  failure, still not this. A new `--tour rig` shot state (mirrors `&"chaos"`: starts a run, advances past
  the un-rollable first brief if still on it, emits `brief_started` so the HUD actually rebuilds)
  plus `--tour-band` is now permanent infrastructure. `shots/tour_rig.png` is a real 8-player
  "Tone Check" brief firing end to end -- four flaws, seven parts, four spilled instruments, the
  live HUD -- caught before the physical FX rack that would show the rolled pedals' names could
  be framed in the same shot; the test above is what actually proves the pedals themselves landed
  right, the same honest trade the loss/win shots already made about the room's own toast.
- **Scale testing: solo, 4, 8. Done 2026-10-10.** `tools/tour_probe.sh N` (N 1..8) runs a brief
  as a host with N-1 real guest processes -- every flaw fixed and every part played from the seat
  that holds it, a draft pick carried over the wire, the roster checked by name so eight is
  eight, the host's project back exactly as it was -- and prints what each seat sees
  (tools/session_probe.sh's shape), on top of the suite's count checks. Slow (about 35 s a run),
  so it is its own command, not part of tools/verify.sh.
- **A held key rolls over to channel 0.** `GuestMidi.follow`'s per-bar take roll replays the
  keys still held into the fresh take with channel 0 (`held` keeps only the velocity), so a note
  straddling a roll lands on channel 0, stretched to the take's end, where a channel-9 part's
  judge no longer counts it. Unreachable by hand (a percussion hit is over in milliseconds and
  the keytar's parts accept any channel but 9), found by the probe; the fix is `held` keeping
  the channel beside the velocity.

### Waiting on the user
- The flaw lines' voice: gig-crew terse (as written) or a named character (a stage manager, the
  promoter) speaking them?
- Should a brief end the moment the last flaw is fixed (as built, score rises with time left),
  or play the loop out so the band hears the fixed song once?
- Twelve strips for a solo player: fine, or a smaller band (drums, bass, keys, vox) under four?
- Should a part be judged per holder (needs per-player lanes, or takes named and trusted) or per
  instrument, as built (one shared Stage lane, told apart by channel/pitch -- what both
  recorders' "lands on the first armed track" forces today)?
- Should the drum pitches on the Stage lane sound as drums rather than tine pings -- it is a
  MIDI lane like the keys stab lane, played through the engine's own tine, not a drum kit.
- The shaker parts' windows (0.1 beat on eighths, 0.12 on the offbeats: about 50 ms either way
  at 124 BPM) are the tightest in the catalogue, sized so flailing fails a half-beat grid; with
  a mouse-flicked shaker they may be the one part a solo player cannot clear. Play-test before
  loosening them, or draw a solo player's one part from the tambourine and keytar only.
- Keep both sound curses on a spilled instrument (sour at -1.5 semitones is subtle on a cowbell;
  low at an octave is the obvious joke) or just the one?
- Should a spilled instrument persist across runs as an unlock (stays in the room from then on)
  rather than go back in the case when the run ends, the way the rest of the gear resets?
- Is a curse spill really a curse for a big band -- it is more to do, which on a crowded card is
  what they came for. Maybe it only reads as a curse solo or in a duo.
- What reputation should actually buy (venues, cosmetics on the ghost, hats and case stickers,
  a second life mid-run) and, if a second life exists, what it costs and whether it is bought
  before a run starts or spent in the moment a brief is about to go wrong -- wins/losses move the
  number (above), but spending it is a shop or a run-time choice either way, not a one-line fix.
- The rest of the original Tour goal, parked here as a block rather than a taste question: the
  user capped the loop's scope at "Rig Roulette + more instruments" on 2026-10-11 (both now done,
  see "Rig Roulette" and "Way more instruments" above), so nothing below gets built without the
  user lifting that cap first. Not a list of what is missing from the codebase -- some of it
  already exists (chaos events: `core/tour/tour_chaos.gd`; several stingers/fanfares: `Foley.
  tour_stinger`/`win_fanfare`/`loss_sting`/`chaos_warning`/`chaos_strike`/`case_toss`; reputation
  that rises and falls: `TourUnlocks`) -- just the parts that are still genuinely unstarted:
  hat/case-sticker cosmetic unlocks, per-player tallies, a live countdown built specifically for
  a watching guest, the band voting on drafts with the host breaking ties, a second boss, and a
  run map with paths to vote on. Each is a real taste/design call (how reputation should be
  spent is its own entry just above), not a mechanical follow-on from what is already built.

## Parked

- **Where the host keeps guests' recordings.** Takes are written to `user://takes/` and, on
  Reaper, copied beside the project when it has been saved. Unsaved, Reaper points at the copy
  in `user://takes/`. Whether the host should choose a folder (or be asked on first take) is a
  decision for the user.

- **More than about ten listeners.** A session admits up to 32 guests (Godot's default), but
  the mix is uncompressed at about 1.5 Mbit/s per listener, and there are 8 colours, so the ninth
  ghost shares one. Opus would make the audio cheap, and a longer palette (or hue variants) the
  colours. Not started: nobody has asked for big rooms yet.

- **Third-party plugins through a Carla sidecar.** Parked by the user 2026-10-10 ("unnecessary
  at this point"). If it comes back: Carla is GPL, so only as its own process, spoken to over
  OSC, using a Carla the user installed (on the PATH), never bundled; instruments on MIDI tracks
  first, effects (audio out and back, latency compensation) after.

## Decided (2026-10-10, the user handed these over: "what makes most sense legally, game fun-wise")

- **Hearing your own keys: through the track by default, fast on a switch.** Decided fast at
  first, for the feel, and then measured: `--built-in` put the host's key straight out (the
  native helper, 15.5 ms) and its recorded note landed 40 ms after its sound in the loopback.
  A key is stamped where the song was as heard, and how late the song is heard is only known
  from Godot, whose report leaves out the sound server's own buffering; through the track the
  key is exactly as late and the two cancel. So the take wins: "Hear my keys through the track"
  is on by default (GuestMidi.through_track), and off plays them straight out, the tooltip saying
  notes can land late. To make fast the default, the game needs the song's real output delay:
  the native helper could time a quiet click from Godot in the sink's monitor (digital, so a
  -60 dB click is plain), which is the open item for it.
- **The engine mixes its own players, in a GDExtension (C++).** Sample-accurate playback needs
  dawkit to mix every track itself, sample by sample, which GDScript is too slow for in a real
  project, least of all on a standalone headset, the headline client. C++ through godot-cpp
  (MIT) builds for desktop and Android arm64 alike, and a compiled engine is also what can be
  sold without handing over its source. dawkit keeps a GDScript face (the project model, the
  file formats, the API), and the mixing core moves into the extension.
  - **Stage 1 done 2026-10-10 (dawkit 5acf743):** `native/` builds with CMake and godot-cpp
    (master, against `godot --dump-extension-api` of this 4.7.2) into addons/dawkit/bin;
    `DawKitTransport` (the song anchored to a block clock the lanes count between them) and
    `DawKitLane` (a track's clips: interpolated at their own rate, offset, gain, linear and
    equal-power fades, looped stretches; sounds kept by id). dawkit's tests mix lanes a block at
    a time in alternating order and one that joined late, and find a clip's first sample on the
    same frame in each. verify.sh builds it first; the game loads it. Next: stage 2, GodotBackend
    playing items through lanes (takes, imports, the demo parts' windows, MIDI renders, the
    click), then the render cut on the sample, and an Android arm64 build for the headset.
  - **Stage 2 done 2026-10-10:** GodotBackend plays through `LaneEngine` (takes, imports, MIDI
    renders, demo parts and their tempo-map windows, the click on its own unheld lane), the
    newest item heard where items overlap, sends and cues as more playbacks of the track's lane.
    The probe prints "engine: native lanes". Measured on --built-in: a render's notes 1.33 ms
    after their place, the same in every note (1.04 ms of it the instrument's attack); the
    count-in's clicks within 0.00 ms of each other. Headless runs keep the players. Next: the
    render cut on the sample, an Android arm64 build.
- **dawkit's licence: proprietary, sold under a commercial licence; the name stays.** Not dual
  GPL: a GPL edition would let anyone ship it free in a GPL game, and GPL sits badly with console
  and store terms. A search found no audio product called DAWKit (not a trademark clearance,
  which wants a lawyer before money changes hands). The compiled core ships as binaries, the
  GDScript face as source, under one per-developer licence. Third-party material in dawkit is
  listed in its THIRD_PARTY_NOTICES (the DAWproject examples and schema, MIT).
- **dawkit's private remote** needs a push to the user's GitHub, which this loop does not do;
  `gh repo create dawkit --private --source ~/Projects/dawkit --push` and pointing
  `.gitmodules` at it is the whole of it, when the user says so.
- **A guest hearing their own voice: the interface's direct monitoring, plus an opt-in.** Direct
  monitoring costs nothing and is how most singers hear themselves; the game does not play a
  voice back by default, since a laptop's mic and speakers feed back. "Hear my mic" on the guest
  panel, off by default and saying to wear headphones, plays it through the native helper's
  duplex path at its latency.
- **Per-track cue stays with the built-in engine.** Per-listener stems cost the host's upload
  per listener, and Reaper's hardware cue outputs need routing only the user can do. On Reaper
  and for a guest the tablet keeps saying "not here".
- **Another player's mic in the personal mix: not built.** It costs the singer's upload per
  listener and tens of ms; voices reach the room through the host's mix and the takes.
- **"Their monitor": not built.** A staged performance for its upload cost, not a way to play
  together.

## Not started

- **A guest's microphone, calibrated.** Audio takes from guests work (see "Recording a guest"
  in docs/architecture.md), measured with a synthetic microphone. A real card that misreports
  its input latency puts takes early or late by the error; a clap-on-the-click calibration that
  sets `GuestAudio.offset_ms` would close it.
- **Hearing your own microphone** through the game while recording, with its latency allowed
  for the way "Hear my keys" is.
- **A calibration routine for the capture offset** (`R3D_CAPTURE_OFFSET_MS`): record a guest
  playing on a click into the host's Reaper and read the offset off the take.
- **Live preview of a guest's notes on the host** through Reaper's `/vkb_midi/` OSC path,
  labelled as late.

- **Mobile renderer pass.** `project.godot` sets the override; nothing has been tested on a
  standalone headset, and the headline hybrid client is exactly that.

- **Reaper parity, still missing** (after sends on faders, the click, the locator and input
  monitoring):
  - Send mute: there is no OSC address for it, so it would be a bridge edit.
  - Pre-roll: done (4h above).
  - Automation modes. `t/track/@/autoread` and its siblings exist, but Reaper reports them only
    for the selected track.
  - FX: adding and removing done 2026-10-10 (`DAW.add_fx`/`remove_fx`, undoable; what can be
    added is the DAW's own, `MixState.fx_choices`, `/fxchoices`, so a guest may add only that:
    Godot's effects built-in, Reaper's stock plugins there, the bridge's AddFx refusing any other
    name). The rack's window over its track window adds; a fine press on a unit's POWER removes.
    Built-in, a chain laid down (moved, added, removed or undone) re-stacks the bus's effects:
    undoing a move left the bus as it was before. Read back on the rig. The Reaper host's work
    ends at 48.2 s of 49.4. (Presets and wet/dry were already there.)
  - Tracks: done. Adding, removing and renaming were already there; colour done 2026-10-10
    (`DAW.set_track_colour`, undoable, a guest's sanitised; the bridge's SetTrackColour; the
    timeline's COLR key steps the picked track through a palette). Read back on the rig through
    the structure poll, within 8 bits a channel. The Reaper host's work ends at 45.0 s of 46.4.
  - Markers: renaming, moving and removing done 2026-10-10 (`DAW.edit_marker`, `remove_marker`,
    undoable, a guest's sanitised; the bridge's EditMarker and RemoveMarker find the marker by
    position to a millisecond). MARK on a marker (where PREV and NEXT land) renames it, on the
    monitor or a keypad in a headset; a fine press removes it. Read back on the rig. There is no
    gesture to move one yet. Regions of any kind: not started. The probe's end moved 3 s later
    (host 49.4/50.4, guest 48.5/50.0); the Reaper host's work ends at 47.0 s.
  - Time signature: done 2026-10-10 (step 7f), through the bridge.
  - `tools/shot.sh --focus patchbay` frames only the floor.

## Known rough edges

- Seen from a second machine: the colour round what somebody holds is faint on small things
  now that it is gentle enough for a keytar. Their glove's cuff and their caption still say
  whose it is. A keytar in a ghost's hand still shows a hot spot where the desk lamp catches its
  gloss. `tools/session_shot.sh` sometimes starts the guest before the host is listening, and
  that guest never joins.

- The radio plane: putting the radio down puts the plane back beside it at once, from
  wherever it was, even mid-flight. A mirror shows your ghost holding the radio but never the
  plane. Other machines ease their copy toward the last pose they heard, so it trails the
  flyer's by a tenth of a second or so, and a crash's tumble there is only as smooth as 20
  poses a second make it. It is flown only from its
  own steering: no wind, no stall, no loop the loop. A crash always ends in the same nosed-in
  heap. Throwing the radio throws the docked plane with it. Not tried in a headset, and never
  flown in front of a second machine outside the tests.

- Pockets: nothing on screen shows what is in them but a notice when they change, and the
  mirror. Anything fits in any pocket, a keytar at the hip included. The ghost's pocketed
  things are real size on a ghost that is not, so a duck at the hip is small. Never tried in a
  headset, where the hips are guessed from the head.

- The venue toys: they are all thrown things, a ball of some kind (or a starfish); none of them
  does anything the others cannot but fly differently. No slinky, nothing to fidget with, and no
  desk toy by the console. Changing venue mid-throw lets the old flight finish, then shows the
  new venue's toy where the old one landed.

- The yo-yo: on a desktop your own string is 15 cm and your ghost's is 70 cm, so what you see
  of your own trick is not what others see. The string is a straight line, never slack, even
  over the top of around the world. No "walk the dog" along the floor.
- The cradle: the balls are swung as one group, not five bodies, so nothing but a clean one,
  two or three out happens (no ball nudged by hand, no messy collisions).
- The hoop: a desktop throw of the ball goes along the view with a loft, not at a target, so a
  basket from the desk takes practice; there is no aim assist and no shot count or streak. The
  base solid stops the walker but the ball rolls under the lamp arm's height freely. The chalk
  hoop is drawn but has no net of its own to swing.
- Darts: no game round them (rounds of three, a running total, 501 down to zero); each throw
  is scored alone. The aimed throw is desktop only; in a headset a dart flies as the arm throws
  it, untried.
- Chips and cards: their tricks run on the hand's button, so in a headset they are a trigger pull,
  not a gesture (a thumb flick, two hands for a shuffle). Their state is only the count of tricks
  since pick-up, so somebody joining mid-fidget sees a fresh stack until the item is put down.

- Keytar: it is not yet tried in a headset, where the pose by its neck grip is untested.

- Hand percussion: another player's hits are heard in the room only. No socket carries them into a
  personal mix, and they are not in their ON AIR monitor. On a desktop, sweeping the cursor
  across the room with an instrument in hand can play a hit when the sweep stops. Not yet played
  in a headset.

- `PatchCable` rebuilds its whole mesh on every patchbay rebuild rather than moving endpoints.
- The timeline rebuilds every lane while the overview bar is being dragged -- one rebuild per
  frame, which is fine at twelve tracks and will not be at ninety. Items want to be moved
  rather than recreated, the way the playhead already is.
- The offline stand-in's meter ballistics are eyeballed, not matched to Reaper's.
- The master section has no monitor level, dim or mono. Those belong to a monitor controller,
  which Reaper does not know about and has no OSC address for -- deliberately absent rather
  than faked, and the gap closes only if something other than Reaper ends up driving it.

## Blender-authored parts

Done: the knob (`tools/blender/knob.py` → `assets/hardware/knob.glb`).

Finding from photographing it: **the knurling does not pay at FX-rack distance.** Front-on, the
skirt hides behind the cap and 18 flutes cost geometry for a silhouette nobody can resolve. It
pays where the skirt is actually seen -- the console pan row, looked down on from a seat at the
desk -- and it will pay in VR. Before authoring the next part, decide what distance it is read
from and spend the triangles there; 1088 tris is on the heavy side for something there are a
hundred of, and most of them are in the chamfers, which do pay.

Done since: the fader cap, and the tape reel flange.

The fader cap confirmed the rule -- its scooped silhouette reads at ordinary desk distance
where the knob's knurling did not. The reel went further and found the better question: not
"how detailed should this part be" but "which half of it is the same in every session". The
flange is; the tape pack is not, and splitting them that way turned a cosmetic pass into a
readout the transport did not have.

Done since: the jack socket. The plug shells were already made properly during the cable work
and did not need redoing -- the socket was the half that was letting them down.

Done since: the 2U rack faceplate, which was filed as "rack ears" and was the wrong unit of
work -- the ears are not a separate part, they are the ends of the panel with holes in them.
Asking "which half does not depend on the session" gave the right answer again: a rack is as
tall as the session has plugins, but a 2U panel is 19 inches by 2U in every session there has
ever been.

That exhausts the parts worth authoring for now. The remaining geometry is either procedural
by nature (the console, the rack frame, the timeline) or furniture that nobody looks at. The
meter bridge arm is the one leftover, and it is two posts and a shelf because that is what it
should be.

Still outstanding from before any of this: the mobile renderer pass (3782 tris per reel is
fine on desktop and worth re-measuring on a standalone headset), audio, consuming
GetProjectStructure, guest write round-tripping, and the participant roster.

## Audio

Done. `core/audio/foley.gd` synthesises five sounds; see architecture.md for the shape of it.

Two findings worth keeping:

**The mix was never the gap.** "The studio is silent" had been sitting in this list for a while,
and the obvious reading of it -- play the audio -- is wrong. Reaper is already making that sound
through the monitors in the same room, and a second copy a few milliseconds late is a comb
filter. The gap was the *gear*: a desk you can touch that makes no noise when you touch it.
Worth remembering the next time something on this list is phrased as an absence; the absence and
the fix are not always the same thing.

**`tools/verify.sh` could pass over a build that did not build.** A broken `knob.gd` printed
`499 checks, 0 failed` -- a GDScript that fails to parse does not throw, it simply is not there,
so `Knob.new()` returned null, every check that would have touched a knob never executed, and
the count dropped by seventeen while the summary stayed green. Fixed: verify now greps its own
output for `SCRIPT ERROR` and fails the run. This had been true for the whole project and would
have been true for every future tick.

## GetProjectStructure

Done. Colour, folder structure and send destination indices now come off the bridge on an
eight-second poll; see architecture.md.

Three findings:

**A level-change rule cuts a bus off from its own children.** The obvious way to draw folder
breaks is "where the nesting level changes", and it is wrong, because a folder's parent sits at
the *outer* level -- that is what makes it the parent. It put the VOX bus in with the guitars.
The rule that works is: break where a track opens a folder, or where the level drops.

**The stand-in project was lying about Reaper's data model.** It had folders with `Kick` as the
parent, which is legal and is not what a session looks like -- Reaper folders are parent-first
and the parent is the submix bus. Reordered with `DRUMS` and `VOX` buses at the head of their
groups. Worth watching for generally: the offline project is the only session anyone can open
without Reaper running, so anything it models incorrectly is what the feature gets designed
against.

**Two tests were pinned to incidental demo numbers**, not to what they meant -- a literal track
count of 12, and "track 1 has items" where track 1 is now a bus that correctly has none. Both
now assert the intent (guest count *equals host count*; the arrangement is non-empty across the
project). A test that breaks when the fixture changes shape was testing the fixture.

## Mobile / drawing budget

Measured, and the measurement overturned this list's own framing. See architecture.md.

**This entry was wrong about what the problem was.** It said "re-measure 3782 tris/reel, ~100
knobs at 1088" -- a triangle budget. Triangles were never the issue: 203k at 90 tracks is
nothing. Draw calls were, at 3,370, and the single biggest contributor was the VU meters at 37%
of the whole studio. A vertex problem and a draw-call problem have opposite fixes, so a guess
here would have cost a tick and fixed nothing.

**Two of the three performance monitors I reached for were wrong by orders of magnitude** --
`Performance.TIME_PROCESS` by 100x, `Engine.get_frames_per_second()` by enough to be useless on
a short sample. Both now deleted from the tool. If a number in a measuring tool is wrong it is
worse than absent, because it is the one that gets acted on.

**A MultiMesh cannot be tested headless.** Its buffer lives in the rendering server and the
headless one is a stub that accepts writes and returns black. Any future widget converted this
way has to lift its decision into a pure function first, or it silently stops being covered.

**The budget tool was measuring one camera angle, and that angle was hiding more than half the
scene.** The default framing fits the console to the viewport, so at 90 tracks the desk runs off
both edges and most of it is culled. The numbers reported in the previous entry were flattering
by **2.3x** -- the real worst case was 4,911 draw calls, not 2,132. `tools/budget.sh` now sweeps
two poses and `wide` is the one to read. A benchmark whose framing discards the workload is not
measuring the workload.

**Buttons are now banked too.** `MeshBank` is the general form of the meter's one-off: claim a
slot, get a transform and a colour back, one draw call for the lot. Console meshes 1,032 -> 492;
wide-pose draw calls at 90 tracks 4,911 -> 3,295. The bank is optional -- a `PanelButton` with no
bank builds its own two meshes -- so nothing outside a console surface had to change.

**The plate, the colour chip and the fader slot are banked too.** 2,492 draw calls at 90 tracks
wide, from 3,295; the console itself is 222 meshes, from 1,032 three ticks ago.

**Two things the draw-call number could not have told me**, both caught by looking:

- `MeshBank.parts` had never honoured per-instance colour at all. A `StandardMaterial3D` ignores
  `COLOR` unless `vertex_color_use_as_albedo` is set, and it was not. This was invisible for a
  whole tick because the only caller claimed everything `Color.WHITE`, so the bug and the
  intended result were the same picture. The moment something actually needed a tint it would
  have drawn 90 chips in one shade.
- **Driving a colour chip like a lamp destroys the thing it is for.** At the lamp's 2.4 gain
  every pastel track colour clipped to the same pale wash, which is the exact failure the chip
  exists to prevent. Chips now scale by the headroom available, so hue is preserved exactly.
  A screenshot A/B found this in seconds; no number in the budget tool would ever have mentioned
  it. Performance work needs a picture as well as a measurement.

**The patchbay's jacks are banked, and the result forced a correction to how this whole effort
has been measured.** Banking 180 jacks moved the draw-call count *not at all*, while objects
fell 4,919 -> 3,845 and primitives halved. That looked like a broken counter, so I stopped and
microbenchmarked it rather than guessing: 400 boxes, loose with one shared material, loose with
a material each, and as one MultiMesh.

    loose, one shared material     draws 7       objects 1100
    loose, a material each         draws 1100    objects 1100
    one MultiMesh                  draws 3       objects 3

Both counters are honest; they measure different things. `draws` is driven by the number of
DISTINCT MATERIALS in frame, because the renderer batches whatever shares one. `objects` is
per-instance submission and only instancing removes it. The jacks all wear the same two
finishes, so they were already batching -- banking them bought CPU submission work and no GPU
draw calls. Worth having on a standalone headset, where the CPU is as likely to be the wall,
but it is not the same win as the console's.

This also explains the console results in hindsight: what paid there was replacing per-colour
`Materials.led()` instances with one unshaded bank, i.e. collapsing MATERIALS, not objects.
And it says where the remaining draw calls are -- every `Label3D` carries its own glyph
texture, so 517 labels is close to 517 unbatchable draw calls.

**The timeline's items are banked, and scrolling no longer rebuilds the surface.** Two things in
one because they are the same code path. Draw calls 1,757 -> 727 at 90 tracks wide -- the
largest single step of the whole effort, and it is the MATERIAL collapse doing it rather than
the object collapse: every item block and lane chip carried its own track colour, so each was
its own material and its own unbatchable call.

The scroll fix is the one worth keeping for its own sake. `mark_dirty()` on a view change meant
a full rebuild per frame for the length of a drag; the split that fixes it is between what the
window decides (items, ruler numbers) and what the project decides (lanes, labels, flags). The
items bank is sized to every item in the project and drawn down with `show_first(n)`, because
capacity is a fact about the project and visibility is a fact about the window.

**A per-instance colour is linear and `albedo_color` is sRGB**, which made the blocks come back
pale and flat. No counter would ever have said so -- it was an A/B screenshot, again. That is
twice now that a draw-call win has quietly changed how something looks, so the A/B is not
optional on this kind of work.

I also nearly shipped a regression test that did not test anything: reverting the scroll fix
left it green, because `mark_dirty()` only sets a flag and the test never ran the frame that
acts on it. The mutation check is what found that, not the test passing.

**A rack unit could only reach a plugin's first eight parameters**, and said nothing about the
rest. The class doc had claimed a page control since it was written; there was never one. Same
silent failure the console's BankSelector exists to prevent -- gear that looks complete for a
simpler thing than the one actually loaded -- so it now works the same way, down to deferring
a page change made while a knob is held.

**It was invisible because the stand-in made it invisible.** Every FX in the offline project
had exactly four parameters, so the overflow case never arose in the only session anyone can
open without Reaper running. A real ReaEQ is four bands of four; a real ReaComp is a dozen and
more. The stand-in now has realistic counts. This is the SECOND time the stand-in has designed
a problem out of existence by being tidier than reality -- the first was folder structure --
which makes it a pattern rather than an accident: **the stand-in has to be at least as awkward
as the thing it stands in for.**

**`verify.sh` now times out.** Its own comment already described the hang -- a parse error in
run_tests.gd leaves the scene with no script, so nothing calls quit() and the run sits forever
looking like a slow suite -- but nothing bounded it. I lost two stretches to exactly that
today, both times assuming the suite had got slow. It is under a second; sixty is the limit,
and on a timeout it says what the cause almost certainly is.

**The reels turned at a flat 2.4 rad/s and both at the same one.** The class header had claimed
a rate "proportional to playback" since the deck was written -- second doc-ahead-of-code gap in
two ticks, after the rack's page control. Now derived: tape crosses the head at one speed, so a
reel's angular rate is that speed over the radius it is paying out at, and the takeup therefore
starts fast and slows all song while the supply does the reverse. That difference IS the thing
you read peripherally; two reels on one rate are two wheels on an axle.

Driving it from position rather than from `playing` is what makes a scrub and a rewind work, and
it costs nothing: the position is the only number that cannot disagree with the DAW. A stop is
the position stopping.

**The speed has to be smoothed, and not for looks.** Position arrives over the wire at the
link's rate, not the frame rate, so at 60fps most frames see the same number as the one before
and read as a dead stop. Unsmoothed the reels stutter to a halt twenty times a second, which
looks like a fault -- and a peripheral display that looks broken is worse than an absent one.
The test for this asserts on the SPREAD of per-frame rotation under a deliberately polled
position, because that is what an eye picks up and what a raw reading destroys.

**And the screenshot found two things no test could.** The left reel was blown to flat white --
`brushed_metal` at 0.34 roughness is right for a fader cap, which is small and angled, and wrong
for a 17cm disc angled into a practical, which puts the whole face near the mirror angle at
once. That is the failure `master_plate` already documents, at a scale that hid a whole feature.
A reel flange has a real reason to be blasted rather than brushed, so it now has its own
material. And with the glare gone it was clear the TAPE PACK had never been visible either: at
0.21 albedo, in the recess the flange shadows, the windows read as holes with nothing behind
them. Lightened, and the supply/takeup asymmetry the pack exists to show is legible for the
first time since it was built.

Third tick running where an A/B screenshot caught something every counter and every test was
happy with. It is not a nice-to-have on this project; it is the only instrument that measures
the thing the project is actually for.

**Swept every doc comment for claims the code does not honour**, because two ticks running had
found one by accident and twice is a pattern. 312 doc lines make a falsifiable claim; the sweep
narrowed to the absolute ones -- always, never, cannot, must -- and found a third:

`_follow()`, the timeline's auto-page, still called `mark_dirty()`. The manual scroll path was
fixed last tick and has a regression test; this is the SAME scroll arriving by itself, and it
is the worse of the two. A drag is something a person is doing on purpose and watching. This
fires unattended, once per window, for the whole of a rolling take, tearing down and recreating
every lane label while the transport runs. **Fixing one caller and leaving the other is how a
bug survives its own fix** -- and the test that was written for the drag could not see it,
because it tested the caller rather than the rule.

It only bites when zoomed in: the timeline opens showing the whole project, and a playhead
cannot run off a window that contains everything. That is why it lasted.

**Three invariants are now enforced on the source instead of asserted in a header.**
presentation.gd says "A surface... must never ask which mode it is in"; surface.gd says the
same for who is looking and for which process is the host. All three were still true. None was
checked -- and an invariant that holds today and is guarded by a comment is one reasonable-
looking `if` away from not holding, written by someone not editing the file the rule lives in.
There is now a scan over every .gd under hardware/ for the six ways out (`Presentation.`,
`Medium.`, `XRServer`, `Session.`, `is_authority`, `multiplayer.`), which prints the offending
file and line. It carries its own self-check: it is pointed at core/presentation, the layer that
IS allowed to know, and must light up there -- a scan that cannot fail is decoration.

The files come from DirAccess rather than a list, because a list is something a new file gets
left out of, and a file left out is exempt from every rule without anyone deciding that.

The general lesson, now three for three: **prose makes claims and only the suite holds anyone
to them.** Worth re-running the sweep whenever a header gets written.

**The room was one wall, and the stated reason for that did not apply to this renderer.**
`_build_room` said a fully enclosed room "makes the desk harder to read in a screenshot, because
every light then bounces into the lens". True with global illumination; this environment is
AMBIENT_SOURCE_COLOR with no SDFGI, no VoxelGI and no SSIL, so ambient is a flat constant and
walls bounce nothing. Three walls now, and the wide shot goes from gear parked in front of a
flat to a corner you are standing in. Measured rather than assumed: 2 draw calls, 2 objects,
0.01ms. The ceiling stays off and THAT reason does survive -- the key is a DirectionalLight3D
with shadows on, so a ceiling does not soften the room, it switches the key off.

Fourth doc-vs-code finding in three ticks, and a new shape: not a missing mechanism this time
but a REASON that was sound somewhere else. Worth checking a justification against this build,
not just against general graphics knowledge.

**The budget tool was measuring the monitor.** Every pose came back at exactly 8.33ms -- the
same number whether the camera faced ninety channel strips or a blank wall, and exactly 1/120s.
That is vsync: the engine sleeps to the refresh and reports the presentation interval. A
measuring instrument that returns the same answer regardless of what it is pointed at is not
conservative, it is broken, and it is worse than having none because its numbers look plausible
enough to write down. `tools/shot.sh` already killed vsync through override.cfg for its own
reasons; the budget wanted it more and never did it. With it off the poses separate again and
land at 1.00ms / 1.37ms worst, consistent with the figures already recorded here -- so the
history was sound and today's run was the anomaly. The suspicious part was never the value, it
was that three different poses agreed to the second decimal.

**A part-filled rack bay was a hole you could see the far wall through.** The frame is built
to the bay's full capacity, because that is what makes two bays line up, and six plugins in a
twelve-U bay left six rows with nothing in them. Blanking panels now, which is what a real rack
has in them and the only honest way to draw the gap -- banked, because every blank is the same
object in a different place.

Same failure family as the bank selector and the rack's page control: the gear misrepresenting
the project in the direction of looking simpler than it is. That is three instances now, and
the tell is always the same -- something absent with nothing saying it is absent.

Also the fifth doc-vs-code gap, and the most embarrassing kind: the class header said "A rack
fills bottom-up" while an inline comment eleven lines below said "Filled from the top down".
**Two comments in one file contradicting each other, with the code agreeing with the lower
one.**

**Two things about the blanks' finish are worth keeping.** The first attempt reused the chassis
albedo with a rougher finish: dimmer in the inspector, BRIGHTER on screen, because roughness
spreads the practicals across the whole panel instead of into one highlight. The second halved
the albedo and changed almost nothing visible -- at which point it stopped being obvious that
albedo was the lever at all, so it was pushed to near-black as a deliberate overshoot to prove
it was. It is now a sixth of chassis, which looks absurd written down and is right on screen,
because the thing a blank is compared against is a faceplate that is mostly knobs, lettering
and the shadows between them.

**And the test caught itself lying.** The first version asserted counts and rows and carried a
comment claiming it would catch blanks placed in the wrong rows. Mutation said otherwise:
reversing the row range, so the blanks cover the gear and the hole stays at the bottom, left
every check green. Same disease as the four found in the source this week -- prose asserting
what the thing below it does not do -- this time in the suite that exists to catch it. Now
asserts WHERE: every blank below the lowest unit.

**The timeline and the patchbay were showing a bank and calling it the project.** Over a real
Reaper link the cache holds a window of tracks -- 64 of 90 -- and both surfaces drew whatever
was in it with nothing saying so. The console has had a bank control since it was written,
which is exactly why this lasted: a desk captioned "17-64 OF 90" standing beside an uncaptioned
timeline and an uncaptioned patchbay makes the other two look right.

Fourth and fifth instance of the same pattern. The phrase lives on MixState now, not in three
surfaces, because three things saying the same fact in three wordings is three facts to anyone
reading the room. The test is written over a LIST of surfaces so a fourth one is held to the
rule the day it is added, rather than joining the two that quietly were not.

**Then the screenshot caught the caption lying, and the test did not.** The first version keyed
off `has_more_banks()`, which asks whether the PROJECT is bigger than a bank -- a different
question from whether this cache is truncated, and not always the same answer. The offline
stand-in at 90 tracks caches all 90 while bank_size is still 64, so the caption read "TRACKS
1-64 OF 90" over ninety drawn lanes. The test passed, because it only checked that "90"
appeared somewhere, and it did -- in the wrong sentence.

A caption that disagrees with the thing it is captioning is worse than no caption, since being
believed about what is missing is its entire job. It is measured from the keys actually in the
cache now, and the test asserts the sentence rather than the number.

**A test that looks for a substring is a test that will accept a lie containing it.** That is
the second time this week a green check was hiding the thing it named -- the rack blanks were
the first -- and both times mutation or a screenshot found it, never the suite on its own.

**Audited the suite for the weak-assertion shape** that had slipped twice, and the worst
instance was in the test written while diagnosing it. The commit for that tick claimed "the
assertion is on the sentence rather than on the number" -- true of the direct checks, false of
the surface checks, which still swept every label for "90" and counted a hit as proof. The
sentence that broke it, "TRACKS 1-64 OF 90" over ninety lanes, contains "90" in passing.

**Then the mutation found two more layers, neither visible by reading.**

*The expectation called the function under test.* The surface checks compared each label
against `DAW.state.bank_caption()`, so a mutation that changed the caption changed the
expectation too and both sides moved together. It passed. An expectation has to be written
independently or it is not an expectation -- it is a restatement.

*The fixture could not tell the formulas apart.* The cache held exactly 64 of a 64 bank, where
"count what is held" and "assume a full bank" return the same characters. The fixture holds 40
of 64 now, which is also the more honest shape: a bank still filling, or a backend that capped
lower than it was asked.

**And the console was still computing its own range from bank_size** while the other two read
what is held -- the exact drift the shared `bank_caption()` was introduced to prevent, left
behind in the surface that had been right the longest. BankSelector takes `shown_count` now. A
caption contradicted by the faders in front of it is worth less than none.

The through-line for the week: **a green check is evidence about the check, not about the
code.** Three of this week's real bugs were sitting behind passing tests, and in every case it
was a mutation or a screenshot that found them.

### Still open

**Lettering is culled once it is too small to read**, which was the largest remaining cost.
An ablation -- hide every Label3D, re-read the counters -- put the 517 labels at 735 of 2,492
draw calls and 0.70ms of a 1.82ms frame: 30% of the drawing, 38% of the time, for text.

The trade turned out to be free, which is why it is worth recording. Label cost rises as you
stand back and more of the room enters frame; label VALUE falls as you stand back, and falls
faster -- a console strip name is already under five pixels of cap height at 1.2m. So culling
lettering below three pixels of cap removes the cost exactly where the text had stopped saying
anything. Measured at 1.82 -> 1.38ms at 90 tracks wide, with nothing visibly different at a
working distance (checked at 0.8m and 1.8m, not assumed).

Two things worth keeping from how this was done. The ABLATION came first: hiding the labels
and re-measuring is what turned "labels are probably the problem" into a number, and it cost
one flag. And the test walks the whole built studio asserting every label has a range, rather
than testing the helper -- a helper that is correct and uncalled is the actual failure mode
here. Verified by deleting one call site and watching it fail by name.
- Guest write round-tripping of provisional values; participant roster on a guest.
- Draw calls are at 727 at 90 tracks wide, from 7,600. This is probably the point to stop and
  put the effort back into the gear itself; the remaining items are small and the measurement
  tooling is now good enough to catch a regression if one lands.

### Tick L -- four plugs in one hole

Swung back to the gear after three audit ticks and photographed the console close up. The desk
itself reads well. The bay above it did not: four cables fanned down to what turned out to be
a single input jack. One jack takes one plug, and the bay had been drawing four in one bore
since the first cable landed.

Worth noting HOW it was found. Not by the suite -- 838 checks and none of them had ever asked
where a cable ENDS, only that the right number of cables existed. Not by reading the code
either; `_draw_cables` reads perfectly sensibly, and `patch_cable.gd`'s own class note cites
"which return has four things landing on it" as a thing the bay is good at showing. It was
found by cropping a screenshot to 260% and looking at it. That is now three bugs this week
whose only detector was a photograph.

The fix is a **mult** -- real patchbay hardware, a strip of jacks wired in parallel, hung
under the bay on two straps. Sources plug into it, one trunk cable leaves for the return. It
is deliberately the dullest object on the bridge. Multed returns pack left to right in a row
rather than hanging under their own column, which would collide the moment two neighbouring
returns were both multed; a mult is a bussed strip and nothing requires it to live beneath the
jack it feeds. The trunk cable says that.

Two placement mistakes, both caught by the second and third screenshots rather than reasoned
out: the first mult sat halfway through the meter-bridge crossbar, and the first version had no
straps, so it floated under the bay reading as a UI panel that happened to be in the scene.

The test is the part worth keeping. `_test_one_jack_takes_one_plug` does not know what a mult
is. It collects both ends of every cable in the bay and asserts no two are closer than a 1/4"
sleeve is wide, then separately asserts the fan-in was not simply dropped to achieve that.
Written that way it would catch any future way of putting two plugs in one hole, including
ones nobody has thought of. Mutation-checked twice: routing the sources straight at the input
again fails it at "0.0mm apart", and never building a mult fails it by name.

846 checks, 0 failed.

### Tick M -- the last 180 loose objects

Knobs and fader caps, banked. The prediction made when this went on the backlog -- "expect an
`objects` win and little on `draws`" -- was right, and worth recording because it was made
from the batching table rather than from a measurement:

| 90 tracks, wide | draws | objects | frame ms |
|---|---|---|---|
| before | 820 | 2,293 | 1.28 |
| after | 830 | **1,225** | **0.95** |

`draws` went UP by ten. Two new banks of a two-surface part add materials to the frame, and
the 180 objects they replaced already shared materials with each other, so there was no
`draws` win available. Objects nearly halved; the frame dropped a quarter. The console's loose
mesh count went 222 -> 42 at 90 tracks.

The argument that had kept these loose was in `mesh_bank.gd`'s own class note: a bank is
filled once, and these move. That was wrong -- a transform is per-instance, and `move_slot`
has existed since the bank was written, with a doc comment that says "a fader cap slides and a
knob turns". The note has been corrected. A stale justification in a docstring is the same
failure as a stale doc elsewhere in this backlog, and it is worse here because it reads as a
decision rather than as a description.

One thing the design had to concede: the fader cap stays a node even when banked, an empty
one, because the slide emitter parents to it so the sound comes from where the cap is. A bank
slot is a row in a buffer with nowhere to hang a speaker.

Two instruments, because neither alone is enough. A **pixel diff** of the console before
against after: identical apart from a tape reel that had turned between captures, which is
what proves banked and loose land at the same place and the same angle -- the test cannot show
that, because it compares the banked slot against the loose node through the same chain. And
**`_test_a_banked_control_still_moves`**, which mounts one banked and one loose control under
a tilted, offset, rotated parent -- a test at the origin agrees with every wrong composition
-- and then separately asserts the cap crossed its full 100mm and the knob its full 270
degrees, because two frozen controls agree with each other perfectly. Mutation-checked by
deleting both `move_slot` calls: seven checks fail, and informatively ("9.00mm", "50.80mm",
"100.40mm" -- the cap frozen at build position).

Rack knobs left loose on purpose. They are created lazily as parameters arrive and as pages
change, i.e. after the surface has committed, so banking them means sizing for the worst case
and hiding unused slots. The rack's mesh count does not grow with the session, so this buys
little; recorded as a decision rather than an oversight.

858 checks, 0 failed.

### Tick N -- the rack, which had never been looked at closely

The surface carrying the most geometry in the room (65,200 triangles, more than everything
else combined) and the one I had photographed least. Shot it square on at 1200x1400.

**A finding that measurement killed.** My first reaction to the photograph was that the rack
is far too dark -- 48 knobs modelled and barely legible, off at the side away from the key
light. That is a plausible story and it is wrong: mean luminance of a rack faceplate is 47
against the console panel's 54, a 13% difference. The rack looked dark because it was
photographed alone against a dark wall, and because the camera was further from it. Dropped,
and recorded here because the next person to look at that photograph will have the same
reaction. One `magick -format %[fx:mean]` settled it in a second.

**The real finding, at 300%.** The faceplate layout was wrong in a way that is invisible at
rack-wide zoom. The knob row sat at a quarter of the plate height below centre, which put 35mm
of empty metal between the title and the knobs and left 3mm of clearance under the captions.
Dead space in the MIDDLE of a panel is the one place real hardware never leaves it, and the
labels were pressed against the lower edge. Raised the row so the knob-and-caption group is
centred in the area the header leaves -- a bottom margin instead of a hole -- and added the
silkscreened rule under the title that every processor with a title bar has. Without the rule
the header and the controls are two things floating on the same slab.

The test is careful about what it claims. It does NOT pin where the row looks best; that was
settled by a photograph, as it has to be. It pins the BRACKET the row has to stay inside,
which is geometry rather than taste: raise it and the knobs grow through the rule, drop it and
the captions walk off the plate. Mutation-checked at both ends -- +0.010 fails 44 checks on
"keeps knob under the rule", -0.030 fails 44 on "keeps caption on the plate (-4.7mm from the
edge)". The old value would have passed, which is correct: it was ugly, not broken, and a test
that failed it would be a test asserting my taste.

Knobs are now named so a failure says `Knob3` rather than `@StaticBody3D@4327`. Third time
this week an unnamed node made a failure message useless.

971 checks, 0 failed.

### Tick O -- the deck had two reels and nothing between them

Shot the tape machine close up for the first time. The reels are good -- the packs already
shrink and grow at the right rate and the two turn at their own speeds. But there was no tape.
Two wheels on a slab, with a floating counter and three small buttons. Everything that makes a
deck legible as a deck lives in the gap between the reels, and the gap was empty.

Built the path: the ribbon, two guides, a three-head block, a capstan and a pinch roller. The
point of the ribbon is not that it is there -- it is that it comes off the pack on a TANGENT,
so the angle it leaves at swings round as the reel empties. Measured, that is 33 degrees of
swing from a full supply to an empty one. A run drawn to a fixed point on the flange would
look identical in a still photograph and dead in motion.

Three things the photographs corrected, none of which I would have got from the code:

1. **The guides were inside the reels.** At the first PATH_Y the guide posts sat 2mm inside
   the flange circle, so both runs vanished into the reels and read as sticks resting on them.
   Moved the path down and the guides in; the buttons and the tempo readout moved down with
   it.
2. **The run must stop at the FLANGE RIM, not at the pack.** The pack is drawn behind the
   flange and is only visible through the windows, so a run drawn all the way to its tangent
   point ends in the middle of a solid disc. Stopping at the rim reads as tape going in
   behind it, and the angle still comes from the pack, which is the part that has to stay
   true.
3. **The tape was the pack's colour and came back looking like a wooden batten.** A pack is
   lit through a window at the bottom of a recess and needs lifting; a run is out in the open
   and does not. Oxide is nearly black and on the path it should look it.

**The mutation that mattered.** The static geometry tests -- tangent on the circle, square to
the line, run stops on the rim, angle swings one way -- all passed while the takeup reel used
the WRONG tangent. They only ever exercised the supply. Flipping that sign is the single most
likely mistake in this feature and the suite was blind to it. Fixed by asserting the thing the
sign actually decides: with equal packs the two reels are mirror images, so the tape must
leave one and arrive at the other at mirrored points. The wrong sign now fails by 20.3mm of
height and 11.3mm of offset.

Also worth recording: the first version of the swing check failed, and the deck was right. The
run crosses due-west partway through the reel, so the raw angles run 163, 173, 180, -174,
which a plain subtraction reads as the tape snapping back through half a turn. Stepped with
`angle_difference` instead. Second time this week a test was wrong about the thing it was
measuring rather than about the code.

999 checks, 0 failed.

### Tick P -- the wide shot, which is the only one that shows what is missing

Four close reviews in a row, then the framing none of them could substitute for: the whole
room at 2.6m. Two findings, and both are of a kind a close-up cannot produce, because both are
about what is NOT in the frame when you stand close.

**A regression I shipped last tick.** There was a small object floating against the right-hand
wall, a metre from anything. It is the tape deck's grab tab. A tab is placed from its
surface's content box ONCE, when the surface says it has rebuilt -- and the tape runs I added
in tick O are unit-length boxes that a transform shrinks to size, with the two outer ones left
unlaid until the first frame. `rebuilt` fires before that frame. So the handle measured a deck
with two one-metre planks lying across it and clipped itself to the edge of that, 413mm out.
Fixed by laying the runs at build time. It had been there for one tick, through a full suite
run, a close-up of the deck and a mutation campaign, because it is outside every close-up.

The test for it is the general statement rather than the specific bug: every grab tab in the
built studio must sit just outside its own surface's content box and at the middle of it. It
does not know what a tape run is. Getting it to BITE took a second try, and the first failure
is the more useful half: the test built the studio and measured without stepping a frame, so
it compared the handle against the same wrong box the handle had been placed from, and passed
the bug cleanly. A test that reads its expectation from the same stale state as the code is
the same mistake as an expectation that calls the function under test. Stepping one frame
first is what makes it an expectation. Mutation now fails at "413.0mm out".

**The timeline was hanging in the air.** The rack has a plinth, the deck a trolley, the bay a
bridge, the console its own carcass -- and then a metre of lit panel at head height with
nothing holding it. Invisible in a close-up of the timeline, where you are looking at the
lanes. Obvious the moment the room is in frame: it is the one object in the room that is
software. Given two legs, two feet and a crossbar, deliberately the same vocabulary as the
patchbay bridge rather than a new idea -- a room furnished out of three kinds of part looks
like a room, and one furnished out of six looks like a kit.

No test for the stand, on purpose. Its correctness is "does it read as supported", which only
a photograph answers; inventing an assertion for it would be asserting my taste, the same trap
noted in tick N. What IS pinned is the timeline's height and the stand's height as one
constant pair, so moving the panel cannot leave the stand behind.

1020 checks, 0 failed.

## Tick Q -- the room had no wiring in it

**The patchbay was wired to nothing.** The bay draws a cable for every send in the session, and
for sixteen ticks those were the only cables in the room. The console, the rack and the deck
stood in the same room as the bay and had no physical relationship to it: the bay's jacks were
labelled with the names of machines they were visibly not attached to. A patchbay wired to
nothing is a prop of a patchbay.

So, three looms -- console, rack and deck, each to its own landing across the back of the bay.
They are the normalling: the permanent run that makes a jack mean a machine, with the per-send
patches then laid over the top. That is a narrower claim than the patch cables make, and the
code says so: nothing in the DAW state decides where a loom goes, and the only thing a loom
asserts is that this machine is wired to the bay, which is true of every machine here.

**The sweep is now shared.** A loom and a patch cable disagree about everything except the hard
part -- the parallel-transport frame -- so that moved to `hardware/cable_sweep.gd` with the
commentary, and `PatchCable._build_jacket` is eight lines calling it.

**Three measurements, in the order they were taken.** The first render showed three black
vertical lines and nothing else, which is what a loom looks like when the route is wrong, the
colour is wrong and the shape is wrong, all at once.

  * A headless probe of the spines, because the photograph cannot read a number. It said the
    floor runs dipped 81mm THROUGH the floor and climbed 108mm above the gland they were
    arriving at. Neither was visible from any angle I had shot.
  * An ablation on the parameterisation with everything else held still: uniform Catmull-Rom
    81mm / 108mm, centripetal 39mm / 29mm. So centripetal is worth having and is half a fix,
    and the comment in `cable_sweep.gd` now says that instead of the "under a millimetre" I had
    written from memory before measuring. **The first draft of that comment was wrong and the
    test caught it**, which is the right way round.
  * The remaining 39mm is not a spline artefact. It is where a slack cable genuinely wants to
    go, and what stops it is the floor -- so `CableSweep.rest_on` lays a spine on a level it
    cannot pass through, with a C1 parabola at the contact so the touchdown is a curve rather
    than the corner a clamp would leave.

**The console's loom is not a floor run.** It stands directly under the bay. A trunk route down
to the floor and back up would be a longer cable than the one that fits, so it hangs, and its
via is a clearance point rather than a floor point -- which is the whole reason the via became
one waypoint with two readings instead of two fields.

**What the test caught that I had already "fixed".** All three looms arrived three centimetres
INSIDE the meter-bridge crossbar, because the bay's bottom edge is exactly where that bar runs
and the entry was 24mm up from the bottom edge. Raising it to 68mm fixed the rack and the deck.
The console still clipped: it was dropping first and clearing the bar afterwards, and the curve
sagged through the top of the bar fifteen millimetres past the gland. Its via now takes it BACK
before it goes down. Both of those are corrections to code I had looked at a render of and
called done.

Four mutations, four catches, each by the assertion that claims to own it: uniform knots ->
"arrives at the bay instead of over it (110.4mm above)"; no floor contact -> "does not go
through the floor (39.7mm under)"; entry back at the bottom edge -> three looms inside the
bridge; via ignored -> the console through the floor.

The bridge is now `BRIDGE_POS` / `BRIDGE_SIZE` so the test and the furniture read the same
numbers, and moving the bar moves the test with it.

Not done, deliberately: cable flags. Real looms carry a label at each end, and at two metres in
a dark room it would be four unreadable pixels and a Label3D per loom.

1053 checks, 0 failed.

## Tick R -- the room was lit by light sources that do not exist

Straight on from tick Q: the looms were in, and the rack's run was invisible because that
corner of the room had no light reaching it.

**Measured first, because the last time I called something "too dark" I was wrong.** In tick N
the rack's faceplate read 46.9 against the console's 54.1 in a close-up -- 13%, no case to
answer, hypothesis dropped. This is a different measurement on the wide shot and it is not
close: rack face 13.8 against console 22.1, and the floor at the rack's foot 9.1 against 29.5
on the lit side. A factor of two to three.

**And then the actual defect, which was not the darkness.** The room was lit by two OmniLights
floating in mid-air with no fixture anywhere near them. That is the same shape as the patchbay
wired to nothing, one layer up: the light is real, the thing it comes out of does not exist,
and nothing says so. `PRACTICALS` is now one table read twice -- by the environment to make
the lights and by the furniture to make the stands -- and the stands are furniture, so an AR
participant keeps the light on the virtual gear without a virtual lamp appearing in his room.

Floor lamps and not pendants, and that is forced rather than chosen: this room has three walls
and no ceiling, so a hanging fixture would hang from open sky above the wall line.

**Three passes, each one a measurement correcting the one before.**

  1. Stands at the old light positions. Rack face 13.8 -> 21.4, floor at its foot 9.1 -> 19.6,
     everything up 55-115%. But the RATIO rack-to-console went 0.63 -> 0.59: the gap I set out
     to close had not closed, the whole picture had simply got brighter. Worth saying plainly,
     because "everything improved" was true and was not the thing I was after.
  2. The reason: the old positions were abstract fill, chosen when nothing was drawn there.
     Two of the three lamps stood over the empty half of the room, and the third was nearly
     edge-on to the rack's faceplate -- the rack is turned 38 degrees, so a lamp to its left
     rakes its side. Moved to where someone would actually stand a lamp, including one beside
     the desk on the rack's face normal: rack face 28.6, ratio 0.74.
  3. That lit the empty room too: bare floor 37.0 against the console's 38.7. A floor lamp is
     a pool, not a sun, so `omni_range` came down from 6.5m to 3.6m and ambient from 0.58 to
     0.46. Final: rack face 24.3, floor at its foot 12.9, console 35.3, bare floor 32.5.

Against the start: rack face +76%, floor at its foot +41%, console +60%, and the gear is no
longer the dimmest thing in a frame of its own room.

The test pins the pairing, not the brightness. Brightness is taste and belongs in a photograph;
"a light with no fixture" is a fact. Three mutations, three catches: a fourth practical with no
stand -> "3 of 4"; a shade hung 300mm above its lamp -> three failures; a stand 250mm to one
side of its lamp -> three failures. The second one matters because a count check alone would
pass a fixture that renders in the wrong place.

1070 checks, 0 failed.

## Tick S -- the budget figure in the docs was five ticks stale

Two ticks of scenery went in without re-measuring anything, and the architecture doc still
quoted 830 draws / 1,225 objects from tick K as if it were current. So: measure.

**90 tracks wide, now: 964 draws, 1,359 objects, 0.99ms.** Against 830/1,225 that looks like a
sixteen percent regression and it is not one -- the baseline was simply old. Five ticks of
additions sit between them (the mult, the rack rule, the tape path, the timeline stand, then
the looms and lamps), and adding things costs something.

**The useful number needed a real baseline, so I built one.** `git worktree` at the pre-tick-Q
commit, same tool, same two poses: 899 draws / 1,294 objects before, 964 / 1,359 after. Three
looms and three lamp stands for +65 draws and +65 objects, with frame time flat (1.03 -> 0.99,
which is noise). That is a number I can defend; "+134 against a figure from last week" is not.

**Twelve of the sixty-five were a mistake.** Every mesh on a loom has `cast_shadow` off except
the strain-relief collars, which I had simply not set -- so the only part of a cable in the
shadow map was the 30mm collar at each end, six of them, two passes each. Predicted from the
counter before changing anything, then confirmed: 976 -> 964.

**One thing measured and then NOT done.** The loom cores are swept at eight segments per span;
dropping to four saves 3,072 primitives at 90 tracks, which is 3.6% of the fitted pose. Left at
eight. The saving is small, the cost is faceting on the one curve anybody looks at -- where the
cable flattens into the floor -- and frame time did not move, so primitives are not what is
binding here. Writing down that the ablation was run and rejected is the point; otherwise it
gets re-run in three ticks' time.

The new test pins the SHAPE, not the count. A draw count belongs in a benchmark, not a unit
test. What a unit test can say is that the room's dressing costs the same at 64 tracks as at
13 -- three looms because three machines, not one per send. Two mutations: a loom count that
scales with the session -> "20 vs 29 meshes"; the collars casting again -> "18 casters, 12
lamp parts".

1073 checks, 0 failed.

## Plugin tablets — follow-ups (2026-10-08)
- Mark a rack unit whose plugin is out on a tablet (dimmed faceplate, or a "ON TABLET" tag)?
- Patchbay: draw sidechain (key) sends as a distinct cable colour/style.
- Offline stand-in shows preset "—" until a preset is stepped; the built-in engine's wet/dry is state-only (not heard).
- Tablets stand on the floor; placing one on a table/desk top was not done — wanted?
- Tested against Neural DSP (Gojira X, Tim Henson X, Mantra) in the rig: tools/probe/plugin_tablet_live.tscn,
  85 checks. Still open from that:
  - The RACK still only reaches a plugin's first 32 parameters, and rack knobs don't follow values changed
    in Reaper (no signal for param values; the tablet polls its visible knobs, the rack doesn't).
  - On/off parameters ("Gate Active", "REV Active") are knobs on the tablet; switches would read better.
  - 140-210 controls is 15-30 pages; a section jump (scroll the page label through section names) would help.
  - The plugin's own presets step blind: the plugin doesn't tell Reaper the preset's name.
  - The first Wine plugin load can outlast the bridge's 4 s reply timeout (it still loads).
- The tablet's UI face (the plugin's own window, read off X and clicked through XSendEvent) is ON
  (2026-10-14; `PluginTablet.window_face = true`). The helper (native/plugin_view.c) does what Reaper does
  to dock a window: it reparents the plugin's top-level window into a holder window of its own, override-
  redirect and mapped at x=-30000, so it never shows on the desktop (verified live: `hyprctl clients` never
  listed the ReaEQ window). XAddToSaveSet restores the window if the helper dies; `q` puts it back on the
  root; `--in-place` turns the reparenting off. Open:
  - Checked live on ReaEQ only (rig); the Wine/yabridge Neural DSP plugins are not tried with the holder.
  - One probe run in three did not find the window ((0,0)); not yet explained.
  - 2026-10-14: the window flashed on the desktop between Reaper opening it and the helper's first frame
    request (seen on workspace 2 with Gojira; and for good if the user moved it by then). The helper now
    watches every 4 ms between commands and takes the window the moment it maps. The tablet also grows
    to 2.4x and walks the viewer up to it when the UI face is turned on.
  - Left button, drag and wheel only: no right-click menus, no keyboard (a plugin's text fields can't
    be typed into), and its popup menus open as separate windows that the tablet doesn't show.
  - Two copies of the same plugin on one track have the same window title; the tablet shows the first.
  - The helper is built on first use with `cc` into user://bin; without a compiler or X11 headers the UI
    button just doesn't appear.
- Webcam AR (asked 2026-10-08: "could we somehow simulate what this would look like in AR using my
  webcam?"). Plan: a `--webcam-ar` desktop launch that shows the webcam (`CameraServer`/`CameraFeed`, V4L2,
  /dev/video0) behind the scene and drops the venue's shell the way `XRBootstrap`'s passthrough does, so
  only the gear, the lattice and the zones float over the room. Fixed camera, not head-tracked; the
  virtual camera is lined up with the webcam once by hand. DROPPED for now (2026-10-09: "drop both of
  those for now"); not to be built unless asked again.

## Lattice cells bobbing in zero-g on the station

The station follow-up asked for the matrix "in true zero-g (its cells bobbing slowly)". The
cells belong to the lattice activity, which every venue shares, so a venue cannot move them
without a hook in the activity (e.g. a per-venue `drift` the lattice reads). Decide whether
activities should take a look from the venue they stand in before building it. DROPPED for now
(2026-10-09: "drop both of those for now"); not to be built unless asked again.

## Rig Roulette outside Tour: a standalone station (2026-10-11)

Rig Roulette (the Tour case's spillable-pedal rig minigame) asked for outside Tour too
(2026-10-11: "I want to be able to do rig roulette (with modifiable parameters) outside of tour.
just in general like i get some bois together and we just roll some shit"). Built as
`RigRouletteStation` (`hardware/rig_roulette/rig_roulette_station.gd`), a wall panel in the
control room, independent of any Tour run and of the built-in engine: works against whichever
`DAW.backend` is open.

- Host-only roll (`Studio._on_rig_roulette_roll_requested` gates on `Session.is_authority()`,
  same pattern as `choose_venue`/`_on_tour_case_struck`); guests can nudge the wheels on their
  own view but nothing reaches anyone until the host's own ROLL press.
- Fresh, unseeded random every roll — not the run's own seed, since this has nothing to do with
  a Tour run's own replay.
- Modifiable: pedal count (1-3), FX pool (CHARACTER/EVERYTHING against the built-in engine;
  against a live Reaper connection both wheel positions read "WHATEVER'S THERE", honestly, since
  a live plugin list carries no kind metadata to filter CHARACTER by), and track eligibility
  (open tracks only / any track).
- Key roll: unless LOCK KEY is lit, every roll also moves the whole song to a new key (a
  nonzero semitone shift, via the existing `DAW.transpose_item`, applied to every MIDI item on
  every track). Tempo was asked for alongside it (2026-10-11: "Key, bpm, like the video I
  sent") but the only tempo roll buildable now is cosmetic (items are stored in absolute
  seconds, not beats, so changing tempo doesn't retime anything that already exists) and was
  explicitly skipped (2026-10-11: "Skip tempo for now (Recommended)"). A real tempo-retime is a
  separate, larger piece of work — not to be built unless asked again.
- Mounted on the control room's BACK wall (`Venue.rig_roulette_spot`), not a side wall: both
  side walls sit behind furniture that lengthens with every track's own FX (the mixing rack off
  the left wall, the patchbay off the right), and a long enough one stands between the seat and
  anything mounted on the wall behind it -- `tests/run_tests.gd`'s own seat-click audit, run at
  40 tracks, catches exactly this. It also carries its own lamp (`RigRouletteStation._lamp`,
  the same fix `TourCase._lamp` already makes for its own dark corner), since the wall it ended
  up on sits past the ceiling downlights' own reach.

Open follow-ups, not built:
- A real tempo-retime (see above) — would need item times converted to a beat-relative
  representation, or a second absolute-time pass applied on every tempo change. Large; wait for
  it to be asked for again.
- The VST pool it draws from, when hooked to a live Reaper host, is the host's own installed
  plugin list (`ReaperBackend.fx_choices`, fed by `reaper/dawlings_bridge.lua`'s
  `ListInstalledFx` handler over `reaper.EnumInstalledFX`) — shipped as part of this same ask
  (2026-10-11: "Solve teh VST issue... just make sure we stay within our licensing requirements"),
  stays within licensing by construction: real plugin binaries only ever load on the host's own
  machine, same as every other FX action already works; guests only ever see id/label strings.

## Tick T -- the rack unit's own name ran into its own buttons (2026-10-11)

"Rack unit labels can overlap their first knob caption on long plugin names," from this list.
Measured rather than trusted: built a unit with a long track name and a long plugin name
(`RHYTHM GUITAR DOUBLE` / `UAD Precision Buss Compressor`), screenshotted it, and cropped in.
The actual collision is not with a knob caption a full row down -- `RULE_Y` leaves 48mm between
the header and the knob row, nowhere near enough for any font to bridge -- it is with the bypass
button and, on a plugin past `MAX_KNOBS`, the page readout beside it, both in the SAME row as
the name. `RackUnit._name_label` was built with `font_size = 64` and no `width`, no
`autowrap_mode`, and critically no `Lettering.fit` call -- the one label on this panel nobody had
ever put through it, where the console's equivalent (`ChannelStrip._name_label`) already was.

Fixed by giving the name a stated span (`RackUnit.NAME_SPAN := 0.24`, the TearTab's own width --
the grip over the name already claimed this ground, so the label's fit now claims the same
ground rather than a separately-guessed one) and calling `Lettering.fit` on it in `refresh()`,
the way `ChannelStrip.refresh()` already does for its own name. Floor is 32 (`NAME_SIZE_MIN`),
proportioned off the console's own 80:40 ratio for its 64px default. Re-screenshotted the same
repro clean; added `_test_rack_unit_name_stays_off_the_header_icons`, which measures the fitted
label's actual rendered width against its font rather than re-rendering a frame, so the check
stays fast and keeps failing if the span ever regresses.

Open follow-ups, not built:
- The same "never fitted" gap might exist elsewhere nobody has stress-tested with a long name;
  this tick only looked at the rack, because that was the reported one.

## Tick U -- the neon ball's own glow was blooming it into one colour (2026-10-11)

"The neon ball reads as a pink ball; its bands do not show as bands," from this list. Measured
rather than trusted: pulled the real `toy` item out of `ItemRoom`, forced it to the grid venue,
pinned it in front of the camera at both an exaggerated scale (to see the geometry clearly) and
at its real size from a realistic holding distance, and screenshotted both.

`ToyItem._skin()`'s `"glow"` material (the three bands `tools/blender/toys.py` cuts into the
ball, against a `"shell"` material for the dark ball between them) was built with
`emission_energy_multiplier = 3.0` -- a grep across every `emission_energy_multiplier` in the
project (`hardware/materials.gd`, every held item) turned up nothing else above 2.4, and that
2.4 is the LED helper, for a few millimetres of panel, not a third of a 7cm ball's surface. At
3.0, bloom bled the bands' own glow across the dark shell between them widely enough that the
geometric band-vs-shell split barely read at the ball's real, small on-screen size -- confirmed
by the real-scale screenshot, where lowering the number alone visibly tightened the glow back
onto the bands and let the shell's own dark colour show between them.

Fixed by lowering it to 1.4, matching the keytar's own `_lit.emission_energy_multiplier` --
already the project's number for something sizeable enough that its shape has to stay readable
through its own glow rather than disappearing into it, rather than inventing a new one.
Checked by `_test_the_neon_ball_glows_without_blooming_into_one_colour`, which pins the number
against the project's own established range (`<= 2.4`) and confirms the shell carries no glow
of its own -- a measurement, so it keeps failing if the glow goes back up without the washout
actually being re-examined, rather than a screenshot nobody re-takes.

Open follow-ups, not built:
- The grid venue's own ambient light (`GridVenue.dress`, `Color(0.36, 0.20, 0.55)` at 0.42
  energy) tints the ball's dark shell pink too, on top of its own bloom -- deliberate venue
  atmosphere, shared by everything else in that room, and not this ball's own bug to fix alone.
  The band-vs-shell contrast is real and visibly improved by this fix; the whole room reading
  pink in the grid venue is the room working as designed.

## Tick V -- the beach ball's own radius cancelled out of its own held distance (2026-10-11)

"The beach ball, held on a desktop, is a big thing over the desk and hides some of it," from
this list. Measured rather than trusted: tried `--carry toy` on a fresh venue first and got a
screenshot of an empty-looking glove -- the carried item's own spring-damper
(`Item._physics_process`, easing toward `held_pose()` rather than snapping to it) hadn't caught
up by the shot's default capture frame, 21 frames after pickup. Recaptured 90 frames in instead
(`tools/shot.sh out.png 90 96`) and the ball was there, floating in front of the console and
covering its whole BPM/ADD/RAMP/DEL/SIG row.

`ToyItem.held_pose()`'s `-size - 0.3` puts the ball's CENTRE a radius-plus-30cm from the hand --
and since the ball's own radius IS `size`, that radius cancels out of where the NEAR surface
ends up: always a flat 30cm from the eye, for a toy 3cm across or 20cm across alike. Every other
toy is under the 0.1 branch that skips this entirely (held flat in the palm), so this formula
has in practice only ever been tuned against the one toy big enough to notice, and 30cm of
clearance for its 20cm radius is most of a desktop view.

Fixed by doubling the radius term before the flat clearance (`-size * 2.0 - 0.3`): the near
surface moves from a flat 30cm to `size + 0.3`, so the beach ball gets 50cm instead of 30 while
every toy under the 0.1 branch is untouched (this line never runs for them) and the formula's
own limit as size -> 0 is unchanged. Re-screenshotted the same repro (same frame-90 technique) --
the BPM row is clear now, though the ball still covers part of the timeline above it, which
reads as proportionate for something 20cm across held up to look at rather than as the bug.
Pinned by `_test_the_beach_ball_does_not_crowd_the_view`, which checks the computed near-surface
distance against the old flat number rather than re-rendering a frame.

Open follow-ups, not built:
- The spring-damper settle time this tick ran into by accident (a carried item takes well over
  a second of physics time to reach a `held_pose` far from its home spot) is itself worth a
  look if a future tick is ever about how a THROW or a CATCH feels on a long carry -- not
  touched here, since this tick's bug was about the end state, not the time to reach it.


## Tick W -- a held keytar's own length ran it across the whole desk (2026-10-11)

"Keytar: ... Held on a desktop, it covers most of the desk," from this list. Used the frame-90
capture technique from Tick V straight away this time (`SHOT_ARGS="--carry keytar" tools/shot.sh
out.png 90 96`) rather than rediscovering the settle-time gotcha: the keytar was there at frame
90, 0.9m of body and neck spanning the full screen width, hiding every one of the console's 13
fader strips underneath it.

`KeytarItem.held_pose()`'s desktop (`MouseInteractor`) branch put the base offset's z at `0.0` --
right at the glove's own depth, with only `CRADLE`'s own 0.1m and the instrument's length to carry
it anywhere, none of it pushed back from the eye. Traced `MouseInteractor.carry_pose()`: the
glove's basis is the camera's own, so local -Z in a held item's offset is away from the eye (the
same frame `CARRY_AT`'s own -0.5 z already relies on) -- the fix is a more negative z, not a less
negative one.

Fixed by moving the base offset's z from `0.0` to `-0.35`: re-shot the same repro and the console's
whole fader row reads clearly under the keytar now, with the keybed still tipped up toward the eye
and legible to play by -- matching the file header's own stated intent for the pose. Pinned by
`_test_a_held_keytar_clears_the_console_instead_of_covering_it`, which checks the exact -0.35
rather than re-rendering a frame.


## Tick X -- a held cradle floated clear of the hand it was in (2026-10-11)

"The cradle: ... Held on a desktop it floats just over the glove rather than resting on it," from
this list. Didn't trust a render on its own: added a one-frame `--shot-debug` print (reusing the
existing frame-28 hook, moved to frame 90 for the settle time Tick V already found) of the carried
item's and the mouse's own `CarryGlove`'s `global_position`. At frame 90 the cradle's base sat at
world y 1.109 against the glove's own origin at 1.130 -- and the glove's palm mesh sits centred on
its origin, roughly 0.021m thick along the direction its target transform turns into world "up"
(`Glove._palm`'s sphere, scaled and sized in `core/session/glove.gd`), putting the palm's own top
surface near y 1.151. A good 4cm of daylight between the two, which a screenshot confirmed reads
exactly as "floating over" rather than "resting on".

`CradleItem.held_pose()` had one pose, shared by a tracked headset hand and the desktop mouse
alike, with a flat `-0.03` in y. A tracked hand has no `Glove` drawn under it at all (only a mouse
gets one -- `core/input/interactor.gd`'s own comment on `_show_glove`), so the pose was never
wrong for a headset; it was only ever wrong for the one case with a visible hand mesh to float
over. Branched the desktop (`MouseInteractor`) case out, same as the keytar's own branch, and
raised its y from `-0.03` to `0.0` -- close enough, re-shot the same repro (`SHOT_ARGS="--carry
cradle" tools/shot.sh`), that the base now reads as sitting on the fingers rather than hovering
clear of them. The headset branch keeps the old pose untouched. Pinned by
`_test_a_held_cradle_rests_on_the_mouses_glove_instead_of_floating_over_it`, which checks both
branches' exact y.


## Tick Y -- a ghost's own name floated through whatever stood in front of it (2026-10-11)

"A ghost's caption ('HOLDING RADIO PLANE') is drawn over whatever is behind its head," from this
list. Built a real repro rather than guessing at the geometry: `--visitor` to stand a second
player (Lin) behind the timeline's SCREEN-mode surface from the seat's own camera, holding the
keytar so her caption had text, framed with `--cam` so her head and the label above it both
landed in frame. The screenshot showed "Lin" and "HOLDING KEYTAR" floating in the middle of the
timeline -- the screen is a few centimetres from the camera and should have hidden her and
anything drawn where she is completely.

`Presence.Avatar`'s `_tag` and `_caption` -- the name and the "HOLDING ..." line, both Label3D
nodes built in `_init` -- had `no_depth_test = true`. That skips the depth comparison outright, so
the label draws regardless of what opaque geometry already occupies that pixel, nearer the camera
or not; it was never "drawn over whatever is BEHIND its head" so much as drawn over everything,
head included, whatever stood between the two. Removed the line (Godot's own default for a
GeometryInstance3D is the ordinary depth test) and re-shot the same repro: the label is cut by the
screen's edge exactly where its mesh is, the same as the head it floats above already was. A
second repro with nothing between Lin and the camera confirmed the ordinary case is untouched --
the label still draws, just honestly now.

The dot that marks who is speaking (`presence.gd`'s `_dot`) keeps its own `no_depth_test = true`:
a different thing (an always-on indicator, not a label meant to read as part of a specific,
occludable person), and out of scope for this tick. Pinned by
`_test_a_ghosts_name_and_caption_respect_what_is_in_front_of_them`, which checks the property
directly on a fresh `Presence.Avatar` rather than re-rendering a frame.


## Tick Z -- a keytar in hand had no way to say where its notes went, on a host's own Reaper (2026-10-11)

Asked directly rather than pulled from the list: wanting the keytar hooked up to "any synth
plugin I have" turned out, once narrowed down, to mean choosing which track a keytar's notes are
recorded onto -- already exactly what `GuestMidi.target_track` and the session panel's own "Play
into" dropdown do, confirmed in `core/session/guest_midi.gd`'s own docstring ("whatever this
machine is, a host or alone too"). The dropdown was just unreachable in the one case that matters
for it: `SessionPanel._place_mic()` hides `_keys_box` whenever `host_records()` is false, which is
right for ordinary MIDI keyboard input on a host whose Reaper already takes that itself -- but
`GuestMidi.plays()` says a keytar plays through here regardless ("anyone's with a keytar"), so the
one control that lets a player steer where it lands was gone in exactly the case that needed it.

Fixed by widening `_keys_box`'s (and the signal that refreshes it) visibility to include
`Session.guest_midi.keytar`, so the panel comes back for as long as the keytar is actually in
hand, host-on-Reaper included, and goes again once it is put down. Along the way, the dropdown's
own "nothing chosen" label (`"The armed track" if gm.host_records() else "Nowhere"`) was caught
making the same host_records()-only assumption `take_track()` itself does not: unset, a keytar
already falls through to the armed track, never nowhere, so the label was corrected to match.
Verified with a test rather than a screenshot -- this is panel visibility and dropdown text, not
rendered geometry. Pinned by
`_test_a_keytar_reaches_its_track_choice_even_where_reaper_records_its_own_midi`, which puts a
host on a `ReaperBackend`, confirms the panel is hidden without a keytar, shown (in the host's own
section, not a guest's) with one in hand, reads the "armed track" label correctly, and hides again
once it is put down.

Open follow-ups, not built:
- Ambient (non-keytar) MIDI input on a Reaper host still goes straight to Reaper with no panel of
  its own here, by design -- Reaper already has its own input choice for that case. Only the
  keytar's own always-captured input was missing its way back to this panel.

## Tick AA -- a dart that missed lay on the floor with its own flights sunk into it (2026-10-11)

"A dart that misses lies flat on the floor with its flights sunk in it," from Known rough edges.
Chased down a hypothesis about the keytar's own glossy body first ("a hot spot where the desk
lamp catches its gloss," the line above that one) and dropped it: a close screenshot of a held
keytar did show a blown-out white patch, but zeroing out its clearcoat entirely and re-rendering
left the exact same pixels (`magick ... -crop ... txt:`, bit for bit) -- which meant the patch was
never the keytar's material at all, just the DAW screen's own lit SIG button sitting behind it in
frame. No real repro in hand, and no second finding to replace it with cheaply (it wants a second
machine's camera on a ghost's hand, which several tries at framing didn't land), so left alone for
whoever picks it up with a better way to frame that shot, and moved to the dart instead.

Measured rather than trusted there too: a `--shot-debug` hook (temporary, removed after) printed
a thrown dart's own position every 20 frames once it missed and came to rest loose on the floor --
exactly `(x, 0.0, z)`, not a hair off. A standalone headless script
(`godot --headless --script`) loading `dart.glb` and walking every mesh's AABB through its own
transform (the same technique `HeadphonesItem._lie_flat` already uses) gave the model's real
cross-section: `0.011102` either side of its own centreline, the whole way down its 0.15 m length.

`DartItem.centre_height()` returns 0 -- right when it is stuck in the board, point-first, since
the point IS the origin and exactly where it goes in. But a miss does not stick: it lies loose on
its SIDE instead, and `Item.launch()`'s non-stuck branch sets `resting` straight from the flight's
own raw floor contact, `Transform3D(Basis(UP, yaw), f.rest)`, with no lift at all --
`centre_height()` only ever shapes the TUMBLE (`Item._fly()`'s `middle - pose.basis * middle`),
which nets to exactly zero once the item settles level, regardless of what `centre_height()`
returns. So the dart's own point-first convention, right for the one state it was written for,
left its OTHER rest state -- lying on a cross-section no other thrown item in the room has reason
to think about, since each of theirs already rests on its own base -- sitting exactly on the
floor's own centreline, flights and all, half of it below the boards.

Fixed narrowly, not by touching `centre_height()` (the tumble still wants 0 there) but by giving
`Item` a second, independently overridable hook, `loose_rest_lift()`, defaulting to 0 (so every
other item is untouched), called from both `launch()`'s non-stuck branch and `lay_down()` (a put
rather than a throw hits the exact same floor-centreline problem). `DartItem` overrides it with
the measured `0.0111`. Checked by re-running the same `--shot-debug` repro: the dart's own rest Y
now converges to `0.0111` precisely, not `0.0`, and pinned in `tests/run_tests.gd`
(`_test_darts_stick_in_the_board_and_score`, which already laid a dart down loose) against
`DartItem.LOOSE_LIFT` rather than a screenshot. The same test's earlier assertion that a dart
STUCK in the board lands exactly on its aimed point, unmoved, stands untouched -- confirming the
stuck path was never touched by this fix.

Open follow-ups, not built:
- The keytar's own "hot spot ... where the desk lamp catches its gloss" line, above, is still
  unconfirmed and still on the list: the DAW-screen false lead is now written down so nobody
  repeats it, but the real repro (a second machine's camera on a ghost holding one, somewhere
  near that lamp) was not found this tick.


## Tick AB -- the timeline was hard to read, boring, and flat (2026-10-12)

Asked for a complete redesign of the timeline ("ugly, hard to see, boring, doesn't take advantage
of 3D"). Looked first, at 1280x720 on the real panel (`shots/tl/before-default.png`): pastel
blocks at value 0.30-0.50 against lane beds at 0.13, 7px item names in white on pale, a hairline
playhead, and a "3D" shelf view that is **invisible** -- `shots/tl/before-shelf.png` is the flat
view to the pixel, because 11 mm of extrusion on a 1.3 m panel framed square to the eye is
nothing. Depth that does not move or show an edge does not read at the distance this is read from.

**Three spatial concepts were mocked up** (`tools/mock/timeline_concepts.gd`, shots in
`shots/tl/mock-{a,b,c}.png`): a highway (time away from you), curved tiers (an amphitheatre) and
glass strata. Curved tiers was picked first and half built -- a cylinder bend in a vertex shader
with the exact inverse for hit-testing -- and abandoned before it landed. A search for prior art
turned up almost none for a 3D *arrangement* view (KORG Gadget VR rings the sequencer round you;
RipX on Vision Pro is announced; the rhythm-game note highway is the one proven use of depth, and
it is for playing, not editing), plus a commentary that a project in a big virtual space is no
help for editing. So: **keep a flat, precise editing surface and make it legible; put the depth
where it has precedent, in a separate playback view.**

*The flat editor* (`TimelineSurface`): clips were value 0.30-0.50 on a lane bed at 0.13; now
`item_body` is 0.58-0.80 on 0.105, so a clip is the brightest thing on its lane, with a drop
shadow and a darker bottom edge under it (the `ItemShades` bank, until now the shelf view's alone)
and a thicker take strip. Names are 38 not 28, in ink on a lit clip and light on a muted one
(white on pastel was the smudge). Lane beds take 10% of the track's colour (16% picked), so a lane
reads back to its name across the panel, and the identity chip is 7 mm not 4.5. The playhead is
2.2 mm with a glow band round it and a bigger head. The screen face and ruler are darker so the
bar lines (brighter) and section names (40 not 32; numbers 48 not 40) stand out of them.

*The road* (`TimelineHighway`, the ROAD key, `TimelineSurface.set_highway`): tracks are lanes,
time runs away from you down a road laid back 58 degrees from the panel, six bars of song on it.
The gate at the near end is the playhead; a lane's receptor under it is lit while that lane has
an unmuted take under the gate; names lie on the apron in front of it. Blocks are one banked draw
call with a shader that shades top, near end and sides apart, so a slab reads as a slab without
the room's lamps. It takes no presses -- the lanes, header and ruler strips have their collision
layer zeroed while it is shown, and the flat playhead and loop band are held hidden by
`_move_playhead`/`_draw_loop` so nothing flat shows through. The screen face is hidden too:
kept, it is an opaque wall the receding road disappears behind (found by leaving it on).

Pinned in `tests/run_tests.gd`: `_test_the_timeline_clips_are_the_brightest_thing_on_their_lane`
(clip value >= 0.58 and >= 0.40 over the bed; muted dimmer but above it; ink/light names; a
shadow and edge per clip) and `_test_the_timeline_can_be_watched_as_a_road` (built hidden; shown
with a lane per track; presses refused while shown and restored after; none of the flat lanes
visible; at 30 s a take that is playing starts at the gate, lamps lit exactly for the lanes with
one under it; at 10 s only the intro is lit and the verse is still down the road). Screenshots
(1280x720 and 1920x1080, flat and road; seated, standing, visitor -- the panel is framed to the
camera in SCREEN mode, which is every medium's default, so those read the same):
`shots/tl/after-*.png`. `tools/screenshot.gd` gained `--tl-shelf on|off` and `--tl-road SECONDS`.

Open follow-ups, not built:
- The road is a view, not an editor: no press on a block, no seek by pressing the road. It would
  want the same drag-plane treatment the lanes have.
- The road is a key, not a mode that follows the transport. Whether it should open itself while
  rolling is a product call, not a correctness one.
- With a few long clips (this demo's are 16 bars) the road is mostly full-length slabs. Bar lines
  carry the motion; a distance fade on the far end would help and needs per-instance custom data
  the banks do not carry.
- The ROAD choice is not saved in the layout the way 3D is.

### Tick AB addendum -- controls were tiny (2026-10-12)
"All the buttons and dials and knobs are sooooo tiny." Timeline keys now draw at `KEY_SCALE` 1.7 with
larger captions, and the four control strips lay out left to right at up to `STRIP_SCALE_MAX` 1.5 (the
panel's `content_aabb()` ignores them so the framed panel does not shrink). Console channel strips draw
their R/S/M/I buttons and pan knob at 1.45x with a letter legend in the left margin. Tests pin the
scales; seat-click audit still passes.
Open follow-ups, not built: the tape deck is still cut off at the right edge of the seated frame and
its keys are small; off-lamp contrast (`Materials.LAMP_DARK`) is unchanged.

Verification, end of Tick AB (2026-10-12): `tools/verify.sh` 7174 / 0 failed (bridge 7, dawkit 359);
`session_probe` offline 53+47, `--built-in` 79+42, all 0 failed; `--reaper` guest 48/0 and host 86 with
one failure ("Reaper added a stock plugin to a track and removed it"), which fails identically on the
commit before the timeline work, so it is the local Reaper install, not this change. Camera evidence for
the flat editor at several positions (`SHOT_ARGS="--tl-shelf off"`): seated `shots/tl/c1.png`, VR eye
height 1.65 m `shots/tl/vr-height.png`, across the room `shots/tl/across.png`, plus the earlier
standing/visitor/road set `shots/tl/after-*.png`. Note: with an explicit `--cam` the 3D shelf is on by
default and clips read as dim edge lines head-on -- the 3D key still toggles it; flat is the legible one.

Tape deck (2026-10-13): keys drawn at `KEY_SCALE` 1.65 (transport three `BIG_KEY_SCALE` 1.95, up from
1.4/1.6) and captions at 38, pinned by `_test_the_tape_decks_keys_are_big_enough_to_aim_at`. The deck is
a side piece of furniture (trolley at 0.80, -0.22), so the seated default frames the timeline and
console and it is reached by looking right (`--look 50,-25`, `shots/tl/d3_50.png`); that is by design,
not a cut-off bug. Off-lamp contrast left as is.

## Public repos, lazygradle-style build system, README media (2026-10-13)
gd-dawlings and gd-dawkit are public (history scanned first: no keys, no home paths; assets are
own-made or CC0; dawkit keeps its all-rights-reserved LICENSE, so it is source-visible, not open).
The old single `build.yml` is replaced by `ci.yml` (suite), `release-check.yml` (suite + Linux and
Windows export, the PR gate and the reusable release gate), `release-beta.yml` (every code push to
master -> `vX.Y.Z-beta.N` pre-release with both zips), `release-stable.yml` (manual, bumps `VERSION`
by PR), Dependabot (actions and the dawkit submodule) and CODEOWNERS; see `RELEASING.md`. dawkit
needs no deploy key now. First beta (`v0.0.3-beta.1`) went through end to end. dawkit gained its own
CI/Dependabot/CODEOWNERS. README has screenshots of every venue, the tape deck and the road view, and
two clips (`tools/movie.sh`, new; `--roll` in `tools/screenshot.gd` starts the transport).
Open: the `DAWKIT_DEPLOY_KEY` secret and deploy key on gd-dawkit are now unused and can be deleted;
no branch protection / required reviews set yet.

## Rig Roulette starts a new project (2026-10-13)
(The user: "the number of tracks should get clobbered to something random (roll). it should start
a new project (only allowed if there are no pending changes to current project)".)
ROLL now refuses with "Save the project first" while the open project has unsaved changes, and
otherwise starts a new project with 2-8 random tracks, lands `count` character pedals on them,
and rolls a named key unless LOCK KEY is lit. There was no unsaved-changes notion anywhere, so
`OfflineBackend` counts edits (`_remember`, undo, redo) against the count at the last
save/open/new (`has_unsaved_changes`, `mark_clean`, reached through `DAW`); undoing back to the
saved point still reads as changed. The rolled project is marked clean so it can be re-rolled.
The key is only named (the project is empty, nothing to transpose), and the ANY/OPEN TRACKS wheel
is gone since every track of a new project is open.
Open follow-ups, not built: the Reaper backend cannot report unsaved changes (answers false) and
cannot start a project, so ROLL there says it cannot; rolling tempo; the visible spin and the
no-re-roll constraints board.

## Rig Roulette board on the wall (2026-10-13)
(The user: "Rolling should populate a huge screen on a wall ... that explains the roll and what
was done".) `RollBoard` (hardware/rig_roulette/roll_board.gd), 3.6m x 1.14m on the control room's
back wall above the acoustic panels, writes up `Session.roll`: track count, key, each pedal and
the track it landed on, who rolled. `Session.publish_roll` replicates it (host-authoritative,
sent to late joiners, like `tour`), so guests read the same board. A slate with chalk colours
where `Venue.roll_board_chalky` (the chalk zone); every other venue gets the lit screen.
Found on the way: `rig_roulette_spot` stood 2cm inside the wall (the wall's face is 5cm out of
ROOM_FRONT), so the panel's plate and lettering were buried and only its buttons showed. Moved
out to +0.07. New shot arg `--rig-roll`.
Open follow-ups, not built: the board only exists in the built-in venues' control room back wall
(AR builds neither); chalk lettering drawn as strokes rather than a slate with text.
Queued by the user next: every venue's stationary gear (console, timeline, cabinets) themed to match it.

## Gear dressed to its venue (2026-10-13)
(The user: "every environment to have more on theme stationary elements like the mixing console,
timeline view, cabinets, etc. their vibe needs to match the venue". Chose all nine at once.)
Found: the gear was the same black powder coat in all nine venues; only the surroundings changed.
Every piece of gear draws from a few shared cached materials, and a venue switch does not rebuild
the gear, so `Venue.gear_style()` returns a `GearStyle` (hardware/gear_style.gd) and
`Materials.apply_style` copies its finishes onto the shared materials in place (STYLED: chassis,
furniture, brushed, end_cheek, trim) -- gear already built changes with them, MeshBank
multimeshes included. New `Materials.furniture()` split from `chassis()` for what the gear
stands in (console body and skirt, rack frame and plinth, patch cabinet, timeline stand legs,
deck trolley), so faceplates under the legends stay dark. New `GearTrim.edges` puts eight edge
strips in `Materials.trim()` round those boxes: steel in the studio, a lit line in club (amber),
chalk (white), dome (aqua), grid (cyan), rooftop (sodium), station (blue). Strip thicknesses are
staggered and uprights stop short of the top and bottom so the coplanar-face audit stays clean.
Styles: studio defaults; cabin deck timber, iron, plank cheeks; club tolex road cases with chrome;
chalk slate; dome teal plate and brass; grid gloss black, magenta cheeks; loft steel plate and
walnut; rooftop grey ply flight cases; station white panels.
The roll board now stands on two posts in the venues with no wall behind it (chalk, dome, grid,
rooftop), framed and trimmed in the venue's furniture, and is rebuilt on a venue change.
Record: shots/venue_gear_styles.png.
Open follow-ups, not built: the Rig Roulette panel itself still hangs in the air in those four
open venues (pre-existing); shapes per venue (a real road-case rack, a log-built desk) rather
than finishes; the tape deck body and rack units' faceplates are unstyled.

## Lamps, tablet stands and the roulette panel join the venue's gear style (2026-10-13)
(Goal set by the user: "style all persistent elements for all venues".) Lamp stand bases and
plugin tablet feet now use `Materials.furniture()`; lamp shades get their own styled finish
(`Materials.lamp_shade`, new STYLED key): iron in the cabin, brass in the club and dome, chalk
white, magenta neon on the grid, green enamel in the loft, copper on the rooftop, white on the
station. The Rig Roulette panel stands on a trimmed post and foot in the four open venues
(`RigRouletteStation.set_free_standing`, redone on a venue change); `Venue.back_wall_gear_stands`
(renamed from `roll_board_free_standing`) says so for both it and the board.
Still to style, next ticks: the Tour case, the hoop, the mirror and wardrobe frame, and the
faceplate tint in the venues that leave `chassis` at the studio default.

## The rest of the persistent pieces join the venue's style (2026-10-13)
Inventory of everything that stays in a venue, and where its look now comes from:
- Console, rack, patchbay, timeline stand, deck trolley, lamps, tablet stands, roll board,
  roulette panel: `GearStyle` finishes (earlier entries).
- Tour case: its shell and hardware are now `Materials.furniture` / `brushed_metal` (were fixed
  black and steel), so it is a timber crate in the cabin, a road case in the club, white on the
  station, and follows a venue switch.
- Gear looms: the heat-shrink band is a new styled finish, `Materials.loom_band` (STYLED key
  `loom_band`); the jacket stays cable-black everywhere, like the patch cables.
- Faceplates: club, loft and rooftop now tint `chassis` too (every venue but the studio, whose
  default it is).
- Wardrobe board: the six venues that left it plain (cabin, club, dome, loft, rooftop, station)
  now dress it, board, ink and arrows.
- Already the venue's own before this: every mirror frame (all nine `_frame_mirror`), the prop
  shelf and the hoop (built from the shelf's frame material, chalk's drawn).
Deliberately not styled: knob and fader caps, LEDs, patch cables and screen faces -- colour
there is information (mute red, solo yellow, a cable's send), not finish.
Tests: every venue's loom band and wardrobe board are distinct; the Tour case's shell is the
furniture finish.

## Knob and fader caps take the venue's style (2026-10-13)
The neutral knob bodies (console pan knobs, rack knobs) and fader caps now come from two new
STYLED finishes, `Materials.knob_cap` / `fader_cap` (a style that names only `knob_cap` gets it
on its faders too, `STYLED_FALLBACK`): brown bakelite in the cabin, oxblood in the club, slate in
chalk, brass in the dome, gloss magenta-black on the grid, black bakelite in the loft, anodised
copper on the rooftop, blue-grey on the station. Kept mid-to-dark in every venue so the
legend-light pointer line on each still reads. Coloured caps stay `cap_plastic(tint)`: their
colour is information.
Correction to the "Gear dressed to its venue" entry above: the tape deck body and rack unit
faceplates were never unstyled -- both are `Materials.chassis()`, which every venue but the
studio (whose default it is) now tints.
Not styled, by decision: LEDs, patch cables, screen faces and the coloured caps (information,
not finish); shapes per venue (a separate modelling job, not a finish).

## Each venue fits its own shapes to the gear (2026-10-13)
The shape half of dressing the gear, taken up after all ("Do per-venue shapes too"). Every box
`GearTrim.edges` outlines (console body, rack plinth, patch cabinet, deck trolley shelf...) joins
group `gear_box` and is handed to `GearShape.dress`, which fits the current venue's kit to it at
its real size: corners at the corners, uprights stretched to its height, handles on the sides,
latches front and back, a face piece centred on each face. A kit is one model per venue,
assets/models/gear_kit_<venue>.glb, built headless by tools/blender/gear_kits.py, its parts named
for their slot and its materials named for the shared finish they wear, so the fittings follow
the venue's GearStyle in place. `studio.set_venue` calls `GearShape.use`, which swaps the kit
whole on every box in the tree.
- club: road case ball corners, recessed spring handles, butterfly latches
- rooftop: flat riveted corners, rope loop handles through iron eyes
- cabin: hewn log uprights, forged iron straps round the top corners
- loft: black iron pipe uprights on bolted flanges
- dome: riveted brass top corners, a porthole on each face
- grid: lit pyramid finials, a neon chevron on each face
- station: bumpered corners, a vent grille on each face
- chalk: no kit; each box is drawn round in chalk instead
- studio: no kit; the gear as designed
Fittings are gated by size (no corners on a box under 20 cm, nothing on a 4 cm shelf). First
pass had the club corners (5.5 cm) and loft pipe (r 1.7 cm, half inside the box) lost under the
trim at standing distance; enlarged to 8.5 cm and r 2.8 cm. shots/venue_gear_shapes.png.

## The big board shows any surface (2026-10-13)
"I wanna be able to put any other surface on the big screen as well or toggle through them."
The Rig Roulette board can show any mounted surface live (console, timeline, FX rack, patchbay,
tape deck) instead of the roll's write-up. A BIG SCREEN wheel on the Rig Roulette panel picks
it: scroll to choose, click to step to the next. The choice is the room's: `room_state` carries
"board", guests ask with the `board_source` room verb (predicted locally), and a roll puts the
write-up back.
`BoardFeed` (hardware/rig_roulette/board_feed.gd) is a second camera like the mirror's:
orthographic, square to the surface's working face (pitched by `screen_pitch_degrees`, the same
face the mount turns to a monitor), sized to `content_aabb`, rendering only while the board is in
view. It draws one layer, `ON_BOARD` (1 << 17), which it puts on the shown surface's parts (not
its presentation chrome) and takes off again, so nothing beside or in front of the gear is in
the picture. A camera's cull mask culls lights too, so every Light3D also gets ON_BOARD, or the
gear came out black. Highlights roll off as on the mirror's glass. `Studio._keep_out_of_mirrors`
now swaps layer bits rather than comparing the whole mask, so it leaves ON_BOARD alone.
Not covered by the session probe: the "board" field rides the room state like every other field.
The rack is tall and thin, so it shows small on a wide board. `tools/screenshot.gd --board <id>`.

## A track pulls out of the rack on a rack of its own (2026-10-13)
"drag on the fx rack on the entire track level (similar to the independency plugin pull out) and
pull out a brand new fx rack that is only that track. it should have a button to fold it back in
but not the abiliy to switch tracks like the "master" one"
The main rack's track window has a grip (`TrackGrip`, a TearTab with a rack-sized ghost) at its
left end. Drag or click it and the racked track comes out as a `RackSurface` with `pinned` set,
up on a plinth on its own casters (`Studio._build_track_rack`), landing in front of the rack.
Pinned: no TrackPicker, no grip, ignores the DAW's selection, follows its track through
renumbering; its track's name is an amber strip where the window was, with a FOLD button beside
the ADD window. Its units still tear off onto tablets, landing in front of that rack. One per
track (pulling the same track again wheels that one over). The room's: room_state
"track_racks" {id: [track, x, z, heading]} (kept out of "floor"), asks `open_track_rack` /
`close_track_rack` predicted on a guest like the tablets, saved in the LayoutProfile's
`track_racks` with floor transforms "floor/<id>". The host folds a rack whose track is deleted.
`tools/screenshot.gd --pull-track`. shots/track_rack_pulled.png.

## Tracks shown in the venue's colours, and more of the gear colour-coded (2026-10-13)
"can we get more color coding across tracks and the hardware. color palletes should match theme
of venue"
`TrackColours` (hardware/track_colours.gd): a track's stored colour (Reaper's, or the COLR key's
step through STANDARD, the twelve the timeline strip used to define) is never rewritten. It is
SHOWN in the venue's `track_palette()`: twelve colours per venue in STANDARD's hue order, a
track drawn as the counterpart of the STANDARD colour nearest its own. Uncoloured tracks (the
TrackState default grey) get a colour by number, round the wheel in big steps. The studio
palette is STANDARD and shows a coloured track exactly. Every display read goes through
`TrackState.shown_colour()` (console chips, timeline lanes/items/notes/waves/fades/bed, highway,
patchbay rows, plugin tablet chip, rack ghost, COLR lamp). `Studio.set_venue` calls
`TrackColours.use` and `_recolour_tracks` (marks every mounted surface, tablet and pulled rack
dirty).
More of the gear coded: each rack unit's rule under its name is a track-coloured stripe
(`Materials.track_stripe`), the rack's track window has a colour chip at its end, a pulled-out
rack's name strip is in its track's colour with a chip, and its plinth has a band of the colour
on the front.
Palettes: club oxblood/amber neon, cabin earth pigments, chalk pastel sticks, dome coral/sea
glass, grid full neon, loft muted enamel and patina, rooftop sunset to dusk, station status
lights. shots/track_palettes_timeline.png, shots/track_palettes_room.png.

## SCHM colours the uncoloured tracks; they are no longer coloured on sight (2026-10-13)
"make a button to apply a color scheme if one isn't set I guess ... then it uses that as a base
or something. tbh I don't care too much. the colors can be arbitrary as well"
Reverses the previous entry's "uncoloured tracks get a colour by number": `TrackColours.shown`
leaves an unset track grey in every venue. The timeline's track strip has an eighth key, SCHM:
it writes a colour into every track that has none (`TrackColours.scheme_colour`, by the track's
place in the project, round the wheel in big steps so neighbours differ), through
`DAW.set_track_colour`, so it is stored, replicated and undoable like COLR. Coloured tracks are
left alone. Lit while there is an uncoloured track. The venue palette then reads those colours
like any other.

## The timeline stands in the room at 1.7x (2026-10-13)
"the timeline is just so damn tiny you really need to scale that up"
In the room/studio placement the timeline node is scaled whole (`Studio.TIMELINE_SCALE` 1.7):
lanes, names, keys and lettering together, so 0.86m of 2.3cm lanes becomes about 1.5m of 4cm
lanes. Its top stays where it was (centre lowered to 1.50), so it hides no more of the big board;
the stand is shorter (`TIMELINE_STAND_TOP` derived from the scale) and its legs, feet, casters,
crossbar and footprint widen with it (`TIMELINE_LEG_X`). SCREEN mode sets its own transform from
the framing and is unaffected. Scaling made three old near-coplanar overlaps big enough for the
audit's MIN_OVERLAP: ruler ticks ended on the ruler strip's bottom edge, the top MIDI notes
reached into a clip's take strip at the clip's ends, and the scrubber thumb was sunk into the
track. Each moved clear. shots/timeline_scaled_up.png (before | after),
shots/timeline_scaled_from_seat.png.

## A rack's whole frame glows in its track's colour (2026-10-13)
"I want the whole bracket to glow with the color but I like where it's going"
`RackSurface._frame_material`: both posts and both rails of every bay are
`Materials.track_glow(shown colour)` (emissive, 1.3) instead of furniture, on the pulled-out racks
and on the main rack, whose frame follows whichever track it is racking. Plain furniture with no
track. Rebuilt with the rack, so it follows a track recolour and a venue change.
shots/track_racks_glow.png.

## A stand pulled into you stops at you (2026-10-13)
"there is a bug where you can push yourself at infinite speeds with moving a thing."
A held stand follows the hand's aim, and the aim comes from your eye. Pulled toward you, the stand
was resolved only against other pieces and fixtures, so it moved into your body; the walker's
solid for it then pushed you out, your aim moved with you, the stand followed, every frame.
`FloorPlan.bodies` (the walker's `body_footprint`) is now something a HELD piece stops against,
and goes round, without being stood up as a wall for the walker itself. Pieces placed by a layout
or played back from the room ignore it. Test: `_test_a_stand_pulled_into_you_stops_at_you`.

## Bare hands, down to the fingertip (2026-10-13)
"i need hand control and pretty fine as well. down to finger tracking"
Godot ships the OpenXR hand extensions off, so a Quest tracking bare hands reported nothing:
`xr/openxr/extensions/hand_tracking` and `hand_interaction_profile` are on now, which also brings
the action map's pinch (trigger) and grasp (grip) bindings to life. On each hand:
- `PokeInteractor`: the index fingertip touches the gear directly. Within 4mm of a face it
  presses; held, the control is driven to the tip itself (one to one, the fine way); it lets go
  only when the finger comes 2cm back off, never by pushing on through. Idle while a controller
  is held (no joint data).
- `HandSkeleton`: beads and bones on the tracked joints, translucent for passthrough, tip lit
  while touching. The pinch ray hides while the fingertip is on something.
- `XRInteractor.steadied`: a bare hand's pinch ray is smoothed adaptively, hard when still and
  barely when swept.

"moving things to "screen" ... puts the edges outside of the FOV and i have no idea how to get
rid of it": in a headset a face panel is framed into the middle 56x36 degrees of the view (the
XR camera reports the desktop window's shape, not the eye's), at arm's length so its handle can
be touched. The menu button, or two fists held half a second, is Escape (`XRRig.escape_requested`
-> `Studio._on_escape`): face panels go back where they belong.

## A knob in a hand turns by turning (2026-10-13)
"the dial control with the AR/VR touch/grab is unwieldy"
A hand turned a knob by the angle of its ray's hit around the knob's centre: on a 22mm knob, a
pinch ray's tremor or a fingertip's millimetre is a big swing. Now `Interactor.twist()` (an
XRInteractor counts its roll about where it points, frame to frame so it never wraps) turns a
knob held by a pinch or a controller: TWIST_GAIN 1.5, so half a turn of the wrist is the whole
sweep. A fingertip (`touches_directly`) slides up or down the panel instead, SLIDE_PER_SWEEP 10cm.
Open: TabletSelector (KEY IN, MOVE TO) changes its choice only by scroll, which a hand has not got.

## Toward the Quest, natively (2026-10-13)
dawkit builds for android arm64 (`tools/build_native.sh android all`). `tools/fetch_openxr_vendors.sh`
installs GodotVR's vendors plugin 5.1.0 (Meta passthrough, scene, anchors, depth) into the
gitignored addons/godotopenxrvendors. Project folders are cleared through DirAccess, not `rm -rf`,
which neither Windows nor a headset can run. Next: Android export templates, a Quest preset.
First standalone APK built (2026-10-13): `tools/build_quest.sh [--install]`, preset "Quest" (arm64,
Quest 3, gradle build with the Meta vendor plugin; hand tracking and passthrough optional, no
eye/face/body). The project imports ETC2/ASTC; Meta passthrough, scene and anchor extensions are
on (asked for only where the runtime has them). Not yet run on the headset. No project icon yet.

## The big board moves to the right-hand wall (2026-10-13)
"the big screen for rig randomizer needs to move somewhere else that isnt the backdrop for the
main set": `Venue.roll_board_spot` hung it centred on the front wall, straight behind the
timeline. Now high on the right wall, facing in, at the same height (bottom 2.14m, over the
acoustic panels); free-standing venues stand it 0.45m in from the edge. Not the left wall: the
mirror, and the studio's window into the live room. The screen's finish went from 0.25 to 0.75
roughness: on the rooftop two string-light bulbs sat on the write-up as glossy discs.
Also: the rack's track window offers every track, so an empty one can be racked and given its
first plugin (it listed only tracks that already had plugins, and the built-in engine has no
Reaper selection to rack one by).

## A hosted session opens to the internet (2026-10-13)
"i need to be able to bind my public ip address": a home machine has only its LAN address; the
public one is the router's, and the host already listens on every address it has (ENet binds
"*"). `InternetDoor` asks the router over UPnP (on a thread) to forward UDP port and
port+AUDIO_PORT_OFFSET here and says the public address; opt in only (the session panel's
"Open to internet", or `--host --public`), closed when the session ends and on quit. When the
router will not, the panel says which ports to forward by hand. On this desk the router did not
answer UPnP discovery, and ufw is active, which drops the router's reply and joining guests alike.

## Five more venues, and three arrangements for every venue (2026-10-14)

"add 5 new fully featured venues and make sure every venue has AT LEAST 2 alternates". New:
the crystal cave (Crystal grotto, Glowworm lake, Lava tube), the glasshouse (Morning, Rain,
Night bloom), the festival stage (Headline night, Soundcheck, Arena), the temple garden (Spring,
Autumn, Winter) and the desert (Starlit canyon, Dawn dunes, Oasis), each with its own props
modelled in Blender, gear finishes, gear kit (`tools/blender/gear_kits.py`), track palette,
wardrobe board, mirror frame and toy (a geode, a lemon, a glow stick, a temari ball, a
tumbleweed; `ToyItem.TOYS` gained "rest" for a toy whose middle is not its size off the floor).
Every existing venue now has three arrangements too (docs/venues.md, "Arrangements"), and the
test holds every venue to at least three. `DAWLINGS_TESTS=_test_a,_test_b` runs only those tests.
- Built in parallel, one agent a venue, each with only its own files; the shared registry,
  toys, kits and docs were done first and last by one hand. Half-written files broke every
  other agent's compile (every venue loads through `venue.gd`); some worked in private copies.
- A subset run fails the duck's put-down checks: they depend on what earlier tests leave behind.
  The full suite passes.
- Known rough edges: studio, grid and chalk were already over the seat light budget before this
  (0.232, 0.265, 0.318 against 0.23), and so is studio's new arrangement (0.231); the station's
  day-side sky is a heavy shader not yet measured on a headset; the festival crowd is blocky up
  close.

## DAW parity loop starts: item mute (2026-10-14)
`docs/daw_parity.md` is the checklist, built by reading the verbs and `MixState`, not the docs.
First gap: an item had a `muted` flag that the lanes honoured and the Reaper timeline reported,
but nothing could set it. Now `DAW.set_item_muted(track, item, muted)` (an item edit, one undo
step, a guest's value is any nonzero number, a repeat is no step), `SetItemMuted` in the Reaper
bridge (`B_MUTE`), and an M key on the item strip under the timeline, lit while the item is muted.
Full suite 9986 checks, 0 failed; session probe host 53 and guest 47, 0 failed. Not looked at in a
screenshot: the strip's new key needs a selected item, which `tools/shot.sh` does not set up yet.

## DAW parity, iteration 2: copy items to the playhead (2026-10-14)
`DAW.copy_selected_to(seconds)`: copies of the selected items, the earliest one's start put at
`seconds`, each on its own track and keeping its distance from the others; the originals stay.
One undo step, a guest's malformed value refused. P key on the item strip. No clipboard: a
clipboard held by one peer is not state the session can agree on, so copy and paste are one act.
Reaper: `CopySelectedTo` clones through the item state chunk with the GUIDs stripped; written
but not run against a live Reaper. Tap tempo, listed missing in the first audit, was already on
the tape deck; corrected. Suite 9991 checks, 0 failed; probe 0 failed.

## DAW parity, iteration 3: normalise an item (2026-10-14)
`DAW.normalise_item(track, item)` sets the item's gain so the loudest moment of the part of the
file it plays reaches full scale (`ItemState.sound_peak()`, from the 50-a-second overview that is
already replicated, so a guest can do it too and it needs no new wire verb). It is a `set_item_gain`:
one undo step, same Reaper path. Nothing for an item with no overview (MIDI, or Reaper's items,
which report no peaks). N key on the item strip, lit only for an item there is sound to measure.
Overview bytes are 1/255 of full scale, so the result is within a step of it, not exact.
Suite 9993 checks, 0 failed; probe 0 failed. Not seen in a screenshot.

## DAW parity, iteration 4: note velocity up and down (2026-10-14)
`DAW.shift_velocity(track, item, by)` adds `by` to every note's velocity of a MIDI item, kept
between 1 and 127 (a guest's amount clamped to +-126, malformed refused), one undo step; Reaper
`ShiftVelocity` through `MIDI_SetNote` (`each_note` now passes the velocity through; untested against
a live Reaper). V- / V+ keys on the item strip: 8 a press, 32 held fine. Only the whole item: a
per-note velocity edit wants the piano roll to select notes, which is the next size up.
Suite 9997 checks, 0 failed; probe 0 failed. Not seen in a screenshot.

## DAW parity, iteration 5: select all items (2026-10-14)
`DAW.select_all_items()` selects every item on every track (a selection, so not an undo step;
Reaper `SelectAllItems`, untested live). An ALL key beside COPY and DEL under the timeline, lit
once there is anything to select; COPY and DEL moved closer to make room, and ALL's lettering is
smaller because the track area clips anything past it. Looked at in a screenshot of the studio's
timeline: all three captions read. The item strip (single selection only) was not shown, since
`tools/shot.sh` cannot select an item. Suite 9999 checks, 0 failed; probe 0 failed.

## DAW parity, iteration 6: clear all solos, clear all mutes (2026-10-14)
`DAW.clear_solos()` and `DAW.clear_mutes()` let go of every soloed or muted track, each through
the ordinary per-track verb, so nothing new crosses the wire and a guest's press is the same intents
a guest's taps would be. SOLO and MUTE keys either side of the balance knob on the master section,
each lit only while there is something to clear (the master section now follows `track_changed`).
Looked at in a screenshot of the studio's console: both keys and captions read. Lettering under 10
trips the legibility tests (the smallest cap), so the captions are 10. Suite 10002 checks, 0 failed;
probe 0 failed. SHOT_CAM is an orbit (yaw, pitch, distance, target), not a position.

## DAW parity, iteration 7: crossfade (2026-10-14)
`DAW.crossfade_items(track, first, second)`: two overlapping items of one track, the earlier one
faded out and the later in over the overlap, as two `set_item_fades` edits (so nothing new on the
wire, two undo steps). Linear in amplitude like every fade here, so the middle dips 3 dB where
a pro DAW's equal-power curve would not; a curve choice is the next step. X key on the item strip,
which now also shows while exactly two items of one track are selected (lit only if they overlap;
the other keys stay dark then). Drag snapping, listed missing in the first audit, was there already.
Not seen in a screenshot (shot.sh cannot select items). Suite 10009 checks, 0 failed; probe 0 failed.

## DAW parity, iteration 8: loop the selection (2026-10-14)
`DAW.loop_selected_items()` sets the loop from the first selected item's start to the last one's
end and switches looping on (`set_loop_range` and `set_looping`, so nothing new on the wire).
LP key on the item strip, which shows for one item or a same-track pair, so a wider selection
cannot be looped from the strip yet. Not seen in a screenshot. Suite 10011 checks, 0 failed;
probe 0 failed.

## DAW parity, iteration 9: the timeline redesigned as a thing in the room (2026-10-14)
The user: "remove the timeline screen entirely ... we're in a 3d environment stop with the expected
shit", then "it still needs to be bars horizontally but ... do better with ideas and looks". So
time still runs left to right and the tracks still stack, but there is no panel, no bezel, no
screen face and no words on keys. Each track is a channel of smoked glass with a thread of its
colour along its foot and a cut gem where its name is (dark when muted, ringed gold when soloed,
red when armed). Each clip is a self-lit glass ingot with a drawn bevel and a shadow on its
channel, pulled out of its row while selected; its sound stands out of its face as a relief (as
far as it is loud) and its notes as bricks (as far as they were played hard). The loop is a rod
of light along the top and a wall of blue light behind the channels; the playhead is a blade of
light through the whole depth, a bead riding the ruler, and lights the clips it cuts through
(`TimelineFinish.light_beam`). The tools are glass tokens on lit ledges, each with a sculpted
mark (`TimelineGlyph`: a curled arrow for undo, a block cut by a blade for split...) and the
words moved to the hover card; settings are rods of light with a bead (`GlyphRail`), their value
floating over the bead only while a hand is on it. The deck starts where the lanes do, not under
the names: under them its first token covered the rack's handle from the seat. Every behaviour
and edit is unchanged; tests that read the old strips read the pages now. Seen from the seat,
head-on in the room and from the side.

## DAW parity, iteration 10: a choosable grid (2026-10-14)
`TimelineLanes.grid`: what a move, a trim, a fade, an automation point and a seek snap to -- the
bar (through the signature map), the beat, half or quarter beats, or nothing. A token on the
timeline's tools beside FIT steps through them (`TimelineSurface.step_grid`); its mark is a bar
cut into that many cells, struck through when free, and the hover card says it in words. Each
person's own, like the view, so nothing crosses the wire and it is not saved with the project or
the layout yet. Fine (shift) still lets go of any grid. Seen in a screenshot from the seat. Suite
10022 checks, 0 failed. Known: the suite's teardown prints a SCRIPT ERROR from a callback in
`scenes/studio.gd` (`_remember_tablets` called on a ChalkVenue) after the summary line; not from
this change, not yet chased.

## DAW parity, iteration 11: item lock (2026-10-14)
`DAW.set_item_locked` and `MixState.ItemState.locked`. A locked item refuses a move, trim, gain,
fades (so crossfade and normalise too), transpose, velocity and quantise, checked by the host for
its own edits and a guest's (`DAW.locked_against`); a split or delete of the selection passes it
by. Muting, selecting and copying it are still allowed, as in Reaper. The lock rides the item's
optional dictionary on the wire, is saved in dawkit's clip (`DawKitClip.locked`, dawkit
submodule bumped; dawproject has no lock, so it is not written there), and is Reaper's C_LOCK
through the bridge (`SetItemLocked`, reported by GetTimeline; Split and Delete skip locked
items there too) -- not yet run against a live Reaper. A padlock token on the ITEM page; while
locked the shape's rails and keys are out of reach, the clip's thread is drawn white, and a drag
on it is only a click. Item rails narrowed to keep the page on one row. Suite 10036 checks, 0
failed; probe 0 failed; dawkit 359 checks, 0 failed. Seen in a screenshot from the seat.

## DAW parity, iteration 12: ripple delete (2026-10-14)
`DAW.ripple_delete_selected`: the selection goes, and every later unlocked item on its track moves
back by the part of each deleted item that started before it, so the gap closes without the order
changing. Other tracks are left alone (Reaper's "ripple per track"). A locked item is neither
deleted nor moved, and a ripple that deletes nothing is not a history step. One undo step; a guest
asks for it as a command. A token beside DELETE on the timeline's tools, lit with a selection.
Reaper path is `RippleDeleteSelected` in the bridge, not yet run against a live Reaper. Ripple move
and ripple trim are split out, still missing.

## DAW parity, iteration 13: pre-fader sends (2026-10-14)
`DAW.set_send_pre_fader` and `MixState.SendState.pre_fader`, on the wire as `/track/N/send/S/pre`
and in the snapshot. The built-in engine leaves the track's fader and pan out of a pre-fader
send's player (still after the track's effects, and still muted with the track), so pulling a
track down no longer pulls its cue or its reverb down with it. Saved through dawkit's existing
`DawKitSend.pre_fader`. Reaper: `SetSendPreFader` in the bridge writes I_SENDMODE 3 or 0, and the
structure poll reports any non-zero mode as pre -- not yet run against a live Reaper. On the desk,
while SENDS ON FADERS shows a return, each strip that sends to it grows a small amber PRE button
right of R and S; lit is pre. Its lamp's lit and dark are close in the room's light (a lone mesh,
not the banked lamps); worth a brighter lit colour later. The audit had send automation as missing;
it has been there all along. Suite 10073 checks, 0 failed; probe 0 failed. Seen in a screenshot.

## DAW parity, iteration 14: swing quantise (2026-10-14)
`DAW.quantize_item` takes a fifth word, swing 0..1 (`DAWBackend.SWING_MAX`): every odd grid point,
the off-beat of each pair, is that many thirds of a step late, so at 1 a pair of eighths is the
long-short of a triplet (`DAWBackend.swung_grid_beat`, nearest swung point, so a note already
played swung stays on its own off-beat). The guest's ask is now five words; a four-word one is
refused as malformed. Reaper's `QuantizeItem` in the bridge does the same arithmetic in quarter
notes against Reaper's tempo map -- not yet run against a live Reaper. On the ITEM page, a rail
with a long-short mark right of QUANTISE, in reach for an unlocked MIDI item: what the next press
swings by, each person's own, not saved. Groove templates (another item's feel) split out as
missing.

## DAW parity, iteration 15: render bit depth and dither (2026-10-14)
`DAW.render(stems, bits)`, bits one of `DAW.RENDER_BITS` (16, 24, 32), 24 the usual. dawkit
(5bcff1d, submodule bumped) writes 16- and 24-bit integer WAVs with triangular dither of one step,
seeded so the same sound writes the same file, as well as 32-bit float (`DawKitAudioFile.write_wav`'s
new `bits`); the built-in render passes the depth through `MixRender.bits`. The built-in render
used to be 32-bit float only. A guest's ask carries its depth; one outside the three, or missing,
renders at 24 rather than being refused. Reaper: `RenderProject` takes the depth as a fifth word,
sets the WAV sink to it, and turns dither on for master and stems below float (RENDER_DITHER 5,
saved and put back with the other render settings) -- not yet run against a live Reaper. On the
RENDER page, a token after MIX and STEMS steps the depth; its mark is a wave drawn in coarse steps
(16), fine steps (24) or smooth (32 float), and the cards say which. Each person's own, not saved.
Other file types and sample rates split out as missing. The dither loop is GDScript, a few
seconds' work per minute of stereo after the render plays; fine for now.

## DAW parity, iteration 16: regions, first part (2026-10-14)
`MixState.regions` ([start, end, name], in order of starts) and `region_at`; `DAW.add_region` and
`DAW.remove_region`, each one undo step, a guest's ask refused when empty, endless or malformed.
On the wire as `/timeline/regions`, led by a count, so removing the last region still says so
(an empty `/timeline/markers` was dropped by `_apply_timeline`: fixed in iteration 17.) Saved
through dawkit's new `DawKitRegion` (72713ac, submodule bumped), in the plain form and in a
dawproject's extras, since DAWproject has no regions. Reaper: the bridge's GetTimeline now lists
regions apart from markers, and `AddRegion`/`RemoveRegion` make and delete them -- not yet run
against a live Reaper. A REGION page on the deck: ADD makes the loop range a region, named for
the marker at its start or "Region N"; LOOP loops the region the playhead is in; REMOVE takes it
away. Regions are drawn as slabs in the ruler's loop band, behind the loop bar, names at left.
Split out as missing: rename, move and resize, render a region, the region list.

## DAW parity, iteration 17: humanise; the last marker (2026-10-14)
`DAW.humanise_item(track, item, seconds, velocity)`: every note of a MIDI item moved up to
`seconds` either way (not before the item's start, keeping its length) and its velocity changed
up to `velocity`, triangular, held to `HUMANISE_SECONDS_MAX`/`HUMANISE_VELOCITY_MAX` (0.1 s, 40).
Seeded from the notes, so the host's edit is one answer and a second press is a different one.
Refused for a locked item. Reaper's `HumaniseItem` in the bridge rolls its own dice; the preview
is a likeness until the next timeline -- not yet run against a live Reaper. A HUMANISE token
(notes on a grid, each off its line) after HARDER on the ITEM page: 15 ms and 8 a press, 35 ms
and 20 fine. Suite 10132 checks, 0 failed; probe 0 failed.

Also: an empty `/timeline/markers` was ignored, so removing the last marker never reached a guest,
a snapshot left markers out when there were none, and Reaper reporting none left the cache's old
ones in place. Now an empty list is no markers, and the snapshot always carries them.

## DAW parity, iteration 18: item reverse (2026-10-14)
`DAW.set_item_reversed` and `MixState.ItemState.reversed`, one undo step, refused for a locked,
MIDI or looped item. A reversed item's `source_offset` is seconds into the reversed sound, so a
split, trim or move of one is the same arithmetic as of a forward one; reversing turns the offset
round (file length - offset - length) and the item's overview with it, so it is drawn as it
sounds. The file's length is the engine's to the sample (`GodotBackend.source_seconds`), else the
overview's to a fiftieth. The built-in engine plays `take_stream(source, true)`: the take's frames
in the other order, cached; stereo 16-bit (a take) as int32 words reversed at once, other 8/16-bit
layouts frame by frame; a compressed stream (IMA ADPCM, QOA) cannot be, and plays nothing.
On the wire in the item's optional dictionary; saved in dawkit's `DawKitClip.reversed` (5fbd49c,
submodule bumped), which also now keeps a clip's lock through a dawproject file -- it was lost
there before. Reaper: the bridge reports a reversed take (PCM_Source_GetSectionInfo, its file
from the section's parent) and `SetItemReversed` runs Toggle take reverse (41051) on the item
alone, putting the selection back after. Whether Reaper's D_STARTOFFS on a reversed take is in
reversed time, as this assumes, is unchecked -- not yet run against a live Reaper.
A REVERSE token (a swell and an arrow back along it) beside LOCK on the ITEM page.
Known: a project loaded from a file gave its audio items no overview (peaks): fixed in iteration 19.

## DAW parity, iteration 19: a reopened project's takes are drawn (2026-10-14)
A project opened from a file gave every audio item -- recorded takes, and the demo's parts, which
a save writes out as looped files -- an empty overview, so they drew as blank blocks. `ProjectBridge.load`
now reads each file's overview once (`AudioTake.overview_of`: dawkit reads the file, its peaks at
the take's 50 a second; about a quarter of a second a stereo minute) and gives it to every item
that plays the file, turned round for a reversed one. The cache (`take_peaks`) is emptied at the
start of a load, since another project's takes may share a file name. A sidecar file of the
overview (Reaper's .reapeaks) was tried and dropped: an opened project's media is unpacked fresh
each time, so it would never be found again, and the scan is quick.
A looped item's waveform now comes round again with its loop (`wave_columns` takes the loop's
range), so a demo part reopened as a two-bar file looped over eight draws the whole way along,
not just its first pass. And the stand-in host (OfflineBackend) can save: `ProjectFiles.save`
asked it for `parts_signature`, which only GodotBackend had, so it moved down to OfflineBackend.
`tools/screenshot.gd --reopen` saves and reopens the project at frame 5, to look at it.
Suite: 10164 checks, 0 failed.

## DAW parity, iteration 20: ripple move and ripple trim (2026-10-14)
`DAW.ripple_move_item` and `DAW.ripple_trim_item`: the item moved or trimmed, and every unlocked
item on its track from where it was (a move) or from its old end (a trim) carried along by as
much -- Reaper's ripple per track, Pro Tools' shuffle. A trim of the left edge leaves its end, so
nothing follows. Locked items stay where they are, a locked item refuses the edit, and a ripple
that changes nothing is not history; one undo step each. Item edits, so a guest asks for them
the same way and the host checks them. A RIPPLE toggle on the timeline's tools (a train of blocks
over an arrow, lit while on) is each player's own, not saved and not on the wire, like the grid:
while it is on, a drag along the lane or an edge trim lands as a ripple edit; a drag onto another
track still moves the item alone. Reaper: `MoveItem` and `TrimItem` take a fifth ripple argument
in the bridge, not yet run against a live Reaper.
Still to do: the drag preview shows only the item moving, not what follows; ripple across all
tracks (Reaper's other mode) is not offered.
Suite: 10180 checks, 0 failed; probe host 53, guest 47, 0 failed.

## DAW parity, iteration 21: autosave (2026-10-14)
The host's engine (OfflineBackend, so the built-in engine and the stand-in) keeps a copy of the
project once there is work no save has kept: `autosave_every` seconds (300) after the first
unsaved change it writes `user://autosave/<project>.dawproject` through `ProjectFiles.save` with
the new `copy` flag, which leaves the project's own file, path and unsaved state alone -- only a
save writes the file you chose. It waits while the transport runs, so a save's pause never lands
in a take; nothing new since the last copy, nothing written. Host only, nothing on the wire: a
guest's work is in the host's project. The SAVE token's card says "copy kept N min ago". The
suite sets `autosave_every` to 0 so a ten-minute run writes none; `tools/screenshot.gd
--autosave` stops the song, edits and keeps one at once. Reaper keeps its own (its autosave
preferences), so the bridge does nothing.
Split out, still missing: crash recovery, offering the copy at start when it is newer than the
project; and more than one copy kept (Reaper's timestamped backups).
Suite: 10192 checks, 0 failed. Host only and nothing on the wire, so no probe.

## DAW parity, iteration 22: crash recovery (2026-10-14)
`OfflineBackend.recoverable()`: the autosave copy of the open project when an earlier run left one
newer than the project's own file (or the project has no file yet), and not a copy this run wrote
or has already recovered. `recover()` opens it in the project's place, keeps the project's own
path (a save writes the project, not the copy) and leaves it unsaved, since what came back is in
no file of its own yet. `DAW.recoverable_copy` / `DAW.recover_autosave` are the host's; a guest is
offered nothing, since the project is the host's to replace. A PROJECT RECOVER token beside SAVE
(the save's tray with an arrow coming back up out of it) is lit and in reach only while there is
a copy to offer; its card says when the copy was kept. Relit when a project is opened or saved.
`tools/screenshot.gd --recover` leaves a copy to offer.
A copy left by a run that ended without saving on purpose is offered too, as Reaper's would be:
it is an offer, and it changes nothing until pressed.
Suite: 10205 checks, 0 failed. Host only, nothing on the wire.

## DAW parity, iteration 23: normalise on render (2026-10-14)
`DAW.render(stems, bits, normalise)`: normalised, the mix is brought to a peak of
`DAWBackend.RENDER_NORMALISE_DB` (-1 dBFS, room for a lossy encoder's overshoot), up when quiet
and down when over full scale, and every stem moves by the mix's gain, so the stems still add up
to the mix (Reaper's "normalize stems to master"). The built-in engine already holds every frame
before it writes (MixRender), so the gain is worked out there (`MixRender.normalise_gain`); a
real render in the suite comes out at -1.00 dB. The guest's ask carries a third word; an ask
without it is a plain render. A RENDER NORMALISE toggle on the RENDER page (the existing
normalise mark), each person's own like the depth, sent with their render; MIX's card says so.
Reaper: RenderProject takes args 6 and 7 and sets RENDER_NORMALIZE to peak mode with stems by the
master (1 + 4 + 32) and RENDER_NORMALIZE_TARGET, putting both back after -- not yet run against a
live Reaper.
Re-marked from the code: rendering a region is there already (LOOP on the REGION page sets the
loop range, which a render follows), so it moved off the regions item.
Suite: 10214 checks, 0 failed; probe host 53, guest 47, 0 failed.

## DAW parity, iteration 24: duplicate track (2026-10-14)
Not on the checklist, and among the most-used edits anywhere: added and done. `DAW.duplicate_track`
puts a copy of a track right after it, as Reaper's Track: Duplicate tracks does: the same name and
colour, level and pan, its effects and their settings, its sends, items and automation lanes
(`DAWBackend._locally_copy_track`, through the snapshot, so the copy is whatever a guest would read
of the original), the demo part it plays, and an instrument a project gave it. Not armed, nothing
selected. A folder's last track hands the folder's end to its copy, so the copy stays inside. One
undo step; a guest asks for it like remove_track, and gets the new structure as a snapshot. The
built-in engine rebuilds once, with the effects laid on the copy's bus (`_renumber` can now leave
the rebuild to its caller). A TRACKS DUPLICATE token on the TRACK page (two gems), lit with a
track picked; the copy is picked after. Reaper: DuplicateTrack in the bridge runs 40062 on that
track alone and puts the selection back, not yet run against a live Reaper.
Checklist extended with three more editing items found missing: fade shapes and equal-power
crossfades, nudging by the grid, and glue.
Suite: 10233 checks, 0 failed; probe host 53, guest 47, 0 failed.

## DAW parity, iteration 25: nudge the selection by the grid (2026-10-14)
`DAW.nudge_selected(amount, unit)`: every selected, unlocked item moved by seconds, beats or bars
(`DAWBackend.NUDGE_SECONDS/BEATS/BARS`), along the tempo map from where each one starts, so a
beat is a beat wherever the tempo changes; none before the song's start; one undo step, none
when nothing moves. A guest asks for it with the amount and the unit, checked by the host.
NUDGE EARLIER and NUDGE LATER on the ITEM page (a block with a step the way it goes) step by the
person's grid (`TimelineItemPage.nudge_step`: a bar, a beat, half or a quarter of one), ten
milliseconds with no grid or held fine; lit while anything unlocked is selected. Reaper: the desk
works out each item's new start and `NudgeItems` in the bridge moves each selected item by its
track and old start -- not yet run against a live Reaper.
The screenshot caught the two marks pointing the wrong way round; fixed before the commit.
Suite: 10249 checks, 0 failed; probe host 53, guest 47, 0 failed.

## DAW parity, iteration 26: equal-power fades (2026-10-14)
dawkit's native lane already played a `fade_shape` (0 straight, 1 a quarter sine) that nothing
set, so no native rebuild: dawkit a08b20c adds `DawKitClip.fade_shape` (FADE_LINEAR,
FADE_EQUAL_POWER) to the clip's plain form and keeps it through a dawproject file beside lock and
reverse. The game: `MixState.ItemState.fade_shape`, on the wire in the item's extras, given to
the lane (`LaneEngine`), saved and opened through ProjectBridge, kept by both halves of a split;
`level_db` follows it, so the waveform's fade is the one heard. `DAW.set_item_fade_shape`, an
item edit (one undo step, none when already so, refused on a locked item; a guest's odd shape is a
straight one). The arrangement draws an equal-power fade as a quarter sine in five pieces
(`TimelineSurface.fade_points`). A FADE SHAPE token on the ITEM page after the fade rails, its mark
the shape the item has, lit when equal-power. Reaper: SetItemFadeShape writes C_FADEINSHAPE and
C_FADEOUTSHAPE 1, the timeline reads shape 1 back -- whether Reaper's shape 1 is its equal-power
curve is unchecked against a live Reaper. `tools/screenshot.gd --tl-fade T:I:S[:shape]`.
Split out, still missing: other shapes, a shape per end, and CROSSFADE choosing equal power
itself (it is still two plain fade edits).
Suite: 10270 checks, 0 failed; probe host 53, guest 47, 0 failed; dawkit 371 checks, 0 failed.

## DAW parity, iteration 27: equal-power crossfades, one edit (2026-10-14)
CROSSFADE was two `set_item_fades` edits (two undo steps) of straight fades, which dip a
crossfade of unrelated sound by 3 dB in its middle. Now `DAW.crossfade_items` is one item edit,
`crossfade_items` on the backend: the earlier item faded out and the later in over the overlap,
both equal-power (the shape is the item's, so its other end's fade becomes equal-power too, until
there is a shape per end). The two levels' powers add to one across it, which the suite checks
halfway. Refused with either item locked, by the desk and by the host for a guest's ask
(`DAWBackend.crossfade_of` works out which is earlier and the overlap for both). Reaper:
CrossfadeItems in the bridge sets both lengths and shape 1 at both ends of both in one undo point
-- not yet run against a live Reaper. `tools/screenshot.gd --tl-xfade T:I` copies an item to
halfway along itself and crossfades the two; the shot shows two bowed lines crossing.
Suite: 10278 checks, 0 failed; probe host 53, guest 47, 0 failed.

## DAW parity, iteration 28: jump through the undo history (2026-10-14)
A HISTORY rail (clock glyph) sits after REDO on the timeline tools. Its bead is where the history
is now, from the start to the last step there is to redo; letting go somewhere else jumps there in
one go (`DAW.undo_to(depth)`, undos or redos repeated on the host, a guest's ask sanitised by
`apply_intent`). Its card names the step a place goes back or forward to, "Kick: move item",
"add marker": `DAW._call` sets `backend.acting` from `DAW.step_name(verb, args)` around each edit,
and the offline backend keeps that name on the step (falling back to its key). "/undo" now carries
the names after the two depths, so a guest's card reads the same. Dim with no history. Reaper:
`undo_to` repeats Undo/Redo from the bridge's depth, and Reaper's own step names are not read, so
the card there says "step N" -- not yet run against a live Reaper.
Suite: 10295 checks, 0 failed; probe host 53, guest 47, 0 failed.

## DAW parity, iteration 29: glue items (2026-10-14)
GLUE on the ITEM page makes the selected items of each track one item (`DAW.glue_selected`, one
undo step, a guest's ask taken with no arguments). `DAWBackend.glue_picks` decides what glues
without a new file: two or more unlocked items that are all MIDI -- notes kept where each part
played them, a note cut at a part's end staying cut, gaps silent -- or all cuts of one recording
that follow on from each other on the track and in the file, as a split leaves them (rejoining a
split). None looped or reversed, all at one gain. The glued item starts where the first did and
takes the last one's fade-out. The token is in reach with two selected and lit when they glue;
its card says why when they do not. Left: gluing audio that is not one file played straight
through needs a bounce to a new file -- the built-in engine renders the mix and stems but not
an item range of a track into a take; that is the next part. Reaper: GlueSelected deselects
locked items and runs Item: Glue items (40362), which glues anything; not yet run against a live
Reaper.
Suite: 10309 checks, 0 failed; probe host 53, guest 47, 0 failed.

## DAW parity, iteration 30: a fade shape per end, and slow, fast and S-curve (2026-10-14)
dawkit daf3027: `DawKitClip.fade_out_shape` beside `fade_shape` (now the fade in's), and shapes
FADE_SLOW (a square), FADE_FAST (an upturned one) and FADE_S_CURVE (half a cosine) after straight
and equal power, with `DawKitClip.fade_gain(t, shape)` the one curve everything draws and hears
by and `clean_shape` for files and peers. A clip saved with one shape has it at both ends. The
native lane plays each end in its own shape (rebuilt for linux, windows and android). In the
game `ItemState.fade_out_shape` goes over the wire only when it differs from the fade in's,
through the lane engine, the project, a split's right half, glue (the last part's) and
`level_db`. `set_item_fade_shape` takes both shapes (a guest's ask needs both; odd ones are
straight). CROSSFADE now shapes only the two ends that cross. The ITEM page's one FADE SHAPE
token is two, one after each fade rail, each marked with its curve (rising or falling;
`TimelineGlyph.fade_glyph`), a press the next shape round, the card naming this one and the
next. Reaper: the bridge maps the desk's 0-4 to Reaper's 0, 1, 2, 3, 5 each way, per end, and
CrossfadeItems sets only the crossing ends -- not yet run against a live Reaper.
`tools/screenshot.gd --tl-fade T:I:S:in/out` shapes the two ends apart.
Suite: 10322 checks, 0 failed; dawkit 374; probe host 53, guest 47, 0 failed.

## DAW parity, iteration 31: regions renamed, moved and resized, and listed (2026-10-14)
`DAW.edit_region(at, start, end, name)`: the region starting at `at` made a new span and name in
one undo step, nothing when there is none there, onto another's start replacing it as ADD does
(`DAWBackend.regions_edited`); a guest's ask refused when empty, endless or malformed. The
REGION page gains NAME (the region the playhead is in, named on the monitor or, in a headset, on
the keypad: `TimelineSurface.ask_region_name`, sharing `_ask_name` with the track's), FIT (that
region moved and resized to the loop range; dark once it is), and GO TO, a rail with a place
for each region in order, its card naming one ("Chorus, 17.1.00 - 25.1.00, 3 of 3"), letting
go there seeking to its start. The bead follows the playhead from region to region as the song
plays. Reaper: EditRegion finds the region by its start, removes any other starting where it
goes, and SetProjectMarker moves and renames it, one undo point -- not yet run against a live
Reaper. Reaper keeps a name unchanged when given an empty one; the desk never sends one.
Suite: 10343 checks, 0 failed; probe host 53, guest 47, 0 failed.

## DAW parity, iteration 32: track groups (2026-10-14)
dawkit 248df69: `DawKitTrack.group` (0 none, 1 and up), kept in its own file and a dawproject's
extras. In the game `TrackState.group`, `/track/N/group` (always in a snapshot, none too, as a
renumbering resends the mix onto tracks a guest already has), saved, carried by a duplicate.
`DAW.set_track_group` is one undo step; a guest's ask clamped to DAW.GROUPS (4). The linking is
the desk's, in `DAW`: `set_track_volume` on a grouped track moves each of `group_mates` by the
same decibels, worked out from the faders' positions (which every peer has; a guest's cache has
no `volume_db` from the built-in engine), each as its own move, so a guest's drag is the intents
the host's would be; all the way down takes the group down. `set_track_mute` / `set_track_solo`
set the whole group. Everything that moves a fader through `DAW` -- the desk's strips, the
tablet -- links; automation playback does not (each track's lane is its own). GROUP on the
TRACK page steps the picked track through the groups and out, lit in the group's colour, its
card naming its mates. The page now refreshes when the picked track's group changes. Reaper:
the desk does the linking, so it works there too, but the groups are kept by the desk, not in
Reaper's project (Reaper's own groups are per-parameter flag bits the bridge does not read).
Split off: VCA faders, and overriding a group for one move. `tools/screenshot.gd --tl-group
T:G,...` groups tracks for a shot.
Suite: 10360 checks, 0 failed; dawkit 375; probe host 53, guest 47, 0 failed.

## 2026-10-14 -- iteration 33: per-note velocity

`DAW.set_note_velocity(track, item, note_index, velocity)`: one note of a MIDI item given its own
velocity (1-127), one undo step, a no-op when it already has it. An ITEM_EDITS verb of 4 args;
a guest's index is clamped to -1..MAX_NOTES and the backend refuses one that is not a note;
refused for a locked item. NOTE VELOCITY on the ITEM page is a rail (a tall brick among low
ones) that edits the note sounding at the playhead, else the next to start (`DAWBackend.note_near`):
move the playhead to pick the note, let go of the rail to set it; it follows the note's velocity
as the playhead moves. Reaper: `SetNoteVelocity` in the bridge finds the note by start time and
pitch (Reaper's own indices skip muted notes); not run against a live Reaper.
Split off: CC / pitch-bend lanes, legato; picking a note by touching it in the item.
Suite: 10371 checks, 0 failed; dawkit 375; probe host 53, guest 47, 0 failed.

## 2026-10-14 -- iteration 34: earlier autosave copies

Each autosave now pushes the earlier copies back one place first (`Name.1.dawproject` ...
`Name.4.dawproject`, `OfflineBackend.AUTOSAVE_KEEP`) before writing the newest, the oldest falling
off; Reaper's timestamped backups, by count. `autosave_history()` lists them newest first;
`recover(generation)` / `DAW.recover_autosave(generation)` open an older one. Host-only and
local, nothing on the wire. The RECOVER token still offers the newest only: a way to choose an
older copy from the deck is the next piece, not done.
Suite: 10376 checks, 0 failed; dawkit 375.

## 2026-10-14 -- iteration 35: the audio-device patchbay wall, part 1

Asked for: a Carla-style patchbay for the audio devices, on a huge screen in a side room.
Split in three; this is the first.
1. DONE -- `PipeGraph` (core/audio/pipe_graph.gd) reads the machine's PipeWire graph from
   `pw-link -o/-i/-l` (nodes, ports, links), and can `link`/`unlink` ports. `PatchWallSurface`
   (hardware/patchbay) draws it: a box per node with a header in the venue's palette
   (`TrackColours.palette()`), ports down the left (outputs) and right (inputs), a bright curved
   ribbon per link, a frame of the venue's trim; ports in use lit, the rest dimmed. Re-asked
   every 2 s on a thread; redrawn only when the graph or the venue's dress changes. Capped at
   16 port rows a column, the rest counted. `tools/screenshot.gd --patch-wall` hangs one for a shot.
2. NEXT -- mount it: a big screen on the studio's side room wall (`StudioVenue` BESIDE variant),
   registered with the SurfaceMount / focus rig, a stand-in room for the other variants.
3. NEXT -- make and break links: drag a cable from an output jack to an input jack, tap a cable
   to cut it (`PipeGraph.link/unlink`); pick a node to see more than 16 rows.
Not multiplayer state: a PipeWire graph is the machine's own. Each player's wall shows their own
devices, and nothing is sent. Linux only (needs `pw-link`); elsewhere it says there is no graph.
Suite: 10391 checks, 0 failed.

## 2026-10-14 -- iteration 36: the patch wall in the side room (part 2)

`StudioVenue._hang_patch_wall`: a `PatchWallSurface` on the back wall of the BESIDE arrangement's
side room, facing in, top at 3.75 m (the room is 4 m), 5.2 m wide in a 5.9 m room. The wall
took the place of the two acoustic panels on that back wall, and the walkway sconce moved to the
front wall. Made larger after "text is tiny": 12 port rows a column, 5-6 cm lettering. Polls
the machine's graph only where it is visible, five times slower while there is none, and never in
a headless run. Other arrangements and venues have no wall yet. Part 3 is still to do: patching
by hand (drag from jack to jack, tap a cable to cut it). `--no-timeline` hides the timeline for a shot.
Suite: 10393 checks, 0 failed.

2026-10-14, after: the timeline is no longer pinned to the camera by default on a monitor
(`Presentation.default_mode` is STUDIO for every surface in every medium): it stands in the room
on its stand with the rest of the gear, and the SCREEN handle still puts it on the glass. Escape
now puts a screened timeline back on its stand too, as it does the rack. A focused surface leaves
a berth for all five room surfaces. The side room's back corner bass traps and back-wall panels
are gone, for the patch wall. Suite: 10394 checks, 0 failed.

## 2026-10-14 -- iteration 37: the patch wall patches (part 3)

Each port on the wall is a `PatchJack` (a ControlAffordance, the whole row the target): press on
one and a ribbon follows the hand, the ports of the other kind light (patched ones red: letting go
there cuts that cable); let go on one to `pw-link` the two (output first, whichever the hand began
on) or `pw-link -d` them; on its own kind or on nothing, nothing happens. The footer says what was
done or that it could not be, and the graph is read again at once. Machine-local like the rest of
the wall: a player's hands edit their own PipeWire graph and nothing is sent. Not done: hold a
node to see more than 12 ports, tap a cable (rather than its ports) to cut it, patching on
systems without `pw-link`. Suite: 10401 checks, 0 failed.

## 2026-10-14 -- iteration 38: legato

A LEGATO key on the ITEM page (three bricks end to end, NOTE group) makes each note of a MIDI item
end where the next later-starting note, of any pitch, begins: a chord's notes run to the same
place, overlapping notes are cut back, the last note keeps its length. `DAW.legato_item` is an
ITEM_EDITS intent (host authority, undoable, refused on locked items); Reaper's bridge has a
`LegatoItem` handler (syntax-checked, not run against a live Reaper). Suite: 10415 checks, 0 failed.

## 2026-10-14 -- iteration 39: staccato

A STACCATO key beside LEGATO on the ITEM page (four short bricks with gaps) cuts every note of a
MIDI item to half its length (never below `MidiTake.MIN_NOTE`). `DAW.staccato_item` is an
ITEM_EDITS intent, undoable and refused on locked items; Reaper's bridge has a `StaccatoItem`
handler (syntax-checked, not run against a live Reaper). Session probe not run: it is the same
intent shape as legato. Suite: 10420 checks, 0 failed.

## 2026-10-14 -- iteration 40: even velocity

An EVEN key on the ITEM page (level bars under a line) gives every note of a MIDI item the rounded
average of their velocities. `DAW.even_velocity` is an ITEM_EDITS intent, undoable, refused on
locked items, a no-op when the notes already agree; Reaper's `EvenVelocity` handler is
syntax-checked, not run live. Probe not run (same intent shape as legato). Seen while shooting:
the known teardown SCRIPT ERROR from `scenes/studio.gd`'s `_remember_tablets` appeared in the shot
run (see iteration 11's note); not from this change. Suite: 10425 checks, 0 failed.

## 2026-10-14 -- iteration 41: select a track's items

A SELECT ITEMS key on the TRACK page (a gem beside two lit blocks) selects every item on the picked
track and clears every other track's selection (Reaper's select-all-in-track). `DAW.select_track_items`
is a plain intent (index sanitised in `apply_intent`, unknown track ignored); Reaper's
`SelectTrackItems` handler is syntax-checked, not run live. Probe: host 53, guest 47, 0 failed.
Suite: 10432 checks, 0 failed.

## 2026-10-14 -- iteration 42: rename an item

A NAME key on the ITEM page (a block with a label strip) opens the keypad (or the monitor's name
prompt) for the one selected item. `DAW.rename_item` is an intent with a string, sanitised in
`apply_intent` (index, type, 64-character cut), one undo step; a locked item may still be named. The
name rides the existing item wire and is saved as the dawkit clip's name. Reaper's `RenameItem`
sets the active take's P_NAME (syntax-checked, not run live). The key is not drawn lit/active for
several items: it renames one. Probe: host 53, guest 47, 0 failed. Suite: 10440 checks, 0 failed.

## 2026-10-14 -- iteration 43: render sample rate

A SAMPLE RATE token on the RENDER page (a row of ticks, closer for a higher rate) steps 48 -> 96 -> 44.1 kHz,
each person's own, sent with their render as a fourth argument of `DAW.render`; the host takes a rate
that is not one of `RENDER_RATES` as 48 kHz, like a bad depth. The built-in render captures at the
engine's rate and `MixRender` resamples each file with `Resampler` (linear: fine for the rates here,
but no anti-alias filter on the way down to 44.1 -- a sinc resampler would be the next step, an
engine limit worth noting). Reaper sets RENDER_SRATE through the bridge (syntax-checked, not run
live). Also `--tl-render` for tools/screenshot.gd. Probe: host 53, guest 47, 0 failed (one click-timing check failed on a first run, unrelated, clean on the rerun). Suite: 10448 checks, 0 failed.

## 2026-10-14 -- iteration 44: notes backwards

A key on the ITEM page (bricks stepping down, an arrow back along them) mirrors a MIDI item's notes
in time about the middle of the item: the last note plays first, each keeping its length and
velocity, kept inside the item. `DAW.retrograde_item` is an ITEM_EDITS intent (undoable, refused on
locked items); pressed twice it is as played. Reaper's `RetrogradeItem` mirrors the PPQ about the
item's ends (syntax-checked, not run live). Probe not run (the same intent shape as legato).
Suite: 10453 checks, 0 failed.

## 2026-10-14 -- iteration 45: delete a note

A red crossed-brick key on the ITEM page takes out the note sounding at the playhead (lit only
while one does; a locked item keeps its notes). `DAW.delete_note` is an ITEM_EDITS intent (the note
index clamped in `apply_intent`, undoable, refused on locked items, a missing note no edit). Reaper's
`DeleteNote` finds it by start and pitch like the velocity edit (syntax-checked, not run live). The
piano roll is still read-only on the wire beyond this: no insert-a-note or move-a-note verb yet
(notes come in through takes). Probe: host 53, guest 47, 0 failed. Suite: 10459 checks, 0 failed.

## 2026-10-14 -- iteration 46: move one note in pitch

NOTE UP and NOTE DOWN on the ITEM page (a brick with a point over or under it) move the note
sounding at the playhead a semitone, or an octave with fine, kept within 0-127. They light with
DELETE NOTE, while a note sounds. `DAW.transpose_note` is an ITEM_EDITS intent (note index and step
clamped in `apply_intent`, undoable, refused on locked items, no move at the range's end is no
edit). Reaper's `TransposeNote` finds the note by start and pitch (syntax-checked, not run live).
Still no insert-a-note or move-in-time verb. Suite: 10466 checks, 0 failed.

## 2026-10-14 -- iteration 47: add a note

ADD NOTE on the ITEM page (a brick and a plus, green) puts a note a beat long into the MIDI item at
the playhead, at the pitch of the note beside it (60 for an empty item) and velocity 100, then
NOTE UP / DOWN and the velocity rail shape it. Lit while the playhead is inside the item.
`DAW.insert_note` is an ITEM_EDITS intent `[track, item, on, off, pitch]` (start and end in seconds
from the item's start, sanitised and clipped to the item in `apply_intent` and the backend; a start
at or past the end, a recorded-audio item, or MAX_NOTES notes refuse it). Reaper's `InsertNote` uses
MIDI_InsertNote on the first MIDI take (syntax-checked, not run live). Still no move-a-note-in-time
or resize-a-note verb. Probe: host 53, guest 47, 0 failed. Suite: 10472 checks, 0 failed.

## 2026-10-14 -- iteration 48: a note ends at the playhead

NOTE ENDS HERE on the ITEM page (a brick cut at a line) makes the note sounding at the playhead end
there. `DAW.set_note_end` is an ITEM_EDITS intent `[track, item, note, off]` (off in seconds from the
item's start; clamped between a note's minimum length after its start and the item's end, index
clamped in `apply_intent`, undoable, refused on locked items). It only lights while a note sounds,
so it cuts; the verb itself also lengthens (a later hand or rail could use it). Reaper's `SetNoteEnd`
finds the note by start and pitch (syntax-checked, not run live). The ITEM page's NOTE row now
wraps onto a second line. Still no move-a-note-in-time. Probe: host 53, guest 47, 0 failed.
Suite: 10479 checks, 0 failed.

## 2026-10-14 -- iteration 49: move a note in time

NOTE EARLIER and NOTE LATER on the ITEM page (a brick with an arrow along it) move the note
sounding at the playhead by a sixteenth of a beat, or a beat with fine, its length kept and held
inside the item. `DAW.move_note` is an ITEM_EDITS intent `[track, item, note, by]` (index and
distance clamped in `apply_intent`, undoable, refused on locked items, a move that cannot happen is
no edit). Reaper's `MoveNote` is told the distance really moved, after the hold (syntax-checked, not
run live). The piano roll now has per-note insert, delete, pitch, length, time and velocity from the
ITEM page; still missing are CC and pitch-bend lanes. Probe: host 53, guest 47, 0 failed.
Suite: 10486 checks, 0 failed.

## 2026-10-14 -- iteration 50: choose which autosave to recover

A fine press on RECOVER (the hand held steady) steps the choice back through the kept copies, round
to the newest; a plain press opens the chosen one in the project's place and the choice returns to
the newest. The hover card says "copy N of M, kept at hh:mm". `DAW.autosave_copies()` lists the host's
copies; no wire change (recovery is the host's own). README gained a short section on the deck.
Probe: host 53, guest 47, 0 failed. Suite: 10491 checks, 0 failed. The loop's 50 iterations are done.


## 2026-10-14 -- the patch wall in every venue

Asked for: the patchbay in every venue. Where a venue hangs one (the studio's side room) that is the
wall; every other venue and arrangement now gets a `PatchWall` on two legs by the control room's left
wall, 0.55 scale, facing the desk (`Studio._stand_a_patch_wall`). Not checked against each venue's
furniture: it may stand in something in a venue whose left side is busy.

Reaper's own plugins' UI (ReaEQ etc.), tried and not working: plain XSendEvent clicks are ignored
(GTK, XI2) and XTest clicks, with the window moved so the clicked point sat under the pointer,
changed nothing either; the X pointer is also confined to the monitors' rectangles under XWayland. The
reparented window is `Withdrawn` with no window manager, so GTK may not even repaint it. Untried: a
WM-less nested server cannot hold Reaper's windows; drawing ReaEQ's graph natively from its band
parameters is the way left. The UI button stays hidden for "(Cockos)" and "JS:" plugins.

## 2026-10-14 -- Reaper's own plugins' windows work from the tablet

ReaEQ, ReaComp and JSFX windows now take the tablet's clicks, drags and wheel, so their UI button is
back. Three things stood in the way, found by poking ReaEQ from a script (open it through the
bridge, send clicks through the helper, diff the pictures) and reading SWELL's and GDK 3's source:

1. GDK reads the pointer through XInput2, so it ignores the core events a client can send.
   `GDK_CORE_DEVICE_EVENTS=1` fixes that.
2. GDK drops a press unless an Enter came first, and SWELL turns a click's screen position back
   into a point using wherever the window last heard it was. plugin_view now sends an Enter once,
   and sends a synthetic ConfigureNotify with the window's real position. It re-sends that whenever
   the compositor moves the holder. Telling a fixed spot instead broke Gojira under Wine, which is
   told the same thing through yabridge.
3. A drag asks where the pointer is (`gdk_display_get_pointer`) and gets the real one. SWELL also
   asks for motion hints, which drop sent motions, and it pulls events with `gdk_event_get` as
   well as the handler. A knob hides the cursor and warps it back, which would move the real
   pointer.

`native/reaper_pointer.c` is preloaded into Reaper and handles all three: it sets the env var,
answers pointer questions from the sent events while they arrive, turns warps into an offset, and
strips the hint mask. A real pointer event puts everything back. The rig builds and preloads it.
Your own Reaper needs `LD_PRELOAD=.../reaper_pointer.so reaper`. Without the library the button
stays hidden for "(Cockos)" and JS plugins, which `DAW.works_own_plugin_windows` checks through
/proc. The JS check never matched before this, because names lose their "JS: " prefix on the way
in; `FXState.type` now keeps it.

Verified on the rig: in ReaEQ, a tab click, a band node drag, the gain slider drag and the Show
phase checkbox all work, and the real cursor stays put. The Gojira probe passes 36/36.
Not handled: a plugin's popup menus and dropdowns open as windows of their own, which the tablet
does not show.

## Audio-reactive venues (loop)

Shared helper: `Venue.hear(level)` (attack/release smoothing as `heard`, rise flash as `heard_hit`,
exactly 0 at rest). Off with `reactive = false` (tied to `--no-motion`). `--feed-level F` fixes the
level for screenshots.

Already reactive: cave, chalk, stage, club, greenhouse, desert, grid, garden.

- [x] rooftop: festoon bulbs and string spots swell, city windows breathe, skylight glows, the
  lattice's chalked square is a violet blacklight, and gold/violet sparks fall under the strings.
  Shots: shots/rooftop_floor_0.png (quiet), shots/rooftop_floor_0.9.png (loud).
- [x] loft (all three arrangements): pendant bulbs and pools and the gallery festoon swell, city
  windows breathe, the lattice's safety-yellow paint fluoresces lime under a violet blacklight that
  comes up with the music, and lime/violet sparks lift off the square.
  Shots: shots/loft_night_0.png (quiet), shots/loft_night_0.9.png (loud).
  Shared `Venue.make_sparks` / `drive_sparks` now back both rooftop and loft.
- [x] cabin (all three): stove glass, stove and candle lights, candle flames and lanterns swell
  and flash; the rug's cream border fluoresces blue-white under a violet blacklight; embers rise
  off a lit stove and motes lift over the rug. Shots: shots/cabin_night_0.png (quiet),
  shots/cabin_night_0.9.png (loud).
- [x] station (all three): cove strips, deck lip and riser edge swell, the lip shifting cyan toward
  violet as it gets loud, downlights and the planet's up-glow lift, the dust brightens, the sky
  energy breathes, and a violet blacklight over the lattice kicks weightless cyan/violet motes up.
  Shots: shots/station_night_0.png (quiet), shots/station_night_0.9.png (loud).
- [ ] dome, studio
