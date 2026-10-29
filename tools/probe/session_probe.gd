extends Node
## Two processes, one session, every promise the session makes checked from both ends.
##
##   tools/session_probe.sh            (starts both halves and reports)
##   godot --headless --path . tools/probe/session_probe.tscn -- --as host|guest [--port N]
##
## Why two processes and not one: a single run is always its own authority, so a field missing
## from the roster, a hold the host never hears of, or a goodbye that never leaves the socket
## all pass there. Both halves run the same timeline and check what they should see at each
## step. Prints PASS/FAIL per check and exits non-zero on any failure.

const KEY := "KICK  VOLUME"
## The duck, carried by the guest: a hold for as long as it is in the hand.
const DUCK := "RUBBER DUCK"
## Held by the host and taken out of its hand by the guest's.
const PLANE := "PAPER PLANE"
## Where the guest says the duck is, relative to its head.
const DUCK_AT := Transform3D(Basis.IDENTITY, Vector3(-0.2, -0.15, -0.5))
## Not the stand-in's tempo nor the rig's, so arriving at it means the write travelled.
const GUEST_TEMPO := 133.5
## A send level neither the stand-in nor the rig starts at.
const GUEST_SEND := 0.345
const GUEST_MARK := 1.25
## The key the host writes before the harps are strummed, from the playhead's bar: one chord, so
## either half reads the same strings wherever the playhead is in it.
const HARP_KEY := "[D minor: Dm]"
const HARP_STRINGS := [57, 62, 65, 69, 74, 77, 81, 86]
## The track the guest records onto.
const TAKE_TRACK := 7
## The track the guest's microphone records onto, in the same take as its keys.
const AUDIO_TRACK := 8
## Where the guest's files from its own machine go, and from when: a second of tone as a WAV,
## then a FLAC, one after the other.
const SENT_TRACK := 12
## The track the host plugs bell 1 into, for the guest to see in the room.
const PLUG_TRACK := 5
## Cables (docs/spatial_loop.md slice 6): the track the host's keys take down what comes into them,
## the song position the guest's harp strum into the host is played to (a given clock, the
## song not playing), and the chord tones the guest's four shaker hits play on the host's keys:
## D minor's, voiced at Jacks.TRIGGER_CENTRE.
const CABLE_TRACK := 9
const CABLE_SONG := 300.0
const CABLE_TONES := [62, 65, 69, 74]
const SENT_AT := 30.0
## The fifths wheel (docs/spatial_loop.md slice 9): the bar the guest's SET names, well past
## everything else the probe writes or plays at, and what it writes there. Its second bar is C.
const WHEEL_BAR := 420
const WHEEL_INSIDE := "E minor: Em C G D"
## Where the guest's head is in its play space when it travels to the harp (slice 11): off the
## centre, as a person stands, so the probe sees the offset kept.
const TRAVEL_OFFSET := Vector3(0.25, 1.6, -0.15)
## One undo step per gesture (slice 12): the track the guest drags pan and volume on at once,
## inside an edit, where to, what the edit is called, and the track the host moves meanwhile.
const EDIT_TRACK := 6
const EDIT_PAN := 0.2
const EDIT_VOLUME := 0.3
const EDIT_NAME := "Probe: place"
const EDIT_HOST_TRACK := 10
## Controls beside the keys (slice 13): the note the host holds while it bends, and the bend.
const BEND_PITCH := 67
const BEND_VALUE := 4096
## Controls in takes (slice 14): where in the song the guest records a held note it bends with a
## keyboard's wheel at 56.2 s, onto TAKE_TRACK, to a clock of its own; the host finds it there.
const BENT_SONG := 480.0
## The note it holds: not the one the guest's first take left down on purpose (its "hanging"
## note, 67), which the guest lets go of first, so this note's off is its last and rests the wheel.
const BENT_PITCH := 69
## Bend and wobble by tilting (slice 15): where in the song the guest records a keytar note its
## neck hand tips TILT_DEGREES after the press, onto TAKE_TRACK to a clock of its own, and the note.
const TILT_SONG := 520.0
const TILT_PITCH := 72
const TILT_DEGREES := 20.0
## Snapped gently (slice 17): where in the song the guest records two shaker hits onto TAKE_TRACK
## to a clock of its own, each this far (s) before a sixteenth, the first snapped and the second not.
const SNAP_SONG := 560.0
const SNAP_EARLY := 0.02
## The stage table (slice 18): the track whose voice the guest places on a table of its own, by a
## hand, from 57.7, and where to: pan 40 L at -10 dB. The host finds both, as one step.
const STAGE_TRACK := 4
const STAGE_PAN := 0.3
const STAGE_DB := -10.0
## Clap to mute (slice 19): the track the guest's latched clap mutes at 58.2, which the host finds
## toggled at 58.4 and puts back.
const CLAP_TRACK := 6
## Sidechain as a rope (slice 20): the guest drags a rope at 58.5 from ROPE_FROM's knot to ROPE_TO's
## voice on a table of its own (the demo's kick to its bass); the host finds the key send at 58.67.
const ROPE_FROM := 2
const ROPE_TO := 6
## Automation by gesture (slice 22): the track whose fader the guest's write bead rides at 58.74, to a
## clock of its own from BEAD_SONG for BEAD_SECONDS, the song not looping; the host finds the pass
## as its lane at those song positions at 58.85.
const BEAD_TRACK := 13
const BEAD_SONG := 640.0
const BEAD_SECONDS := 1.0
## Clips as cassettes (slice 23): the clip the guest pulls at 58.86, as "clip:<track>:<index>" names
## it; the host mints it and it is in the guest's glove. At 58.9 the host hands the guest one of its
## own; by 58.97 both halves find both cassettes in the guest's hand and their rows the same.
const PULL_TRACK := 2
const PULL_FROM := "clip:2:0"
## A cassette onto a track (slice 24): at 58.99 the guest pastes the host-made cassette it was handed
## (cassette2) onto PASTE_TRACK at PASTE_BAR, by the room's `paste` naming it, its track and its time;
## the host pastes its own row's clip there, and by 59.08 both halves find it, the clip it was but
## for its start and track. The host takes it back at 59.1.
const PASTE_TRACK := 4
const PASTE_BAR := 30.0
## A cassette at the ear (slice 25): at 59.12 the host mints an audio cassette of a file only its own
## media folder has (EAR_FILE, a half second of tone, named for the port); at 59.2 the guest holds it
## to its ear with no file of it, FETCHING, and asks the host once (FileSend.fetch); by 59.32 the copy
## is in its FETCHED folder, byte for byte the host's, and it plays. The host has sent it once by 59.34.
const EAR_SECONDS := 0.5
## Anything can be a sample (slice 26): at 59.36 the guest presses the host's sampler's REC (the
## room's `sampler` [true]); by 59.42 the room's row is the guest. At 59.44 it takes the duck, and at
## 59.48 squeezes it, its hand ringing Foley's take SAMPLE_TAKE. By 59.52 the host has heard that take,
## caught it (its Sampler, as the studio's) as one WAV equal to Foley's stream for it and a sample
## cassette the guest made, and REC is off; by 59.55 the guest has the cassette's row, the room naming
## it, and REC off. The host takes them away at 59.62.
const SAMPLE_TAKE := 3
## A DJ platter (slice 27): at 59.6 the guest takes hold of a platter of its own (as the studio's, on
## the deck's cart), turns it to PLATTER_TURNS, a bar a turn, over 30 ms, holds it still there until
## its speed (read over Platter.SPEED_SPAN) is nothing, and lets go: a drag put down, not a flick, so no
## spin-back, whichever way the playhead it started from is. Its turns are seeks asked of the host,
## SEEK_HZ a second at most, the last always sent, within a SEEK_HZ'th of the turning. At 59.74 the host's
## playhead is there (or just past it, playing on), and the guest asked no more than the rate allows.
const PLATTER_TURNS := 6.0
## A tape reel for undo history (slice 28): at 59.78 the guest turns a history crank of its own (as
## the studio's, on the tape deck's supply reel) back CRANK_NOTCHES, a notch at a time, and leaves it;
## once it has stood SETTLE it asks the host one undo_to (two undos where the host's DAW does not say
## its depth). By 60.12 the host's history is CRANK_NOTCHES back from where it was at 59.76, and the
## guest's copy says so; the host puts it back at 60.14.
const CRANK_NOTCHES := 2
## Sections rearranged (slice 29): at 60.16 the host makes three regions of two bars each from
## ARRANGE_BAR, past everything else the probe writes ("Probe A", "Probe B", "Probe C"), a marker a
## bar and a half in (in B) and a take of its own on HOST_MIDI_TRACK half a bar into C. At 60.24 the
## guest asks the order C A B of its copy of them, the host's other regions where they are; by 60.34
## the host has C at ARRANGE_BAR with the take in it, the marker gone with B, as one step, and the
## guest's copy and the room's notice say so. The host takes all of it back at 60.36.
const ARRANGE_BAR := 460.0
const ARRANGE_NAMES := ["Probe A", "Probe B", "Probe C"]
## Chord bricks (slice 31): at 60.38 the host lays out a section of four bars from BRICK_BAR, past
## the arrangement's ("Probe D", its marker at its start). At 60.42 the guest's MAKE BRICKS asks
## for BRICK_CHORDS in BRICK_KEY onto the ledge (`make`, "ledge:<key>:<chord>"); the host mints them
## from the words alone into its ledge's next slots, and by 60.46 the guest's copy of the room has
## them in a row there. The guest nudges the second to 2 bars (the room's `bricks` ask), and at 60.5,
## the host's row saying so, presses its ledge's row onto the host's section block: the wheel's
## `harmony` ask with that section's bar, ChordBrick.section_ask's. By 60.56 both halves have the
## section's marker bracketed with the row (BRICK_MARKER) and its third bar in F; the host takes all
## of it back at 60.58.
const BRICK_BAR := 480.0
const BRICK_SECTION := "Probe D"
const BRICK_KEY := "A minor"
const BRICK_CHORDS := ["Am", "F", "C"]
const BRICK_MARKER := "Probe D [A minor: Am F - C]"
## Point, mark and listen together (slice 35): from 60.82 the guest points at the song time POINT_AT
## on its ruler (Presence's `ruler:<seconds>`, on the presence stream) and drops a sticky note at
## NOTE_AT (an add_marker intent of NOTE_WORDS, Harmony.note_named). By 60.9 the host has heard the
## point and has the note in its markers, and takes the note back at 60.92.
const POINT_AT := 37.25
const NOTE_AT := 520.0
const NOTE_WORDS := "probe note"
## The EQ wall's spectra (slice 36): from 60.92 to 61.12 the host stands a Spectra, as the studio
## does, measuring SPECTRA_KICK's bands at SPECTRA_KICK_DB and SPECTRA_BASS's at SPECTRA_BASS_DB
## (the rest silent), and sending them on five times a second; by 61.1 the guest has them, within a
## byte's half step, and finds the two clashing where they overlap.
const SPECTRA_KICK := 2
const SPECTRA_BASS := 6
const SPECTRA_KICK_BANDS := [3, 7]
const SPECTRA_BASS_BANDS := [4, 8]
const SPECTRA_KICK_DB := -12.0
const SPECTRA_BASS_DB := -15.0
## Carving the clash (slice 37): at 61.14 the guest stands an EQ wall of its own over the same kick and
## bass, grabs their glow on the bass's side and drags it CARVE_SHARE of EqCarve.PUSH_FULL down,
## holding it until 61.22: an edit, an add_fx of the carving EQ and, once the host's EQ is back on
## the guest, its bands' set_fx_param, intents the host carries out. By 61.26 the host's bass ends
## its chain with the EQ, on the built-in engine its bands in the clash cut CARVE_DB, one step named
## for the carve, which one undo takes back (on Reaper the ReaEQ is removed by hand).
const CARVE_SHARE := 0.5
const CARVE_DB := -6.0
## Instruments that stand still (slice 38): by 61.28 each half stands the test drum (TestDrumItem, a
## fixed kind no room has) at DRUM_HOME; at 61.3 the guest's fingertip comes down through its rim at
## DRUM_SPEED (its Strike, stepped by hand), to a clock of its own at DRUM_SONG. By 61.46 the host
## has the hit from the guest with its zone, the slap, and its song, and its own drum plays it where
## it stands, held by nobody. The host leaves at 64.76 and waits until 64.83; the guest ends at 64.88.
const DRUM_HOME := Transform3D(Basis.IDENTITY, Vector3(2.0, 0.0, 2.0))
const DRUM_SONG := 700.0
const DRUM_SPEED := 2.0
## A circle of hand drums (slice 40): the djembe is a fixed kind every room has (ItemRoom.KINDS), put
## away until it stands somewhere; by 61.28 each half stands it at DJEMBE_HOME (ItemRoom.stand), and at
## 61.32 the guest's fingertip comes down through its rim at DRUM_SPEED to DJEMBE_SONG. By 61.46 the
## host has the slap from the guest with its zone and song, and its own djembe rings it where it
## stands.
const DJEMBE_HOME := Transform3D(Basis.IDENTITY, Vector3(-2.0, 0.3, 2.0))
const DJEMBE_SONG := 702.0
## Drum pads on anything (slice 41): the kit is a fixed kind every room has, stood by each half at
## KIT_HOME by 61.28 (no console stands it in the probe). At 61.32 the guest marks a pad of its own
## on a surface at PAD_AT (SurfacePads, a fingertip's dwell, saved to PAD_FILE) and comes down
## through it at DRUM_SPEED to PAD_SONG: the kick. By 61.46 the host has the hit on `kit` from the
## guest with its drum and song, and rings it, with no ghost here to ring it from, at the kit.
const KIT_HOME := Transform3D(Basis.IDENTITY, Vector3(1.0, 0.74, 0.2))
const PAD_AT := Vector3(-1.0, 0.6, 1.5)
const PAD_SONG := 704.0
const PAD_FILE := "user://probe_pads.cfg"
## Every venue has something to play (slice 42): the rooftop's railing, its tuned balusters the fixed
## kinds venue1..venue8 every room has, dressed as the rooftop's set and stood by each half at its
## spot by 61.28 (`_stand_the_railing`). At 61.32 the guest's fingertip goes into the third
## baluster's front at DRUM_SPEED to RAILING_SONG. By 61.46 the host has the hit on venue3 from the
## guest with its song, and its own baluster rings it where it stands, on the song's scale tone there.
const RAILING_BAR := 2
const RAILING_SONG := 706.0
## Generative weather (slice 44): at 61.28 the host schedules the loft's Thunderstorm over one bar,
## WEATHER_BAR (1-based, the top of its gust), from its own song (Weather.drops, the loft's seed) and
## publishes what it scheduled in its room (`weather_probe`, [step, note, velocity] each). At 61.46 the
## guest presses the switch (the room's `weather` [true]), the drums done with (the first ring of a
## baluster is a sound made, some tens of milliseconds) and with room for the halves' clocks, started
## a moment apart, to be as much out; by 61.56 the room's row is LISTEN, and the
## guest's own schedule of the same bar, from its copy of the host's song, is the host's drop for
## drop. By 61.56 the host has the ask from the guest.
const WEATHER_BAR := 5.0
## A looper, by hand (slice 45): at 61.6 the guest slaps the looper, asking the host (the room's
## `looper` [LOOPER_ASKED_BAR, LOOPER_BARS]) for a bar too far off to be the next one, so the host
## gives it the next bar instead and publishes the room's row [guest, bar, LOOPER_BARS]. At 61.68 the
## guest's layer over that span (LOOPER_NOTES, a key and a hit, as Looper takes them down) is sent
## (`looper_layer`); by 61.76 the host has written it onto a track of the guest's own,
## "<GUEST> LOOP 1" in a LOOPER folder, and cleared the row; by 61.82 the guest's mirror of the host's
## mix has that track in that folder. Its ring (slice 46): at 61.84 the guest stands the looper's rings
## of its own (LooperRings, from its mirror of the host's LOOPER folder), closes a hand on the layer's
## ring and pulls it 0.5 m off: one edit, the mute and the track's removal in it, asked of the host. By
## 61.92 the host's project no longer has "<GUEST> LOOP 1" (on the built-in engine one step, named for
## the ring), and by 61.98 nor does the guest's mirror. The host takes the rest back (the folder, loop
## and transport) at 61.98.
const LOOPER_ASKED_BAR := 900
const LOOPER_BARS := 2
## [on, off, pitch, velocity, channel] in seconds after the span's start: a key, and a hand drum's hit.
const LOOPER_NOTES := [[0.1, 0.35, 60, 100, 0], [0.5, 0.6, 38, 90, 9]]
## A music-box sequencer (slice 47): at 62.02 the guest stands a music box of its own, hearing the song
## at MUSIC_BOX_SONG (past everything else the probe writes), and presses MUSIC_BOX_CELL (row, step)
## on it. Its peg shows at once; the box asks the host for the MUSIC BOX track (add_track), and once
## its mirror has it, the item over the box's bar with the peg as its note (insert_midi_take), in one
## edit. By 62.14 the host's MUSIC BOX track has one item with that note: the row's pitch in the song's
## key there, at the step's time (on the built-in engine one step, "MUSIC BOX: pegs"), and a box of
## the host's own reads it back as that peg; so does the guest's mirror. The host takes the track out
## again at 62.26.
const MUSIC_BOX_SONG := 760.0
const MUSIC_BOX_CELL := Vector2i(3, 5)
## How far a placed note may be from the moment the guest heard it, in seconds.
const TAKE_TOLERANCE := 0.005
## A string across the room (slice 48): at 62.3 the guest ties STRING_ID from STRING_A to STRING_B
## (the venue's frame), asking the host (the room's verb `string`), which answers as the studio does
## (RoomString.answer) and publishes the room's row `strings`; by 62.36 the host's row has it with
## the guest as its maker, and the guest's mirror of the room has it too. At 62.36 the guest plucks a
## string of its own at those ends, hearing the song at STRING_SONG, recording onto TAKE_TRACK; it
## rings to 62.4 and its clock stops at 62.42, sending the take. By 62.5 the host has the pluck on
## TAKE_TRACK at STRING_SONG, on the string's note in the song's key there, and heard it with the
## string's source.
const STRING_ID := &"probe_string"
const STRING_A := Vector3(-0.6, 1.2, 5.0)
const STRING_B := Vector3(-0.6, 1.2, 7.0)
const STRING_SONG := 780.0
## A marble run (slice 49): at 62.56 the guest asks two blocks of the lattice (the room's verb
## `marble`): a ramp at MARBLE_TOP facing right and a bell in the cell it rolls into, and one cell
## outside the lattice, which the host refuses to it in words. The host answers as the studio does
## (MarbleRun.answer) and publishes the room's row `marbles`; by 62.62 its row has both and not the
## third, and it publishes its rings over MARBLE_BAR (`marbles_probe`, [beat, cell, note] each). By
## 62.68 the guest's mirror of the room has both blocks, and its own rings over that bar, from its
## copy of the host's song, are the host's, bell for bell.
const MARBLE_TOP := Vector3i(4, 9, 5)
const MARBLE_BELL := Vector3i(5, 9, 5)
const MARBLE_OUTSIDE := Vector3i(4, 12, 5)
const MARBLE_BAR := 7.0
## A theremin (slice 50): from 62.72 the guest plays a theremin of its own (Theremin, its SCALE switch
## FREE) with two hands of the probe's: the volume hand half way up over the loop, the pitch hand
## gliding in from THEREMIN_FROM's distance from the rod to THEREMIN_TO's by 62.84, past the bend's
## two semitones so its note is handed on legato, hearing the song at THEREMIN_SONG and recording
## onto TAKE_TRACK. At 62.84 the volume hand comes down onto the loop and it is silent; its clock
## stops at 62.86, sending the take. By 62.92 the host has the glide on TAKE_TRACK at THEREMIN_SONG,
## named for the theremin: its notes rising, each down before the last let go, and its bends and
## CC 11 in the item; and heard its notes with the theremin's source. THEREMIN_TO is more than two
## semitones past the first hand-on's note whichever frame that falls in (71 or 72, the glide's frames
## a semitone apart), so the note is handed on twice.
const THEREMIN_SONG := 800.0
const THEREMIN_FROM := 69.0
const THEREMIN_TO := 74.6
## A modular wall (slice 51): at 62.94 the guest re-patches the room's modular (the room's verb
## `modular_patch`): an LFO onto the VCF's CV, and the noise into that same CV, which the host refuses
## to it in words (an input taken twice); it streams MODULAR_TURNS of a knob's turn (Session.send_knob)
## and lets it go at MODULAR_KNOB (`modular_knob`). The host answers as the studio does
## (Modular.answer_patch, answer_knob) and publishes the room's row `modular`; by 63.0 its row has the
## guest's cable and knob and not the refused cable, and it heard every streamed value from the guest.
## By 63.04 the guest's mirror of the room has them too.
const MODULAR_TURNS := [0.6, 0.7, 0.8]
const MODULAR_KNOB := 0.85
## The modular recorded and heard (slice 52): from 63.06 the guest plays the modular (its keys at the
## wall, GuestMidi.through_modular) hearing the song at MODULAR_SONG and recording onto TAKE_TRACK:
## MODULAR_PITCH held, and from 63.1 the cutoff swept down through MODULAR_SWEEP a frame at a time
## (Session.send_knob, stamped as it is turned); let go at 63.24, its clock stopped at 63.26. Its
## take is marked to the host on both lanes and nothing else is sent. By 63.62 the host has one
## audio take named `modular` on TAKE_TRACK at the guest's song and no MIDI take there, heard the
## notes with the modular's source and every step of the sweep, and publishes the WAV's start,
## frames and digest (the room's row `modular_probe`); by 63.68 the guest finds them equal to its
## own render of the take.
## The world into the modular (slice 53): at 63.74 the guest pulls the LFO out of the VCF's CV and
## patches the weather's socket into it (`modular_patch` [world:weather, vcf.cv]); by 63.8 the host's
## row has it, and the host renders WEATHER_BAR of the loft's Thunderstorm through its patch, MODULAR_PITCH
## held and the weather's level and drops played in from its own song (ModularWorld.weather_events),
## and publishes the render's frames and digest (`world_probe`); by 63.86 the guest's own render of the
## same bar, from its mirror of the room's patch and its copy of the host's song, begins, and by 64.0
## (the host's render takes most of a tenth of a second) it is the host's sample for sample.
## The grain cloud recorded and heard (slice 55): from 64.08 the guest's cloud plays GRAINS events, one
## a frame (Session.send_grains, stamped with the song it hears from GRAINS_SONG plus the cloud's
## figure), while it records onto TAKE_TRACK, both halves' clouds sounding the same tone
## (`_probe_grain_sound`, standing in for a sample both have). Its first event begins its take, marked
## to the host on the gestures' channel; its clock stopped at 64.3 ends it. By 64.4 the host has
## heard every event from the guest, in order, and has one audio take named `grains` on TAKE_TRACK at
## the guest's first event's song, rendered from its own sound, and publishes the WAV's start, frames
## and digest (the room's row `grains_probe`); by 64.46 the guest finds them equal to its own render
## of its take.
## The lyrics in the booth (slice 56): at 64.52 the guest's own board (a LyricBoard of its own, not in
## a room) writes two untimed lines, which is a set_lyrics intent to the host; at 64.6, hearing the
## song from LYRIC_SONG, it TAPs, which is a second intent stamping the first line. By 64.7 the
## host's lyrics are those two lines, the first stamped at LYRIC_SONG as the guest heard it and the
## second still untimed. The session ends at 64.76.
const GRAINS_SONG := 960.0
const LYRIC_SONG := 980.0
const GRAINS := 12
const MODULAR_SONG := 900.0
const MODULAR_PITCH := 57
const MODULAR_SWEEP := [0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.25, 0.2]
## The host's own take, on the built-in engine: a track, a stretch of song with nothing in it,
## and how far from the beat a click may land.
const HOST_TAKE_TRACK := 3
const HOST_TAKE_AT := 600.0
const HOST_MIDI_TRACK := 5
## The punched take's second track: the take's track records input 1, this one input 2, of the
## same recording.
const HOST_SIDE_TRACK := 4
## A track with no effects of its own, for the host's key to be heard through plainly.
const HOST_KEYS_TRACK := 11
## Fifteen, not five: Godot starts a player on the next mix step and cannot be told where in it,
## so players started in different frames can be up to a step apart (10.7ms at this driver), and
## a take from a run to run sits within about 12ms of the beat. Sample-accurate starts need the
## engine to mix its own players (step 7 in docs/loop_backlog.md).
const HOST_TAKE_TOLERANCE := 0.015
## The off-beats' track's fader: held at 0 dB, down to -9 dB over three seconds, then held.
const HOST_RAMP := [[HOST_TAKE_AT + 2.0, 0.0, DawKitAutomation.LINEAR], [HOST_TAKE_AT + 5.0, -9.0, DawKitAutomation.HOLD]]
const HOST_RAMP_TOLERANCE_DB := 0.5
## How far from its beat a count-in's click may be heard at the master.
const COUNT_IN_TOLERANCE_MS := 5.0
## How far the demo kick's onsets may be from their beats on average, and from each other.
const PARTS_TOLERANCE_MS := 6.0
const PARTS_SPREAD_MS := 1.5
## How long the punch range is, and how near its ends a punched take must start and stop.
const PUNCH_SECONDS := 1.5
const PUNCH_TOLERANCE := 0.04
## And how far each may be from the others' average.
const COUNT_IN_SPREAD_MS := 1.0
## Where the render's loop starts, and how far a note in the rendered stem may be from its place.
const RENDER_FROM := 40.0
const RENDER_TOLERANCE_MS := 2.0
## The rig's Kick Out: a track of its own, not a folder, with a steady sound in it. (Its DRUMS
## folder renders 0.7 dB short of its lane: something in the folder is not under its fader.)
const RENDER_TRACK := 3
## Clicks let go by before playing. The host's song clock is only as good as the reports it
## has had, and in the first moments of a take Reaper has sent only a few; see SongClock and
## docs/architecture.md, "Recording a guest".
const SETTLE_CLICKS := 1

var _failures := 0
var _checks := 0
var _notices: Array[String] = []
var _refused: Array = []
var _start := 0
var _reaper_resource := ""
var _expect_tracks := 20
## Seconds added to every step of the timeline, on both halves: a host on a real Reaper needs a
## moment to hear the project before it has anything to share.
var _shift := 0.0
var _port := 7342
## The host plays the built-in engine's song instead of a test tone: what the guest hears is
## then a real mix off the host's master bus, and has no clicks to time.
var _built_in := false
## The guest's host is Reaper (the rig, whose project is rig.RPP).
var _reaper_host := false
## Host: the guest's recording, as Session placed it.
var _audio_placed := {}
## Every take placed, in order.
var _placed_all: Array = []
## Host: what guests asked of the room, as [verb, args, from].
var _room_asks: Array = []
## The modular's knobs as the guest turned them (slice 51), heard on the host: [id, v, from] each.
var _knobs_heard: Array = []
## Host: the modular takes placed (slice 52), as ModularTakes.placed says each.
var _modular_placed: Array = []
## Host: the grain events heard (slice 55), [event, from, song] each; and the grain takes placed.
var _grains_heard: Array = []
var _grains_placed: Array = []
## Host: where the guest said something was while pushing it.
var _motions: Array = []
## Guest: how many times the host's room arrived.
var _rooms_heard := 0
## Heard from the other side: [item, local or down, from] for carries and uses.
var _carries: Array = []
var _uses: Array = []
## The Foley take each of `_uses` rang (Session.item_used's `take`, slice 26), in the same order.
var _use_takes: Array = []
## Notes heard from the other half, as Session.note_played gives them: plain keys' here, and an
## instrument's [kind, pitch, from, source] in `_sourced`.
var _notes: Array = []
var _sourced: Array = []
## The other half's harp notes, from when the strums begin: [kind, pitch, from, song].
var _harped: Array = []
## The other half's item hits, as Session.item_hit gives them: [item, velocity, from, song, snap,
## take, zone].
var _item_hits: Array = []
## Each half's room of items, as the studio keeps one: the four handbells are in it.
var _room: ItemRoom = null
## Who the host's table said had the duck when the guest's put-down reached it.
var _duck_holder_at_put := -1
## Who has had the plane, in turn, as the host's table said.
var _plane_holders: Array = []
## Each half's jacks, as the studio keeps them (slice 6): what comes down a cable into this half,
## as Session.jack_played gives it ([source, kind, pitch, from, song]), and what that played on
## this half's keys as the cable's ([kind, pitch, song]).
var _jacks: Jacks = null
var _jacked: Array = []
var _cabled: Array = []
## The head this half publishes (`_keep_publishing`), until the guest travels (`_travel_to_the_harp`).
var _head := Transform3D.IDENTITY
## What this half publishes it points at, and where (`_keep_publishing`); the guest's ruler time
## from 60.82 (slice 35).
var _pointing := ""
var _pointing_local := Vector3.ZERO
## Host: the history's depth before the guest's two-value drag (slice 12), and the guest's track's
## pan and volume and the host's own track's volume then.
var _edit_depth := 0
var _edit_was: Array = [0.5, 0.5, 0.5]
## The stage track's pan and volume before the guest placed it.
var _stage_was: Array = [0.5, 0.716]
## Whether the clap's track was muted before the guest clapped at it.
var _clap_was := false
## How many plugins the rope's track had before the guest tied it, so a compressor the rope added on
## Reaper is taken away by hand.
var _rope_plugins_were := 0
## The bead track's lane and level before the guest's pass, to put back on Reaper.
var _bead_was: Array = []
var _bead_volume_was := 0.0
## Host: the made items the guest's pull and the host's give put in the guest's hand (slice 23).
var _made_for_guest: Array[StringName] = []
## Host: the guest's paste as asked, [id, track, seconds] (slice 24), and what pasting it said.
var _paste_asked: Array = []
var _paste_said := "not asked"
## Host: the audio cassette minted for the guest's ear (slice 25).
var _ear_cassette: StringName = &""
## Host: the sampler the guest's REC arms (slice 26), and what it caught: [cassette id, file, from].
var _sampler: Sampler = null
var _sampled: Array = []


func _ready() -> void:
	var argv := OS.get_cmdline_user_args()
	var role := "host"
	var port := 7342
	for i in argv.size():
		if argv[i] == "--as" and i + 1 < argv.size():
			role = argv[i + 1]
		if argv[i] == "--port" and i + 1 < argv.size():
			port = int(argv[i + 1])
			_port = port
		# The host drives a real Reaper instead of the stand-in: the guest's fader move then
		# goes guest -> host -> Reaper -> OSC echo -> host -> guest, the whole road.
		if argv[i] == "--reaper-resource" and i + 1 < argv.size():
			_reaper_resource = argv[i + 1]
		if argv[i] == "--shift" and i + 1 < argv.size():
			_shift = float(argv[i + 1])
		if argv[i] == "--built-in":
			_built_in = true
		if argv[i] == "--reaper-host":
			_reaper_host = true
		if argv[i] == "--expect-tracks" and i + 1 < argv.size():
			_expect_tracks = int(argv[i + 1])
	Session.notice.connect(func(t: String): _notices.append(t))
	Session.hold_refused.connect(func(k: String, h: int): _refused.append([k, h]))
	_start = Time.get_ticks_msec()
	if role == "host":
		_write_epoch()
		await _host(port)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_epoch_path()))
	else:
		await _share_the_hosts_epoch()
		await _guest(port)
	print("\n[%s] %d session checks, %d failed" % [role, _checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Where the host writes when its timeline began, for the guest's to begin with it.
func _epoch_path() -> String:
	return "user://session_probe_%d.epoch" % _port


## Host: my timeline's 0, in the machine's clock, written for the guest (`_share_the_hosts_epoch`).
func _write_epoch() -> void:
	var f := FileAccess.open(_epoch_path(), FileAccess.WRITE)
	if f != null:
		f.store_string("%.6f" % Time.get_unix_time_from_system())


## Guest: my timeline begun when the host's did. The two halves are started together but each is up
## when it is, tens of ms apart under load (60 ms has been seen), and every step's gap is a few tens of
## ms: a guest ahead of its host acted before the host looked (a clap before the host's check of the
## placing before it), one behind looked before the host had answered. Both run on one machine, so
## the host's start in the machine's clock is the guest's 0 too. A file from an earlier run is older.
func _share_the_hosts_epoch() -> void:
	var mine := Time.get_unix_time_from_system()
	while Time.get_unix_time_from_system() - mine < 5.0:
		var text := FileAccess.get_file_as_string(_epoch_path())
		if text.is_valid_float() and float(text) > mine - 5.0:
			_start = Time.get_ticks_msec() - int((Time.get_unix_time_from_system() - float(text)) * 1000.0)
			return
		await get_tree().process_frame
	print("the host's epoch never came: my timeline is my own")


func _host(port: int) -> void:
	Session.audio_take_placed.connect(func(info: Dictionary):
		_audio_placed = info
		_placed_all.append(info))
	# The patch a take through the modular starts from, as the studio hears it (slice 52).
	Session.modular_takes.patch = _probe_patch
	Session.modular_takes.placed.connect(func(info: Dictionary): _modular_placed.append(info))
	# The grain cloud's sound both halves hear, and what the guest's grains do here (slice 55).
	Session.grain_takes.sound = _probe_grain_sound
	Session.grain_takes.placed.connect(func(info: Dictionary): _grains_placed.append(info))
	Session.grains_played.connect(func(e: PackedFloat32Array, from: int, song: float): _grains_heard.append([e, from, song]))
	Session.local_name = "Ada"
	var restore := NAN
	var tempo_restore := NAN
	var send_restore := NAN
	var monitor_restore := -1
	if _reaper_resource != "":
		check("opens the link to Reaper", DAW.use(ReaperBackend.new(), true, {
				"bridge_dir": _reaper_resource.path_join("Scripts/dawlings_bridge_data")}))
		await _until(-0.5)
		restore = DAW.state.track(2).volume
		tempo_restore = DAW.state.tempo
		monitor_restore = DAW.state.track(3).monitor
		var first := _first_send(DAW.state)
		if not first.is_empty():
			send_restore = DAW.state.send(first[0], first[1]).volume
	elif _built_in:
		var engine := GodotBackend.new()
		engine.track_count = 20
		DAW.use(engine)
		DAW.transport_play()
	else:
		var offline := OfflineBackend.new()
		offline.track_count = 20
		DAW.use(offline)
	Session.code = "AB12"
	Session.mix_source = func(): return MixSource.Tone.new()
	if _built_in:
		Session.mix_source = func(): return (DAW.backend as GodotBackend).mix_source()
	check("hosts", Session.host(port))
	# The room as the studio would publish it, and answered the way the studio answers.
	Session.publish_room({"venue": &"grid", "tablets": {&"tablet_1": [2, 1, "EQ", 0.4, 0.2, 0.0]}})
	Session.room_motion.connect(func(piece: StringName, x: float, z: float, h: float, from: int):
		_motions.append([piece, x, z, h, from]))
	Session.item_carried.connect(func(item: StringName, local: Transform3D, from: int):
		_carries.append([item, local, from]))
	Session.item_used.connect(func(item: StringName, down: bool, from: int, take: int):
		_uses.append([item, down, from])
		_use_takes.append(take))
	Session.item_used.connect(_sample_a_use)
	Session.note_played.connect(_on_note_played)
	Session.item_hit.connect(func(item: StringName, velocity: int, from: int, song: float, snap: bool, take: int, zone: StringName):
		_item_hits.append([item, velocity, from, song, snap, take, zone]))
	Session.knob_turned.connect(func(id: StringName, v: float, from: int, _song: float):
		_knobs_heard.append([id, v, from]))
	Session.room_asked.connect(func(verb: StringName, args: Array, from: int):
		_room_asks.append([verb, args, from])
		if verb == &"put_item":
			_duck_holder_at_put = Session.holder_of(DUCK)
		if verb == &"plug":
			_answer_plug(args, from)
		if verb == &"make":
			_answer_make(args, from)
		if verb == &"paste":
			_answer_paste(args, from)
		if verb == &"bricks":
			_answer_bricks(args, from)
		if verb == Sampler.VERB:
			_answer_sampler(args, from)
		if verb == Weather.VERB:
			_answer_weather(args, from)
		if verb == Looper.VERB:
			_answer_looper(args, from)
		if verb == Looper.LAYER_VERB:
			_answer_looper_layer(args, from)
		if verb == FifthsWheel.VERB:
			# As the studio answers a guest's SET: written at the bar the guest chose.
			FifthsWheel.answer(args[0], args[1])
		if verb == RoomString.VERB:
			_answer_string(args, from)
		if verb == MarbleRun.VERB:
			_answer_marble(args, from)
		if verb == Modular.PATCH_VERB or verb == Modular.KNOB_VERB:
			_answer_modular(verb, args, from)
		if verb == &"open_tablet":
			var room: Dictionary = Session.room.duplicate(true)
			room["tablets"][&"tablet_2"] = [args[0], args[1], args[2], args[3], args[4], 0.0]
			Session.publish_room(room))
	check("and shares its mix's audio", Session.mix_feed.sending)
	_keep_publishing(Transform3D(Basis(Vector3.UP, 0.6), Vector3(1.2, 1.62, 0.4)), "MASTER  VOLUME")

	# Between the guest's wrong knock (0.3) and its right one (1.4), with room either side: two
	# processes started a moment apart do not share a clock to the millisecond.
	Session.takeable = func(key: String) -> bool: return key == PLANE
	Session.holds_changed.connect(func() -> void:
		if _plane_holders.is_empty() or _plane_holders[-1] != Session.holder_of(PLANE):
			_plane_holders.append(Session.holder_of(PLANE)))
	Session.claim_hold(PLANE)

	await _until(0.9)
	check("a knock with the wrong code is not let in", Session.participants.size() == 1)
	check("and the host hears about it", _notices.has("Someone tried to join without the right code."))

	await _until(3.6)
	var guest_id := _other_id()
	check("the guest is on the roster", guest_id != 0)
	check("under the name it gave", Session.name_of(guest_id) == "Grace")
	if guest_id != 0:
		check("in a colour of its own", Session.participants[guest_id].colour_index
				!= Session.participants[1].colour_index)
		check("and its head has been heard", Session.participants[guest_id].head.origin.is_equal_approx(
				Vector3(-0.8, 1.5, 0.9)))
	check("the guest's fader move reached the mix (%.4f)" % DAW.state.track(2).volume,
			absf(DAW.state.track(2).volume - 0.123) < 0.002)
	check("the guest's tempo reached the mix (%.1f)" % DAW.state.tempo,
			absf(DAW.state.tempo - GUEST_TEMPO) < 0.05)
	var sent := _first_send(DAW.state)
	check("the guest's send level reached the mix (%s)" % [sent], not sent.is_empty()
			and absf(DAW.state.send(sent[0], sent[1]).volume - GUEST_SEND) < 0.002)
	check("the guest switched the click on", DAW.state.metronome)
	check("the guest's input monitoring reached the mix (%d)" % DAW.state.track(3).monitor,
			DAW.state.track(3).monitor == DAW.MONITOR_AUTO)
	check("the guest's marker is on the host's timeline (%s)" % [DAW.state.markers.values()],
			_has_guest_mark(DAW.state))
	check("the guest's grab is in the host's table", Session.holder_of(KEY) == guest_id and guest_id != 0)
	check("the guest's ask for a stand reached the host (%s)" % [_room_asks], _room_asks.size() == 3
			and _room_asks[0][0] == &"open_tablet" and _room_asks[0][2] == guest_id)
	check("the guest's push reached the host while it moved (%s)" % [_motions], _motions.size() == 1
			and _motions[0][0] == &"rack" and is_equal_approx(_motions[0][1], -0.9) and _motions[0][4] == guest_id)
	check("and its rolling the rack", _room_asks.size() == 3 and _room_asks[1][0] == &"move_piece"
			and _room_asks[1][1][0] == &"rack")
	check("and its putting the desk down", _room_asks.size() == 3 and _room_asks[2][0] == &"place_surface"
			and (_room_asks[2][1][1] as Transform3D).origin.is_equal_approx(Vector3(0.1, 0, 0.2)))
	check("and the guest is listening to the mix", Session.mix_feed.listener_count() == 1)
	check("the guest's pick-up of the duck is in the host's table", Session.holder_of(DUCK) == guest_id
			and guest_id != 0)
	check("and where it carries it came with it (%s)" % [_carries], not _carries.is_empty()
			and _carries[-1][0] == &"duck" and (_carries[-1][1] as Transform3D).is_equal_approx(DUCK_AT)
			and _carries[-1][2] == guest_id)
	check("and its squeeze (%s)" % [_uses], _uses == [[&"duck", true, guest_id]])
	Session.send_item_use(&"duck", false)

	# Reach for the fader the guest is holding: the host's own hand is refused too.
	Session.claim_hold(KEY)
	# A key on the host's keys, as played, for whoever is patched into them.
	Session.guest_midi.note_on(67, 80)
	Session.guest_midi.note_off(67)
	# And one from an instrument of the host's: it says so (GuestMidi.instruments).
	Session.guest_midi.note_on(71, 70, 0, 0.0, false, &"harp")
	Session.guest_midi.note_off(71, 0, 0.0, false, &"harp")
	await _until(4.0)
	check("the host is refused a control the guest holds",
			_refused.size() == 1 and _refused[0][0] == KEY and _refused[0][1] == guest_id)
	check("and the hold stays the guest's", Session.holder_of(KEY) == guest_id)

	await _until(6.0)
	check("the guest's release cleared the table", Session.holds.is_empty())
	check("the plane went from the host's hand to the guest's, and was let go (%s)" % [_plane_holders],
			_plane_holders == [1, _other_id(), 0])
	check("its throw of the duck arrived whole: the launch, as vectors (%s)" % [_room_asks[3] if _room_asks.size() > 3 else null],
			_room_asks.size() == 6 and _room_asks[3][0] == &"throw_item"
			and _room_asks[3][1] == [&"duck", Vector3(0.4, 1.2, 1.5), Vector3(0.0, 2.0, 3.5), Vector3(-6.0, 0.0, 0.0)])
	check("its put-down of the duck arrived while it still had it (%d)" % _duck_holder_at_put,
			_room_asks.size() == 6 and _room_asks[4][0] == &"put_item" and _duck_holder_at_put == _other_id())
	check("the guest's keys as it played them, a note on and its note off (%s)" % [_notes],
			_notes == [[Session.Note.ON, 60, 100, guest_id], [Session.Note.OFF, 60, 0, guest_id]])
	check("and its fingertips' note, saying where it came from (%s)" % [_sourced],
			_sourced == [[Session.Note.ON, 62, guest_id, &"fingertips"], [Session.Note.OFF, 62, guest_id, &"fingertips"]])
	check("and its plug in the MIX send, for its own headphones (%s)" % [_room_asks[5] if _room_asks.size() > 5 else null],
			_room_asks.size() == 6 and _room_asks[5][0] == &"patch" and _room_asks[5][1] == [1, &"mix"]
			and _room_asks[5][2] == guest_id)
	Session.claim_hold(KEY)
	check("so the host can take it now", Session.holder_of(KEY) == 1)
	Session.release_hold(KEY)

	# The guest records a take against what it hears: see _guest_records. On the built-in engine
	# the host records itself instead: see _host_records_itself.
	await _until(7.0)
	if not _built_in:
		DAW.transport_record()
	else:
		await _host_records_itself()
	await _until(12.8)
	if not _built_in:
		DAW.transport_stop()
	else:
		# A different project opened mid-session reaches the guest whole: seven tracks, the first
		# renamed, where there were thirteen -- drums and bass, and the reverb return, which the
		# render's tail is heard through.
		# The second track records from the default microphone: kept through the file.
		DAW.set_track_input(2, "audio:")
		var other := ProjectBridge.capture(DAW.backend as OfflineBackend)
		var verb := other.tracks.filter(func(t): return t.name == "Verb Rtn")
		other.tracks.resize(6)
		other.tracks.append_array(verb)
		for t in other.tracks:
			t.sends = t.sends.filter(func(sd): return other.track(sd.target) != null)
		other.tracks[0].name = "Opened"
		var refused := ProjectBridge.load(other, DAW.backend as OfflineBackend)
		# And through a real file: saved as DAWproject and opened again, so what the guest hears
		# next is the project's own files (the demo parts, rendered into it), not the engine's
		# synthesised song.
		var file := OS.get_temp_dir().path_join("dawlings_probe_%d.dawproject" % _port)
		var saved := DAW.save_project_as(file)
		var opened := DAW.open_project(file)
		# From the first item: the six tracks kept are drums and bass, which the intro leaves
		# out (and the guest moved the tempo, so bar numbers no longer say where they are).
		var first_item := INF
		for index in DAW.state.track_indices():
			for it in DAW.state.track(index).items:
				first_item = minf(first_item, it.start)
		DAW.seek(first_item + 0.1)
		DAW.transport_play()
		DirAccess.remove_absolute(file)
		check("I opened another project mid-session, through a file (%s %s %s)" % [refused, saved, opened],
				refused.is_empty() and saved.is_empty() and opened.is_empty())
		check("with its second track's input kept (%s)" % DAW.state.input_of(2), DAW.state.input_of(2) == "audio:")
	if _built_in:
		await _until(14.3)
		var file := OS.get_temp_dir().path_join("dawlings_probe_%d.dawproject" % _port)
		check("the guest's save saved my file, and I was told (%s)" % [_notices],
				FileAccess.file_exists(file) and _notices.has("Grace saved the project as %s." % file.get_file()))
		DirAccess.remove_absolute(file)
		await _render_and_measure()
		await _count_in_and_measure()
		await _count_in_and_measure(true)
		await _count_in_and_measure(false, true)
		await _punch_and_measure()
		await _meter_and_measure()
		await _parts_and_measure()
	await _until(14.0)
	if not _built_in:
		_check_placed_take()
		_check_audio_take()
		await _edit_the_take()
		if _reaper_resource != "":
			await _tracks_in_reaper()
		await _undo_takes()
		if _reaper_resource != "":
			# After the takes' undos: these are Reaper undo points of their own.
			await _count_in_in_reaper()
		await _until(39.0 if _reaper_resource != "" else 17.5)
		_check_sent_files()

	# The harp (docs/spatial_loop.md slice 3): the song put in D minor from the playhead's bar,
	# the guest strums at 41, the host hears it as harp notes of that chord, and strums back at 43.
	await _until(40.0)
	_harped.clear()
	var bar := floorf(DAW.state.bar_at(DAW.state.position_seconds) + Harmony.BAR_SLACK)
	DAW.add_marker(DAW.state.bar_to_seconds(bar + 1.0), HARP_KEY)
	var harp := _harp()
	_check_bells()
	await _until(43.0)
	_check_strum(_other_id(), "the guest's strum reached me")
	_strum(harp)

	# The guest rings bell 2 at 44 (docs/spatial_loop.md slice 4): its hit arrives with the song
	# position it was played to, and my bell 2 rings D minor's third there, as the guest's did.
	await _until(46.0)
	var rings := _item_hits.filter(func(h: Array) -> bool: return h[0] == &"bell2")
	var song: float = rings[0][3] if rings.size() == 1 else -1.0
	check("the guest's ring of bell 2 reached me with its song position (%s)" % [rings],
			rings.size() == 1 and rings[0][2] == _other_id() and is_equal_approx(song, _ring_song()))
	var bell := _room.items.get(&"bell2") as HandbellItem
	check("and my bell 2 rings it as D minor's third, F5 (%d)" % (bell.note_at(song) if bell != null else -1),
			bell != null and bell.note_at(song) == 77)

	# Jacks (docs/spatial_loop.md slice 5): the guest plugged the shaker on its shelf into track
	# 3 at 44.5, and the host's rule let it; the host plugs bell 1 into track 5 for the guest to see.
	var plugs := _room_asks.filter(func(a: Array) -> bool: return a[0] == &"plug")
	check("the guest's plug reached me, from the guest (%s)" % [plugs], plugs.size() == 1
			and plugs[0][1] == [&"shaker", &"track_3"] and plugs[0][2] == _other_id())
	check("and is in my room's state (%s)" % [Session.room.get("jacks")],
			Session.room.get("jacks", {}) == {"shaker": "track_3"})
	var mine: Dictionary = Session.room.duplicate(true)
	var rows: Dictionary = mine.get("jacks", {})
	rows["bell1"] = String(Jack.track_sink(PLUG_TRACK))
	mine["jacks"] = rows
	Session.publish_room(mine)

	# Cables (docs/spatial_loop.md slice 6): jacks of my own, playing what comes into my keys, and
	# my word on every event down one, as the studio's (Session.jack_check).
	_wear_jacks()
	_jacks.set_patch(rows)
	_room.played.connect(func(item: InstrumentItem, velocity: int, _struck: bool, at: float, zone: StringName) -> void:
		_jacks.hit(item, velocity, at, zone))
	Session.jack_check = func(to: int, source: StringName, from: int) -> String:
		var item: Item = _room.items.get(source)
		var holder := Session.holder_of(item.network_key()) if item != null else 0
		return Jacks.send_refusal(Session.room.get("jacks", {}), source, to, from, holder)
	# Bell 1, in my hand, into the guest: its note, D minor's root D5, and its off there.
	await _until(48.6)
	var bell1 := _room.items.get(&"bell1") as HandbellItem
	Session.claim_hold(bell1.network_key())
	mine = Session.room.duplicate(true)
	rows = mine.get("jacks", {})
	rows["bell1"] = String(Jack.player_sink(_other_id()))
	mine["jacks"] = rows
	Session.publish_room(mine)
	_jacks.set_patch(rows)
	await _until(49.0)
	InstrumentItem.clock = func() -> float: return _ring_song() + 2.0
	bell1.play(90)
	InstrumentItem.clock = Callable()
	# The guest's shaker, in its hand and plugged into me at 48.3, hit four times at 48.8.
	await _until(49.6)
	var hits := _jacked.filter(func(j: Array) -> bool: return j[0] == &"shaker")
	check("the guest's four shaker hits reached me down its jack, from the guest (%s)" % [hits], hits.size() == 4
			and hits.all(func(j: Array) -> bool: return j[1] == Jack.Kind.TRIGGER and j[3] == _other_id()))
	var tones := _cabled.filter(func(c: Array) -> bool: return c[0] == Session.Note.ON).map(func(c: Array) -> int: return c[1])
	check("and played D minor's tones up the chord on my keys, at their songs (%s)" % [tones], tones == CABLE_TONES
			and _cabled.filter(func(c: Array) -> bool: return c[0] == Session.Note.ON).map(func(c: Array) -> float: return c[2])
			== hits.map(func(j: Array) -> float: return j[4]))
	check("each let go (%d)" % _cabled.filter(func(c: Array) -> bool: return c[0] == Session.Note.OFF).size(),
			_cabled.filter(func(c: Array) -> bool: return c[0] == Session.Note.OFF).size() == 4)
	# The guest's harp, plugged into me, strummed at 50.2: in my take on CABLE_TRACK, recording to a
	# given clock from 49.8 to 53.
	await _until(49.8)
	var gm := Session.guest_midi
	var saved_roll := gm.roll_every
	gm.roll_every = 0.0
	gm.target_track = CABLE_TRACK
	gm.record_with_host = true
	DAW.state.track(CABLE_TRACK).items.clear()
	gm.heard_source = _given_clock(CABLE_SONG - 1.0, true)
	_jacked.clear()
	await _until(53.0)
	gm.heard_source = _given_clock(CABLE_SONG + 2.2, false)
	await _until(53.6)
	var strings := _jacked.filter(func(j: Array) -> bool: return j[0] == Jack.HARP and j[1] == Jack.Kind.NOTE_ON)
	var takes: Array = DAW.state.track(CABLE_TRACK).items.filter(func(it: MixState.ItemState) -> bool:
		return it.name.contains("cable"))
	var notes: Array = MidiTake.unpack_relative(takes[-1].notes, takes[-1].start) if not takes.is_empty() else []
	notes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var landed := notes.size() == strings.size() and strings.size() == ChordHarp.STRINGS
	for i in mini(notes.size(), strings.size()):
		landed = landed and int(notes[i][2]) == int(strings[i][2]) and absf(float(notes[i][0]) - float(strings[i][4])) < 0.002
	check("the guest's harp strum came down its jack as D minor's strings (%s)" % [strings.map(func(j: Array) -> int: return j[2])],
			strings.map(func(j: Array) -> int: return j[2]) == HARP_STRINGS)
	check("and is in my take on track %d, each where the guest plucked it (%d notes, %s)" % [CABLE_TRACK, notes.size(),
			takes.map(func(it: MixState.ItemState) -> String: return it.name)], takes.size() == 1 and landed)
	gm.heard_source = Callable()
	gm.target_track = 0
	gm.roll_every = saved_roll
	Session.release_hold(bell1.network_key())

	# Slice 12: where history is before the guest's two-value drag, and my own fader in the middle
	# of it, as another player's write between the edit's.
	await _until(54.4)
	_edit_depth = DAW.state.undo_depth
	_edit_was = [DAW.state.track(EDIT_TRACK).pan, DAW.state.track(EDIT_TRACK).volume,
			DAW.state.track(EDIT_HOST_TRACK).volume]
	await _until(54.7)
	DAW.set_track_volume(EDIT_HOST_TRACK, 0.42)

	# The fifths wheel (docs/spatial_loop.md slice 9): the guest's SET at 53.7, asked with its bar.
	await _until(55.0)
	var sets := _room_asks.filter(func(a: Array) -> bool: return a[0] == FifthsWheel.VERB)
	check("the guest's SET reached me as an ask with its bar (%s)" % [sets], sets.size() == 1
			and sets[0][1] == [WHEEL_BAR, WHEEL_INSIDE] and sets[0][2] == _other_id())
	_check_wheel("my")
	# The guest travelled to the harp at 53.8, in a headset (slice 11): its head, which its ghost
	# stands at, is at the harp's seat in my room's venue.
	var seat: Variant = _harp_seat()
	var guest_head: Transform3D = Session.participants[_other_id()].head if Session.participants.has(_other_id()) \
			else Transform3D.IDENTITY
	var wanted: Vector3 = (seat as Transform3D) * TRAVEL_OFFSET if seat != null else Vector3.INF
	check("the guest's travel put its ghost at the harp's seat (%.3f m off)" % guest_head.origin.distance_to(wanted),
			guest_head.origin.distance_to(wanted) < 0.05)

	# One undo step per gesture (slice 12): the guest's two-value drag, 54.55 to about 54.9,
	# inside an edit; my own fader in the middle of it is a step of my own. After 55.1, when the
	# guest has read the same.
	await _until(55.25)
	var depth: int = DAW.state.undo_depth
	var names: Array = DAW.state.undo_names.slice(_edit_depth, depth)
	check("the guest's drag moved both its pan and its volume (%.3f, %.3f)" % [DAW.state.track(EDIT_TRACK).pan,
			DAW.state.track(EDIT_TRACK).volume], absf(DAW.state.track(EDIT_TRACK).pan - EDIT_PAN) < 0.002
			and absf(DAW.state.track(EDIT_TRACK).volume - EDIT_VOLUME) < 0.002)
	if _reaper_resource == "":
		check("and is one step in my history, beside my own (%s)" % [names], depth == _edit_depth + 2
				and names.count(EDIT_NAME) == 1 and names.any(func(n) -> bool: return str(n).ends_with(": volume")))
		DAW.undo()
		DAW.undo()
		check("two undos take back my fader, and the guest's whole drag (%.3f %.3f %.3f)" % [
				DAW.state.track(EDIT_TRACK).pan, DAW.state.track(EDIT_TRACK).volume, DAW.state.track(EDIT_HOST_TRACK).volume],
				absf(DAW.state.track(EDIT_TRACK).pan - float(_edit_was[0])) < 0.0001
				and absf(DAW.state.track(EDIT_TRACK).volume - float(_edit_was[1])) < 0.0001
				and absf(DAW.state.track(EDIT_HOST_TRACK).volume - float(_edit_was[2])) < 0.0001
				and DAW.state.undo_depth == _edit_depth)
	else:
		# Reaper's OSC writes stay its own undo points (docs/spatial_loop.md): put back by hand.
		DAW.set_track_pan(EDIT_TRACK, float(_edit_was[0]))
		DAW.set_track_volume(EDIT_TRACK, float(_edit_was[1]))
		DAW.set_track_volume(EDIT_HOST_TRACK, float(_edit_was[2]))

	# Controls beside the keys (slice 13): my bend during a held note, which the guest hears on its
	# TheirKeys, and which rests there at my note-off. The guest's CC 7 at 55.27 is refused here.
	await _until(55.29)
	gm.note_on(BEND_PITCH, 100)
	check("my bend during a held note is taken", gm.control(DawKitClip.PITCH_BEND, BEND_VALUE))
	await _until(55.45)
	gm.note_off(BEND_PITCH)
	check("and rests at my note-off", int(gm.controls.get(DawKitClip.PITCH_BEND, -1)) == 0)
	check("the guest's volume controller was refused, as no controller but the bend, 1 and 11 is passed (%d)"
			% Session.controls_refused, Session.controls_refused == 1)

	# Controls in takes (slice 14): the guest's keyboard wheel at 56.2, during a held note, is a
	# control in the take it sends me, at the song it was moved at, and back at rest at its note-off.
	await _until(56.7)
	_check_bent_take()

	# Bend and wobble by tilting (slice 15): the guest's keytar note, bent by its neck hand's tilt,
	# is in the take it sends me with its bend.
	await _until(57.55)
	_check_tilted_take()

	# Snapped gently (slice 17): the guest's shaker hit 20 ms before a sixteenth, snapped, is half
	# way there in the take it sends me; its unsnapped one is where it was played.
	await _until(57.65)
	_check_snapped_take()

	# The stage table (slice 18): the guest's placing, from 57.7, is its pan and its level at once,
	# and one step in my history: one undo takes both back.
	_stage_was = [DAW.state.track(STAGE_TRACK).pan, DAW.state.track(STAGE_TRACK).volume]
	await _until(58.1)
	_check_stage_placing()

	# Clap to mute (slice 19): the guest's clap at 58.2, a latch, toggles my track's mute.
	_clap_was = DAW.state.track(CLAP_TRACK).mute
	await _until(58.4)
	_check_clap_mute()

	# Sidechain as a rope (slice 20): the guest's rope, tied at 58.5, is my key send.
	_rope_plugins_were = DAW.state.track(ROPE_TO).plugins().size()
	await _until(58.67)
	_check_rope()

	# Automation by gesture (slice 22): the guest's write bead, pulled at 58.74 to a clock of its
	# own, is my lane at its song positions.
	_bead_was = WriteBead.lane_now(BEAD_TRACK, "volume")
	_bead_volume_was = DAW.state.track(BEAD_TRACK).volume
	await _until(58.85)
	_check_written_lane()

	# Clips as cassettes (slice 23): the guest's pull at 58.86 is a cassette I mint and put in its
	# glove (`_answer_make`); at 58.9 I hand it one of my own, as the studio's give does.
	await _until(58.9)
	_give_a_cassette()
	await _until(58.97)
	_check_cassettes_given()

	# A cassette onto a track (slice 24): the guest's paste at 58.99 of the cassette I gave it is my
	# own row's clip on PASTE_TRACK at PASTE_BAR (`_answer_paste`), one step I take back at 59.1.
	await _until(59.08)
	_check_pasted()
	await _until(59.1)
	_take_back_the_paste()

	# A cassette at the ear (slice 25): an audio cassette of a file only I have, minted at 59.12; the
	# guest's ear on it at 59.2 asks me for the file, and by 59.34 I have sent it, once.
	await _until(59.12)
	_mint_an_ear_cassette()
	await _until(59.34)
	_check_ear_file_sent()

	# Anything can be a sample (slice 26): the guest's REC at 59.36 arms my sampler for it
	# (`_answer_sampler`); its squeeze at 59.48 is caught here with its take (`_sample_a_use`).
	await _until(59.52)
	_check_sampled()
	await _until(59.62)
	_take_back_the_sample()

	# A DJ platter (slice 27): the guest's turns of its platter, 59.6 to 59.68, are seeks of mine.
	await _until(59.74)
	_check_platter_seek()
	# And my playhead back in the harp's D minor, where the chord hand (slice 33) is held at 60.66:
	# the platter left it at bar 7, in the intro's A minor, whose IV is Dm and not Gm.
	DAW.seek(_ring_song())

	# A tape reel for undo history (slice 28): the guest's crank, settled about 60.05, is one
	# undo_to of my history, CRANK_NOTCHES back from where it is at 59.76; put back at 60.14.
	await _until(59.76)
	var crank_from: int = DAW.state.undo_depth
	await _until(60.12)
	_check_cranked(crank_from)
	await _until(60.14)
	if crank_from >= 0:
		DAW.undo_to(crank_from)
	else:
		for _i in CRANK_NOTCHES:
			DAW.redo()

	# Sections rearranged (slice 29): three regions of mine past the song, laid out at 60.16; the
	# guest's order at 60.24 is one step of mine by 60.34, taken back with them at 60.36.
	await _until(60.16)
	_lay_out_sections()
	await _until(60.34)
	_check_rearranged()
	await _until(60.36)
	_take_back_the_sections()

	# Chord bricks (slice 31): a section of mine at 60.38; the guest's ledge bricks (60.42) minted
	# onto my ledge, its nudge my room's row, its press of the row onto my section block (60.5) the
	# wheel's ask, written by 60.56; all of it taken back at 60.58.
	await _until(60.38)
	_lay_out_a_brick_section()
	await _until(60.56)
	_check_bricks_pressed()
	await _until(60.58)
	_take_back_the_bricks()

	# A chord hand down a jack (part two, slice 33): a chord hand of mine to take the guest's chord,
	# its chord:G plugged into me at 60.62, IV held at 60.66; my harp retuned to it by 60.7 and
	# strummed, and let go once the guest unplugs it at 60.74.
	await _until(60.6)
	var chords := ChordHand.new()
	add_child(chords)
	await _until(60.7)
	_check_chord_into_me(chords, harp)
	await _until(60.8)
	check("unplugged, the guest's chord is let go, and my harp is D minor's again (%s)" % [harp.tuning()],
			not chords.plays_theirs() and harp.tuning() == PackedInt32Array(HARP_STRINGS))
	chords.queue_free()

	# Point, mark and listen together (slice 35): the guest's ruler point and its sticky note, by
	# 60.9; the note taken back at 60.92.
	await _until(60.9)
	_check_point_and_note()
	await _until(60.92)
	_take_back_the_note()

	# The EQ wall's spectra (slice 36): sent from 60.92 to 61.12, as the studio's Spectra sends them.
	var spectra := Spectra.new()
	spectra.measure = _probe_spectrum
	add_child(spectra)
	await _until(61.12)
	check("my spectra went out: measured, a guest here to send them to", not spectra.latest().is_empty()
			and Session.role == Session.Role.HOST)
	spectra.queue_free()

	# Carving the clash (slice 37): the guest's push on the bass's side, from 61.14, is my bass's EQ by
	# 61.26, taken back at once.
	var carve_chain := DAW.state.track(SPECTRA_BASS).plugins().size()
	var carve_depth := maxi(DAW.state.undo_depth, 0)
	await _until(61.26)
	_check_carve(carve_chain, carve_depth)

	# Instruments that stand still (slice 38): the guest's strike on the test drum, at 61.3, is mine
	# by 61.46 with its zone and song, and my drum plays it where it stands.
	await _until(61.28)
	_room.spawn(&"testdrum", &"testdrum", DRUM_HOME)
	_room.stand(&"djembe", DJEMBE_HOME)
	_room.stand(KitItem.KIND, KIT_HOME)
	_stand_the_railing()
	_publish_the_weather()
	await _until(61.46)
	_check_drum_strike()
	_check_djembe_slap()
	_check_pad_hit()
	_check_railing_strike()
	await _until(61.56)
	_check_weather_asked()
	await _until(61.76)
	_check_looper_layer()
	await _until(61.92)
	_check_ring_pulled()
	await _until(61.98)
	_take_back_the_looper()
	# A music box (slice 47): the guest's peg, pressed at 62.02, is a note in my MUSIC BOX item by 62.14.
	await _until(62.14)
	_check_music_box_peg()
	await _until(62.26)
	_take_back_the_music_box()
	# A string across the room (slice 48): the guest's tie at 62.3 is in my room's row by 62.36, and
	# its pluck at 62.36 a note on TAKE_TRACK by 62.5.
	await _until(62.36)
	_check_string_tied()
	await _until(62.5)
	_check_string_take()
	# A marble run (slice 49): the guest's blocks at 62.56 are in my room's row by 62.62, its one outside
	# the lattice refused; my rings over MARBLE_BAR published for the guest to set its own beside.
	await _until(62.62)
	_check_and_publish_the_marbles()
	# A theremin (slice 50): the guest's glide from 62.72, sent at 62.86, is a take on TAKE_TRACK by 62.92.
	await _until(62.92)
	_check_theremin_take()
	# A modular wall (slice 51): the guest's cable and knob at 62.94 are my room's row by 63.0, its
	# second cable into the same input refused, and its knob's turn heard here as it streamed.
	await _until(63.0)
	_check_the_modular()
	# The modular recorded (slice 52): the guest's take from 63.06, ended at 63.26, is an audio take on
	# TAKE_TRACK by 63.62, which I render from what reached me.
	await _until(63.62)
	_check_the_modular_take()

	# How much of the time before the end the work took: the end has moved twelve times as it grew.
	if DAW.backend is GodotBackend:
		print("engine: %s" % ("native lanes" if (DAW.backend as GodotBackend).lanes != null else "players"))
	# The world into the modular (slice 53): the guest's weather into my VCF's CV at 63.74 is my row by
	# 63.8, and my render of the storm's bar through it is published for the guest's.
	await _until(63.8)
	_check_the_world_patched()
	# The grain cloud recorded (slice 55): the guest's grains from 64.08, its take ended at 64.3, are
	# an audio take on TAKE_TRACK by 64.4, which I render from my own sound.
	await _until(64.4)
	_check_the_grain_take()
	# The lyrics in the booth (slice 56): the guest's two lines from 64.52 and its TAP at 64.6.
	await _until(64.7)
	_check_the_guests_tap()

	print("host work done at %.2fs of 64.76" % ((Time.get_ticks_msec() - _start) / 1000.0 - _shift))
	await _until(64.76)
	Session.leave()
	check("ending the session leaves the host solo", Session.role == Session.Role.SOLO)
	check("with its own mix still open", DAW.is_live() and DAW.state.track(2).volume > 0.12)
	if not is_nan(restore):
		DAW.set_track_volume(2, restore)
	if not is_nan(tempo_restore):
		DAW.set_tempo(tempo_restore)
	DAW.set_metronome(false)
	if monitor_restore >= 0:
		DAW.set_track_monitor(3, monitor_restore)
	if not is_nan(send_restore):
		var first := _first_send(DAW.state)
		DAW.set_send_volume(first[0], first[1], send_restore)
	DAW.set_lyrics("")
	await _until(64.83)


## The guest's rope (slice 20), as my DAW has it: a key send from ROPE_FROM into ROPE_TO and a
## compressor on ROPE_TO to hear it, listening to it on the built-in engine, as one step named for
## the rope, which one undo takes back. On Reaper the bridge's Batch is Reaper's own one step; it is
## taken back by hand.
func _check_rope() -> void:
	var n := Sidechain.key_send(ROPE_FROM, ROPE_TO)
	var comp := Sidechain.compressor_on(ROPE_TO)
	check("the guest's rope is my key send from track %d into %d (send %d)" % [ROPE_FROM, ROPE_TO, n], n > 0)
	check("with a compressor on %d to hear it (%d)" % [ROPE_TO, comp], comp >= 0)
	var engine := DAW.backend as GodotBackend
	if engine != null and comp >= 0:
		var effect := AudioServer.get_bus_effect(engine._bus[ROPE_TO], 1 + comp) as AudioEffectCompressor
		check("which listens to the key (%s)" % (effect.sidechain if effect != null else &"none"),
				effect != null and effect.sidechain == StringName(GodotBackend.send_bus(ROPE_FROM, ROPE_TO)))
	if _reaper_resource == "":
		var last: String = str(DAW.state.undo_names[DAW.state.undo_depth - 1]) if DAW.state.undo_depth > 0 else ""
		var named := "%s > %s: rope" % [DAW.state.track(ROPE_FROM).display_name(), DAW.state.track(ROPE_TO).display_name()]
		check("as one step, called the rope (%s)" % last, last == named)
		DAW.undo()
		check("which one undo takes back whole", Sidechain.key_send(ROPE_FROM, ROPE_TO) == 0
				and DAW.state.track(ROPE_TO).plugins().size() == _rope_plugins_were)
	else:
		if comp >= 0 and DAW.state.track(ROPE_TO).plugins().size() > _rope_plugins_were:
			DAW.remove_fx(ROPE_TO, comp)
		if n > 0:
			DAW.remove_send(ROPE_FROM, n)


## The guest's write bead pass (slice 22), as my DAW has it: BEAD_TRACK's volume lane, its points
## at the guest's song positions from BEAD_SONG, one each WriteBead.POINT_SECONDS, rising as the
## guest's hand did, and the lane let go again. One step named for the lane, which one undo takes
## back; on Reaper the lane and the level are put back by hand.
func _check_written_lane() -> void:
	var lane := WriteBead.lane_now(BEAD_TRACK, "volume")
	var inside := lane.filter(func(pt): return absf(float(pt[0]) - BEAD_SONG - BEAD_SECONDS * 0.5) <= BEAD_SECONDS * 0.5 + 0.0001)
	var spaced := true
	for i in inside.size():
		spaced = spaced and absf(float(inside[i][0]) - (BEAD_SONG + i * WriteBead.POINT_SECONDS)) < 0.002
	var wanted := roundi(BEAD_SECONDS / WriteBead.POINT_SECONDS) + 1
	check("the guest's bead pass is my track %d's lane at its song positions from %.1f (%d of %d points)"
			% [BEAD_TRACK, BEAD_SONG, inside.size(), wanted], inside.size() == wanted and spaced)
	check("rising as its hand did (%s)" % [[inside[0][1], inside[-1][1]] if not inside.is_empty() else []],
			not inside.is_empty() and float(inside[-1][1]) > float(inside[0][1]) + 1.0)
	check("and the lane is followed again", not DAW.backend.lane_held(BEAD_TRACK, "volume"))
	if _reaper_resource == "":
		var last: String = str(DAW.state.undo_names[DAW.state.undo_depth - 1]) if DAW.state.undo_depth > 0 else ""
		check("as one step, named for the lane (%s)" % last, last.ends_with("level automation"))
		DAW.undo()
		check("which one undo takes back", ReaperBackend._same_lane(WriteBead.lane_now(BEAD_TRACK, "volume"), _bead_was))
	else:
		DAW.set_automation(BEAD_TRACK, "volume", _bead_was)
		DAW.set_track_volume(BEAD_TRACK, _bead_volume_was)


## The guest's latched clap (slice 19), as my DAW has it: CLAP_TRACK's mute toggled from what it
## was, and left so once its hands parted. Put back.
func _check_clap_mute() -> void:
	var t := DAW.state.track(CLAP_TRACK)
	check("the guest's latched clap toggled my track %d's mute (%s, was %s)" % [CLAP_TRACK, t.mute, _clap_was],
			t.mute != _clap_was)
	DAW.set_track_mute(CLAP_TRACK, _clap_was)


## The guest's placing on its stage table (slice 18), as my DAW has it: the stage track's pan and
## level where the guest put its voice, the last step in my history named for it as a placing,
## which one undo takes back whole. On Reaper its OSC writes stay Reaper's own undo points, so
## the track is put back by hand.
func _check_stage_placing() -> void:
	var t := DAW.state.track(STAGE_TRACK)
	var db := DAW.taper_to_db(t.volume)
	check("the guest's placing on its stage table moved my track %d's pan and level at once (%s, %.2f dB)"
			% [STAGE_TRACK, StageTable.pan_words(t.pan), db], absf(t.pan - STAGE_PAN) < 0.002 and absf(db - STAGE_DB) < 0.05)
	if _reaper_resource == "":
		var last: String = str(DAW.state.undo_names[DAW.state.undo_depth - 1]) if DAW.state.undo_depth > 0 else ""
		check("as one step, called a placing (%s)" % last, last == "%s: place" % t.display_name())
		DAW.undo()
		check("which one undo takes back whole (%.3f %.3f)" % [t.pan, t.volume],
				absf(t.pan - float(_stage_was[0])) < 0.0001 and absf(t.volume - float(_stage_was[1])) < 0.0001)
	else:
		DAW.set_track_pan(STAGE_TRACK, float(_stage_was[0]))
		DAW.set_track_volume(STAGE_TRACK, float(_stage_was[1]))


## The guest's bent take (slice 14), as my DAW has it: its note, and its keyboard's bend as a
## control at the song the guest moved the wheel at, then back at rest at the note-off.
func _check_bent_take() -> void:
	var expected_path := "/tmp/r3d_probe_bend_%d.json" % _port
	var expected = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	DirAccess.remove_absolute(expected_path)
	check("the guest wrote down where it bent", expected is Dictionary)
	if not expected is Dictionary:
		return
	var takes: Array = DAW.state.track(TAKE_TRACK).items.filter(func(it: MixState.ItemState) -> bool:
			return it.start > BENT_SONG - 0.1 and it.start < BENT_SONG + 1.0)
	check("the guest's bent take is an item on track %d (%d)" % [TAKE_TRACK, takes.size()], takes.size() == 1)
	if takes.size() != 1:
		return
	var item: MixState.ItemState = takes[0]
	var notes := MidiTake.unpack_relative(item.notes, item.start)
	var bends: Array = []
	for o in range(0, item.controls.size() - DawKitClip.CONTROL_WIDTH + 1, DawKitClip.CONTROL_WIDTH):
		if int(item.controls[o + 1]) == DawKitClip.PITCH_BEND:
			bends.append([item.start + item.controls[o], int(item.controls[o + 2])])
	var bent: Array = bends.filter(func(b: Array) -> bool: return b[1] == BEND_VALUE)
	var off := float(notes[0][1]) if notes.size() == 1 else NAN
	print("bend: placed ", bends, " expected ", expected)
	check("with its held note (%s)" % [notes], notes.size() == 1 and int(notes[0][2]) == BENT_PITCH)
	check("and the guest's bend at 56.2 is a control in it at that song, during the note, worst %.2fms (%s)" % [
			absf(float(bent[0][0]) - float(expected["at"])) * 1000.0 if bent.size() == 1 else -1.0, bends],
			bent.size() == 1 and notes.size() == 1 and absf(float(bent[0][0]) - float(expected["at"])) < TAKE_TOLERANCE
			and float(bent[0][0]) > float(notes[0][0]) and float(bent[0][0]) < off)
	check("then back at rest at the note-off", bends.size() == 2 and bends[1][1] == 0
			and absf(float(bends[1][0]) - off) <= MidiTake.CONTROL_GAP + 0.0001)


## The guest's tilted keytar take (slice 15), as my DAW has it: its note, and the bend its neck
## hand's tilt made, risen to what the guest's keys had and back at rest at the note-off.
func _check_tilted_take() -> void:
	var expected_path := "/tmp/r3d_probe_tilt_%d.json" % _port
	var expected = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	DirAccess.remove_absolute(expected_path)
	check("the guest wrote down how far its tilt bent", expected is Dictionary)
	if not expected is Dictionary:
		return
	var takes: Array = DAW.state.track(TAKE_TRACK).items.filter(func(it: MixState.ItemState) -> bool:
			return it.start > TILT_SONG - 0.1 and it.start < TILT_SONG + 1.0)
	check("the guest's tilted keytar take is an item on track %d (%d)" % [TAKE_TRACK, takes.size()], takes.size() == 1)
	if takes.size() != 1:
		return
	var item: MixState.ItemState = takes[0]
	var notes := MidiTake.unpack_relative(item.notes, item.start)
	var bends: Array = []
	for o in range(0, item.controls.size() - DawKitClip.CONTROL_WIDTH + 1, DawKitClip.CONTROL_WIDTH):
		if int(item.controls[o + 1]) == DawKitClip.PITCH_BEND:
			bends.append([item.start + item.controls[o], int(item.controls[o + 2])])
	print("tilt: placed ", bends, " expected ", expected)
	var held := int(bends[-2][1]) if bends.size() >= 2 else 0
	check("with its keytar note (%s)" % [notes], notes.size() == 1 and int(notes[0][2]) == TILT_PITCH)
	check("and its bend, risen to the %d the tilt made it, during the note (%d)" % [int(expected["value"]), held],
			bends.size() >= 3 and absi(held - int(expected["value"])) <= 8 and notes.size() == 1
			and float(bends[0][0]) > float(notes[0][0]) and float(bends[-2][0]) < float(notes[0][1]))
	check("then back at rest at the note-off", not bends.is_empty() and int(bends[-1][1]) == 0)


## The guest's snapped shaker take (slice 17), as my DAW has it: its snapped hit half way to the
## sixteenth it was played 20 ms before, by the guest's grid and by mine; its unsnapped one where it
## was played; and both hits as they reached me, each with its snap flag and its Foley take.
func _check_snapped_take() -> void:
	var expected_path := "/tmp/r3d_probe_snap_%d.json" % _port
	var expected = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	DirAccess.remove_absolute(expected_path)
	check("the guest wrote down where it shook", expected is Dictionary)
	if not expected is Dictionary:
		return
	var first := float(expected["first"])
	var second := float(expected["second"])
	var takes: Array = DAW.state.track(TAKE_TRACK).items.filter(func(it: MixState.ItemState) -> bool:
			return it.start > SNAP_SONG - 0.1 and it.start < SNAP_SONG + 1.0)
	check("the guest's shaker take is an item on track %d (%d)" % [TAKE_TRACK, takes.size()], takes.size() == 1)
	if takes.size() != 1:
		return
	var item: MixState.ItemState = takes[0]
	var notes := MidiTake.unpack_relative(item.notes, item.start)
	notes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	print("snap: placed ", notes, " expected ", expected)
	check("with both its hits, as the shaker (%s)" % [notes], notes.size() == 2
			and notes.all(func(n: Array) -> bool: return int(n[2]) == 82 and int(n[4]) == HitRecorder.CHANNEL))
	if notes.size() != 2:
		return
	var mine := HitRecorder.snapped_at(first, DAW.state)
	check("its snapped hit, played 20 ms early, landed 10 ms early by its grid and mine (%.4f for %.4f, %.4f)" % [
			float(notes[0][0]), float(expected["snapped"]), mine],
			absf(float(notes[0][0]) - float(expected["snapped"])) < 0.0005 and absf(mine - float(expected["snapped"])) < 0.0005
			and absf(float(notes[0][0]) - first - SNAP_EARLY * HitRecorder.SNAP_PULL) < 0.0005)
	check("and its unsnapped one where it was played (%.4f for %.4f)" % [float(notes[1][0]), second],
			absf(float(notes[1][0]) - second) < 0.0005)
	var shakes := _item_hits.filter(func(h: Array) -> bool: return h[0] == &"shaker" and h.size() == 7)
	var on := shakes.filter(func(h: Array) -> bool: return absf(float(h[3]) - first) < 0.0001)
	var off := shakes.filter(func(h: Array) -> bool: return absf(float(h[3]) - second) < 0.0001)
	check("both hits reached me with their snap and their take, at the song they were played to (%s)" % [shakes],
			on.size() == 1 and bool(on[0][4]) and int(on[0][5]) == 5
			and off.size() == 1 and not bool(off[0][4]) and int(off[0][5]) == 6)


## The guest's take, as the host's DAW has it, against when the guest heard each note played.
func _check_placed_take() -> void:
	var expected_path := "/tmp/r3d_probe_take_%d.json" % _port
	var expected = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	DirAccess.remove_absolute(expected_path)
	check("the guest wrote down what it played", expected is Dictionary)
	if not expected is Dictionary:
		return
	var item: MixState.ItemState = null
	for it in DAW.state.track(TAKE_TRACK).items:
		if it.name == "Grace take 1":
			item = it
	check("the guest's take is an item on track %d" % TAKE_TRACK, item != null)
	check("and the room was told", _notices.any(func(t): return t.begins_with("Grace played 4 notes onto")))
	if item == null:
		return
	var placed := MidiTake.unpack_relative(item.notes, item.start)
	check("with all four of its notes (%d)" % placed.size(), placed.size() == 4)
	var worst := 0.0
	var all_there := true
	for e in expected["notes"]:
		var found: Array = []
		for n in placed:
			if int(n[2]) == int(e[0]):
				found = n
		if found.is_empty():
			all_there = false
			continue
		worst = maxf(worst, absf(found[0] - float(e[1])))
		if e[2] != null:
			worst = maxf(worst, absf(found[1] - float(e[2])))
	check("each where the guest heard it played, worst %.2fms" % (worst * 1000.0),
			all_there and worst < TAKE_TOLERANCE)
	print("take: placed ", placed, " expected ", expected["notes"], " worst_ms %.3f" % (worst * 1000.0))
	var hanging: Array = placed.filter(func(n): return int(n[2]) == int(expected["hanging"]))
	check("a note still down when recording stopped ends with the take",
			hanging.size() == 1 and absf(hanging[0][1] - item.end()) < 0.002)


## The guest's recording, as the host placed it: every clap the guest's microphone heard, where
## in the song the guest heard the click it clapped on. The tone clicks on whole song seconds.
## The host records its own output: the click, out of the null sink, back in through its
## monitor as the host's microphone (PULSE_SOURCE), where the song has nothing else playing. Each
## click in the take should be on a beat. What is measured is the whole chain: the engine's
## clock, the click player kept to it, the output's latency taken off what the host hears, and
## the input's taken off what the microphone gives.
func _host_records_itself() -> void:
	var ha := Session.host_audio
	# The default input, which the script points at the null sink's monitor (PULSE_SOURCE): never
	# this machine's own microphone.
	ha.input_device = ""
	ha.target_track = HOST_TAKE_TRACK
	ha.record_with_host = true
	_audio_placed = {}
	DAW.set_metronome(true)
	# The tempo changes in the middle of the take: held, then ramped down to three quarters over
	# four beats. The clicks and the notes below follow it, and are measured against it.
	var tempo := DAW.state.tempo
	var turn := ceilf((HOST_TAKE_AT + 0.6) * tempo / 60.0)
	DAW.set_tempo_map([[0.0, tempo, DawKitTempoMap.HOLD], [turn, tempo, DawKitTempoMap.RAMP_BEATS],
			[turn + 4.0, tempo * 0.75, DawKitTempoMap.HOLD]])
	var map := DAW.state.tempo_map()
	# A MIDI item under the take, a short high note on every off-beat, played by the engine's
	# instrument: between the clicks, so each can be found on its own.
	var notes: Array = []
	var nb := ceilf(map.beat_at(HOST_TAKE_AT)) + 0.5
	while map.seconds_at(nb) < HOST_TAKE_AT + 6.0:
		var t := map.seconds_at(nb)
		notes.append([t, t + 0.08, 84, 120, 0])
		nb += 1.0
	DAW.state.track(HOST_MIDI_TRACK).items.clear()
	DAW.insert_midi_take(HOST_MIDI_TRACK, HOST_TAKE_AT, HOST_TAKE_AT + 6.0, notes, "Off-beats")
	# And their track's fader automated: held, then down 9 dB in a straight line over three seconds,
	# then held there. Each note's level in the take is measured against it.
	DAW.set_automation(HOST_MIDI_TRACK, "volume", HOST_RAMP)
	var midi: MixState.ItemState = DAW.state.track(HOST_MIDI_TRACK).items[0]
	(DAW.backend as GodotBackend).midi_stream(midi, true)
	DAW.seek(HOST_TAKE_AT)
	await _until(7.6)
	check("my microphone is open (%s)" % ha.input_device, ha.mic_open())
	var gm := Session.guest_midi
	gm.target_track = HOST_KEYS_TRACK
	gm.record_with_host = true
	DAW.state.track(HOST_KEYS_TRACK).items.clear()
	var reseeks_before: int = (DAW.backend as GodotBackend).reseeks
	DAW.transport_record()
	# A key of my own, heard through its track, a quarter of a beat after a click: between the
	# click and the off-beat note, so its sound can be found in the take on its own.
	await _until(9.0)
	while absf(fposmod(map.beat_at(DAW.state.position_seconds), 1.0) - 0.22) > 0.04:
		await get_tree().process_frame
	gm.note_on(96, 127)
	await get_tree().create_timer(0.1).timeout
	gm.note_off(96)
	await _until(11.2)
	var reseeks: int = (DAW.backend as GodotBackend).reseeks - reseeks_before
	print("host take reseeks: %d" % reseeks)
	check("nothing put back on the clock while I recorded (%d)" % reseeks, reseeks == 0)
	DAW.transport_stop()
	await _until(11.6)
	ha.record_with_host = false
	check("my own recording was placed (%s)" % [_audio_placed], not _audio_placed.is_empty()
			and int(_audio_placed.get("track", 0)) == HOST_TAKE_TRACK)
	if _audio_placed.is_empty():
		return
	var wav := FileAccess.get_file_as_bytes(_audio_placed["path"])
	var start: float = _audio_placed["start"]
	_measure_onsets("clicks", wav, start, map, 0.0)
	_measure_onsets("notes", wav, start, map, 0.5)
	_measure_ramp(wav, start, map)
	DAW.set_automation(HOST_MIDI_TRACK, "volume", [])
	var at_turn := map.seconds_at(turn + 4.0) - start
	check("and the take runs through the tempo's change (%.2fs in, of %.2fs)" % [at_turn, _audio_placed["seconds"]],
			at_turn > 1.0 and at_turn < float(_audio_placed["seconds"]) - 0.3)
	# My key: where its sound is in the take against where the keys' take put the note. The same
	# moment, if what the host hears of its own keys is accounted for.
	var keys: Array = DAW.state.track(HOST_KEYS_TRACK).items.filter(
			func(it: MixState.ItemState) -> bool: return not it.notes.is_empty())
	check("my key was taken down on its track (%d)" % keys.size(), keys.size() == 1)
	if keys.size() == 1:
		var stamped: float = keys[0].start + keys[0].notes[0]
		var centre := int((stamped - start) * AudioTake.RATE)
		var loudest := 0
		for f in range(centre - AudioTake.RATE / 25, centre + AudioTake.RATE / 25):
			loudest = maxi(loudest, absi(wav.decode_s16(AudioTake.HEADER_BYTES + f * 2)))
		var heard_at := NAN
		for f in range(centre - AudioTake.RATE / 25, centre + AudioTake.RATE / 25):
			if absi(wav.decode_s16(AudioTake.HEADER_BYTES + f * 2)) > loudest / 2:
				heard_at = start + float(f) / AudioTake.RATE
				break
		print("host take key: stamped %.4f heard %.4f off_ms %.2f monitor_latency_ms %.1f" % [stamped, heard_at,
				(heard_at - stamped) * 1000.0, Session.guest_midi.synth.latency_seconds() * 1000.0])
		check("my key's sound is where its note was put (%.2fms)" % ((heard_at - stamped) * 1000.0),
				absf(heard_at - stamped) < HOST_TAKE_TOLERANCE)


## Each beat inside the take (or each point `phase` of a beat on), through the tempo map, after
## its first half second: the onset there is the first sample within 40ms over half the loudest
## one there. Checked to be on time on average and each within the tolerance of that average.
func _measure_onsets(what: String, wav: PackedByteArray, start: float, map: DawKitTempoMap, phase: float) -> void:
	var offs: Array[float] = []
	var peaks: Array[int] = []
	var frames := (wav.size() - AudioTake.HEADER_BYTES) / 2
	var nth := ceilf(map.beat_at(start + 0.5) - phase) + phase
	var b := map.seconds_at(nth)
	while b < start + float(frames) / AudioTake.RATE - 0.1:
		var centre := int((b - start) * AudioTake.RATE)
		var from := maxi(centre - AudioTake.RATE / 25, 0)
		var to := mini(centre + AudioTake.RATE / 25, frames)
		var loudest := 0
		for f in range(from, to):
			loudest = maxi(loudest, absi(wav.decode_s16(AudioTake.HEADER_BYTES + f * 2)))
		peaks.append(loudest)
		if loudest > 1500:
			for f in range(from, to):
				if absi(wav.decode_s16(AudioTake.HEADER_BYTES + f * 2)) > loudest / 2:
					offs.append(start + float(f) / AudioTake.RATE - b)
					break
		nth += 1.0
		b = map.seconds_at(nth)
	var mean := 0.0
	for o in offs:
		mean += o
	mean /= maxf(offs.size(), 1)
	var spread := 0.0
	for o in offs:
		spread = maxf(spread, absf(o - mean))
	print("host take %s: %d of %d (peaks %s), offsets_ms %s mean_ms %.2f spread_ms %.2f out_latency_ms %.1f" % [
			what, offs.size(), peaks.size(), peaks, offs.map(func(o): return snappedf(o * 1000.0, 0.01)),
			mean * 1000.0, spread * 1000.0, AudioServer.get_output_latency() * 1000.0])
	check("%s on every one in my take (%d of %d)" % [what, offs.size(), peaks.size()],
			peaks.size() >= 5 and offs.size() == peaks.size())
	check("%s on time, on average (%.2fms)" % [what, mean * 1000.0], absf(mean) < HOST_TAKE_TOLERANCE)
	check("%s, each of them (%.2fms from the average)" % [what, spread * 1000.0], spread < HOST_TAKE_TOLERANCE)


## Each off-beat note's level in the take, in dB, against the ones before the ramp:
## the difference is the lane's value at that note, to within HOST_RAMP_TOLERANCE_DB.
func _measure_ramp(wav: PackedByteArray, start: float, map: DawKitTempoMap) -> void:
	var frames := (wav.size() - AudioTake.HEADER_BYTES) / 2
	var rows: Array = []
	var nth := ceilf(map.beat_at(start + 0.5) - 0.5) + 0.5
	var b := map.seconds_at(nth)
	while b < start + float(frames) / AudioTake.RATE - 0.1:
		var from := maxi(int((b - start - 0.01) * AudioTake.RATE), 0)
		var to := mini(int((b - start + 0.08) * AudioTake.RATE), frames)
		# The power over the note, not its loudest sample, which is a matter of where the
		# waveform's peak falls; and the lane in the middle of it, as the ramp goes on falling.
		var power := 0.0
		for f in range(from, to):
			var v := float(wav.decode_s16(AudioTake.HEADER_BYTES + f * 2))
			power += v * v
		power = maxf(power / maxf(to - from, 1), 1.0)
		var middle := b - 0.01 + 0.5 * float(to - from) / AudioTake.RATE
		rows.append([b, 10.0 * log(power) / log(10.0), DawKitAutomation.value_in(HOST_RAMP, middle)])
		nth += 1.0
		b = map.seconds_at(nth)
	var flat: Array = rows.filter(func(r): return r[2] > -0.001)
	var reference := 0.0
	for r in flat:
		reference += r[1]
	reference /= maxf(flat.size(), 1)
	var worst := 0.0
	var ramped := 0
	var off: Array = []
	for r in rows:
		var d: float = (r[1] - reference) - r[2]
		off.append([snappedf(r[2], 0.1), snappedf(r[1] - reference, 0.1)])
		worst = maxf(worst, absf(d))
		if r[2] < -0.5:
			ramped += 1
	print("host take ramp: [lane dB, heard dB] %s worst_db %.2f" % [off, worst])
	check("the notes follow their fader's automation (%d of %d down the ramp, worst %.2f dB off)" % [ramped, rows.size(), worst],
			flat.size() >= 2 and ramped >= 3 and rows.any(func(r): return r[2] < -5.0) and worst < HOST_RAMP_TOLERANCE_DB)


## A passage rendered with its stems, and the stem measured: a track of its own with a note on
## every half second, its fader dropped 12 dB halfway by its automation. Each note's onset in
## the file against where it is in the song, and each note's level against the lane.
func _render_and_measure() -> void:
	var count := DAW.state.track_indices().size()
	DAW.add_track(count + 1, "Render probe")
	var track := count + 1
	var at := RENDER_FROM + 0.5
	var notes: Array = []
	for i in 6:
		notes.append([at + i * 0.5, at + i * 0.5 + 0.08, 84, 120, 0])
	DAW.insert_midi_take(track, RENDER_FROM, RENDER_FROM + 3.5, notes, "Render probe")
	# Sent to the reverb, so its last notes ring on past the range: the render's tail.
	for index in DAW.state.track_indices():
		if DAW.state.track(index).name == "Verb Rtn":
			DAW.create_send(track, index)
	var part := (DAW.backend as GodotBackend).midi_stream(DAW.state.track(track).items[0], true)
	# The instrument's own attack: how far into its first note its sound reaches half its peak,
	# in the item's own rendered sound. That much after the note is on time.
	var first := int((at - RENDER_FROM) * part.mix_rate)
	var part_peak := 0
	for f in range(first, first + part.mix_rate / 10):
		part_peak = maxi(part_peak, absi(part.data.decode_s16(f * 4)))
	var attack_ms := NAN
	for f in range(first, first + part.mix_rate / 10):
		if absi(part.data.decode_s16(f * 4)) > part_peak / 2:
			attack_ms = (f - first) * 1000.0 / part.mix_rate
			break
	var drop := at + 1.25
	DAW.set_automation(track, "volume", [[0.0, 0.0, DawKitAutomation.HOLD], [drop, -12.0, DawKitAutomation.HOLD]])
	DAW.set_loop_range(RENDER_FROM, RENDER_FROM + 3.5)
	DAW.set_looping(true)
	var done: Array = []
	DAW.render_finished.connect(func(files, problems): done.append([files, problems]), CONNECT_ONE_SHOT)
	var began := Time.get_ticks_msec()
	DAW.render(true)
	while done.is_empty() and Time.get_ticks_msec() - began < 8000:
		await get_tree().process_frame
	var seconds := (Time.get_ticks_msec() - began) / 1000.0
	check("I rendered the loop with its stems (%.2fs, %s)" % [seconds, done], not done.is_empty()
			and (done[0][1] as PackedStringArray).is_empty() and (done[0][0] as PackedStringArray).size() == count + 2)
	if done.is_empty():
		return
	var files: PackedStringArray = done[0][0]
	var stem := DawKitAudioFile.read(files[files.size() - 1])
	var mix := DawKitAudioFile.read(files[0])
	var rate: int = stem["rate"]
	var samples: PackedFloat32Array = stem["samples"]
	var range_frames := int(roundf(3.5 * rate))
	var tail_frames := int(stem["frames"]) - range_frames
	check("the stem is the loop and a tail (%.3fs and %.3fs)" % [range_frames / float(rate), tail_frames / float(rate)],
			tail_frames >= 0 and tail_frames <= int(DAWBackend.RENDER_TAIL_SECONDS * rate)
			and int(mix["frames"]) == int(stem["frames"]))
	# After the range nothing new begins: the song stopped there, and what is left only rings out.
	var mix_samples: PackedFloat32Array = mix["samples"]
	var windows: Array = []
	for w in range(range_frames + rate / 20, int(mix["frames"]) - rate / 10, rate / 10):
		var pk := 0.0
		for f in range(w, w + rate / 10):
			pk = maxf(pk, absf(mix_samples[f * 2]))
		windows.append(linear_to_db(maxf(pk, 1e-9)))
	var rises := 0
	for i in range(1, windows.size()):
		# A reverb's ring wavers by a dB or two; a note beginning is far more.
		if windows[i] > windows[i - 1] + 3.0:
			rises += 1
	print("render tail: %.3fs, mix peak per 100 ms %s" % [tail_frames / float(rate), windows.map(func(d): return snappedf(d, 0.1))])
	check("the reverb rings on after the range, falling away to silence (%.2fs, %d rises, ends at %.1f dB)" % [
			tail_frames / float(rate), rises, windows[-1] if not windows.is_empty() else 0.0],
			tail_frames > rate / 2 and windows.size() >= 3 and rises == 0 and windows[-1] < -60.0
			and windows[-1] < windows[0] - 40.0)
	var offs: Array = []
	var levels: Array = []
	for n in notes:
		var centre := int((float(n[0]) - RENDER_FROM) * rate)
		var loudest := 0.0
		for f in range(maxi(centre - rate / 25, 0), centre + rate / 10):
			loudest = maxf(loudest, absf(samples[f * 2]))
		levels.append(20.0 * log(maxf(loudest, 0.000001)) / log(10.0))
		for f in range(maxi(centre - rate / 25, 0), centre + rate / 25):
			if absf(samples[f * 2]) > loudest * 0.5:
				offs.append((f - centre) * 1000.0 / rate - attack_ms)
				break
	var spread := 0.0
	for o in offs:
		spread = maxf(spread, absf(o))
	var step: float = (levels[3] + levels[4] + levels[5]) / 3.0 - (levels[0] + levels[1] + levels[2]) / 3.0
	print("render: onsets_ms %s (less an attack of %.2fms) levels_db %s step_db %.2f render_seconds %.2f" % [
			offs.map(func(o): return snappedf(o, 0.01)), attack_ms, levels.map(func(l): return snappedf(l, 0.01)), step, seconds])
	check("each note is where it is in the song (%d of %d, worst %.2fms)" % [offs.size(), notes.size(), spread],
			offs.size() == notes.size() and spread < RENDER_TOLERANCE_MS)
	check("and the fader's drop is in the stem (%.2f dB)" % step, absf(step + 12.0) < 0.5)
	var mix_peak := 0.0
	for v in (mix["samples"] as PackedFloat32Array):
		mix_peak = maxf(mix_peak, absf(v))
	check("the mix has the song in it (peak %.3f)" % mix_peak, mix_peak > 0.05)
	await get_tree().create_timer(0.2).timeout
	check("and the room was told", _notices.any(func(t): return t.begins_with("Rendered ")))
	for f in files:
		DirAccess.remove_absolute(f)
	DirAccess.remove_absolute(files[0].get_base_dir())
	DAW.set_looping(false)


## A recording counted in, heard at the master: a bar of the click alone before the take, on the
## beats before the record point, with the song silent under it -- and the song back from there.
## With `play`, the count before playback: the same, played rather than recorded. With `song`,
## pre-roll: the song heard under the count, and the take still from the record point.
func _count_in_and_measure(play := false, song_too := false) -> void:
	var engine := DAW.backend as GodotBackend
	var s := DAW.state
	Session.guest_midi.record_with_host = false
	DAW.transport_stop()
	DAW.set_metronome(true)
	DAW.set_count_in(1)
	DAW.set_count_in_play(play)
	DAW.set_pre_roll(song_too)
	var first_item := INF
	for index in s.track_indices():
		for it in s.track(index).items:
			first_item = minf(first_item, it.start)
	# Two bars into the song, so the count runs over it: none of it must be heard there.
	var map := s.tempo_map()
	var beat := ceilf(map.beat_at(first_item)) + 8.0
	if song_too:
		# Pre-roll: inside an item that sounds (a take, an import, notes), a beat and a bar in, so
		# the whole count runs over it and the song is there to hear under the click.
		for index in s.track_indices():
			for it in s.track(index).items:
				var b0 := ceilf(map.beat_at(it.start)) + 1.0 + s.beats_per_bar
				if not it.muted and (not it.source.is_empty() or not it.notes.is_empty()) \
						and map.seconds_at(b0) + 0.6 < it.end():
					beat = b0
	var at := map.seconds_at(beat)
	DAW.seek(at)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 4.0
	AudioServer.add_bus_effect(engine._master_bus, capture)
	await get_tree().process_frame
	# Lined up as a render is (MixRender): cleared, started and set going in one hold of the lock,
	# so the first frame captured is the first played, from where the count was told to start.
	AudioServer.lock()
	capture.clear_buffer()
	if play:
		DAW.transport_play()
	else:
		DAW.transport_record()
	var first_frame_at := (DAW.backend as GodotBackend).first_frame_at(s.position_seconds)
	engine._drive_meters(0.0)
	AudioServer.unlock()
	var from := s.count_in_start(at)
	check("%s counted in from a bar before (%.3fs to %.3fs)" % ["playing" if play else "recording", s.position_seconds, at],
			s.counting_in() and absf(s.position_seconds - (from - engine.count_in_lead)) < 0.001 and absf(s.count_in_to - at) < 0.001)
	var took_at := NAN
	var began := Time.get_ticks_msec()
	while s.position_seconds < at + 0.6 and Time.get_ticks_msec() - began < 5000:
		if is_nan(took_at) and (s.taking() if not play else not s.counting_in()):
			took_at = s.position_seconds
		await get_tree().process_frame
	DAW.transport_stop()
	var frames := capture.get_buffer(capture.get_frames_available())
	for i in range(AudioServer.get_bus_effect_count(engine._master_bus) - 1, -1, -1):
		if AudioServer.get_bus_effect(engine._master_bus, i) == capture:
			AudioServer.remove_bus_effect(engine._master_bus, i)
	DAW.set_count_in(0)
	DAW.set_count_in_play(false)
	DAW.set_pre_roll(false)
	check("and %s from the point it stood at on (%.3fs)" % ["played" if play else "took", took_at],
			absf(took_at - at) < 0.05 and (not play or not s.recording))
	var rate := AudioServer.get_mix_rate()
	var frame_of := func(t: float) -> int: return int(roundf((t - first_frame_at) * rate))
	var offs: Array = []
	var quiet := -INF
	for k in int(roundf(beat - map.beat_at(from))):
		var t := map.seconds_at(map.beat_at(from) + k)
		var centre: int = frame_of.call(t)
		var loudest := 0.0
		for f in range(maxi(centre - int(rate) / 25, 0), mini(centre + int(rate) / 25, frames.size())):
			loudest = maxf(loudest, absf(frames[f].x))
		for f in range(maxi(centre - int(rate) / 25, 0), mini(centre + int(rate) / 25, frames.size())):
			if loudest > 0.01 and absf(frames[f].x) > loudest * 0.5:
				offs.append((f - centre) * 1000.0 / rate)
				break
		# Between this click's ring and the next beat, nothing.
		for f in range(centre + int((DawKitMetronome.CLICK_SECONDS + 0.02) * rate),
				mini(frame_of.call(map.seconds_at(map.beat_at(t) + 1.0)) - int(rate) / 100, frames.size())):
			quiet = maxf(quiet, linear_to_db(maxf(absf(frames[f].x), 1e-9)))
	var song := -INF
	for f in range(frame_of.call(at + 0.05), mini(frame_of.call(at + 0.55), frames.size())):
		song = maxf(song, linear_to_db(maxf(absf(frames[f].x), 1e-9)))
	# On time on average, as the take's clicks are measured, and each the same as the others: the
	# first is not clipped.
	var mean := 0.0
	for o in offs:
		mean += o / maxf(offs.size(), 1)
	var worst := 0.0
	for o in offs:
		worst = maxf(worst, absf(o - mean))
	print("count-in%s: click onsets_ms %s, loudest between them %.1f dB, song after %.1f dB" % [
			" before playback" if play else (" with pre-roll" if song_too else ""), offs.map(func(o): return snappedf(o, 0.01)), quiet, song])
	if song_too:
		check("with the song under the count (%.1f dB between its clicks)" % quiet, quiet > -40.0)
		check("and on from the record point (%.1f dB)" % song, song > -30.0)
		return
	check("the count was a click on each of its beats (%d of %d, %.2fms on average, each within %.2fms of it)" % [
			offs.size(), int(roundf(beat - map.beat_at(from))), mean, worst],
			offs.size() == int(roundf(beat - map.beat_at(from))) and absf(mean) < COUNT_IN_TOLERANCE_MS
			and worst < COUNT_IN_SPREAD_MS)
	check("with nothing of the song under it (%.1f dB)" % quiet, quiet < -60.0)
	check("which plays from the record point on (%.1f dB)" % song, song > -30.0)


## The click through a change of time signature, heard at the master past the song's end, where
## nothing else plays: a bar of the song's own signature, then 6/8 -- a click on every eighth, the
## first of each bar the accent.
func _meter_and_measure() -> void:
	var engine := DAW.backend as GodotBackend
	var s := DAW.state
	DAW.transport_stop()
	DAW.set_metronome(true)
	var end := 0.0
	for index in s.track_indices():
		for it in s.track(index).items:
			end = maxf(end, it.start + it.length)
	var map := s.tempo_map()
	var meter := s.meter()
	var bar := ceilf(meter.bar_at(map.beat_at(end + 1.0)))
	var change := meter.beat_of_bar(bar + 1.0)
	var sig := Vector2i(s.beats_per_bar, s.beat_unit)
	DAW.set_time_signature_map([[0.0, sig.x, sig.y], [change, 6, 8]])
	meter = s.meter()
	var from := map.seconds_at(meter.beat_of_bar(bar))
	var to := map.seconds_at(meter.beat_of_bar(bar + 2.0))
	DAW.seek(from - 0.1)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 6.0
	AudioServer.add_bus_effect(engine._master_bus, capture)
	# Long enough for the engine to have made its window of clicks for the new meter while
	# stopped: made under the lock below, it would be put that much ahead of a song that was not
	# moving.
	await get_tree().create_timer(0.15).timeout
	AudioServer.lock()
	capture.clear_buffer()
	DAW.transport_play()
	var first_frame_at := (DAW.backend as GodotBackend).first_frame_at(s.position_seconds)
	engine._drive_meters(0.0)
	AudioServer.unlock()
	var began := Time.get_ticks_msec()
	while s.position_seconds < to + 0.1 and Time.get_ticks_msec() - began < 6000:
		await get_tree().process_frame
	DAW.transport_stop()
	var frames := capture.get_buffer(capture.get_frames_available())
	for i in range(AudioServer.get_bus_effect_count(engine._master_bus) - 1, -1, -1):
		if AudioServer.get_bus_effect(engine._master_bus, i) == capture:
			AudioServer.remove_bus_effect(engine._master_bus, i)
	DAW.set_time_signature_map([[0.0, sig.x, sig.y]])
	var rate := AudioServer.get_mix_rate()
	var offs: Array = []
	var peaks: Array = []
	var expected := meter.counts(meter.beat_of_bar(bar), meter.beat_of_bar(bar + 2.0))
	for c in expected:
		var centre := int(roundf((map.seconds_at(float(c[0])) - first_frame_at) * rate))
		var loudest := 0.0
		for f in range(maxi(centre - int(rate) / 50, 0), mini(centre + int(rate) / 50, frames.size())):
			loudest = maxf(loudest, absf(frames[f].x))
		peaks.append(loudest)
		for f in range(maxi(centre - int(rate) / 50, 0), mini(centre + int(rate) / 50, frames.size())):
			if loudest > 0.01 and absf(frames[f].x) > loudest * 0.5:
				offs.append((f - centre) * 1000.0 / rate)
				break
	var mean := 0.0
	for o in offs:
		mean += o / maxf(offs.size(), 1)
	var worst := 0.0
	for o in offs:
		worst = maxf(worst, absf(o - mean))
	# The accents are the bar's first counts; each louder than every count that is not one.
	var quietest_accent := INF
	var loudest_other := 0.0
	for i in expected.size():
		if expected[i][1]:
			quietest_accent = minf(quietest_accent, peaks[i])
		else:
			loudest_other = maxf(loudest_other, peaks[i])
	print("meter: %d/%d then 6/8 at beat %.1f, %d counts, onsets_ms %s, accents >= %.3f, others <= %.3f" % [sig.x, sig.y,
			change, expected.size(), offs.map(func(o): return snappedf(o, 0.01)), quietest_accent, loudest_other])
	check("the click counted a bar of %d/%d then one of 6/8 (%d of %d, %.2fms on average, each within %.2fms)" % [
			sig.x, sig.y, offs.size(), expected.size(), mean, worst],
			expected.size() == sig.x + 6 and offs.size() == expected.size()
			and absf(mean) < COUNT_IN_TOLERANCE_MS and worst < COUNT_IN_SPREAD_MS)
	check("accented on each bar's first count (%.3f against %.3f)" % [quietest_accent, loudest_other],
			quietest_accent > loudest_other * 1.2)


## The demo song's kick through a tempo ramp, heard at the master: a track named for the kick
## with an empty item past the song's end (so it plays the engine's own part), soloed, the click
## off, and the tempo gliding down by a quarter over four bars. Each kick where the map puts its
## beat, across the window the part changes over to at a loop's end.
func _parts_and_measure() -> void:
	var engine := DAW.backend as GodotBackend
	var s := DAW.state
	DAW.transport_stop()
	DAW.set_metronome(false)
	var was: Array = s.tempo_points.duplicate(true)
	var end := 0.0
	for index in s.track_indices():
		for it in s.track(index).items:
			end = maxf(end, it.start + it.length)
	var track := s.track_indices().size() + 1
	DAW.add_track(track, "Kick probe")
	# A track plays a demo part by being given it, not by its name.
	s.track(track).part = "kick"
	var tempo := s.tempo
	var loop := float(DemoSong.BARS * 4)
	var b0 := ceilf(s.tempo_map().beat_at(end + 2.0) / loop) * loop
	var points := [[0.0, tempo, DawKitTempoMap.HOLD], [b0 + 8.0, tempo, DawKitTempoMap.RAMP_BEATS],
			[b0 + 24.0, tempo * 0.75, DawKitTempoMap.HOLD]]
	DAW.set_tempo_map(points)
	var map := s.tempo_map()
	var it := MixState.ItemState.new()
	it.start = map.seconds_at(b0)
	it.length = map.seconds_at(b0 + 32.0) - it.start
	it.name = "Kick probe"
	s.track(track).items.append(it)
	DAW.set_track_solo(track, true)
	var from := map.seconds_at(b0 + 14.0)
	var to := map.seconds_at(b0 + 22.0)
	DAW.seek(from)
	var began := Time.get_ticks_msec()
	while not engine._waiting_roles().is_empty() or engine._part_window("kick", from).is_empty():
		if Time.get_ticks_msec() - began > 4000:
			break
		await get_tree().process_frame
	var ready_ms := Time.get_ticks_msec() - began
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 8.0
	AudioServer.add_bus_effect(engine._master_bus, capture)
	await get_tree().create_timer(0.1).timeout
	AudioServer.lock()
	capture.clear_buffer()
	DAW.transport_play()
	var first_frame_at := (DAW.backend as GodotBackend).first_frame_at(s.position_seconds)
	engine._drive_meters(0.0)
	AudioServer.unlock()
	began = Time.get_ticks_msec()
	while s.position_seconds < to and Time.get_ticks_msec() - began < 8000:
		await get_tree().process_frame
	DAW.transport_stop()
	var frames := capture.get_buffer(capture.get_frames_available())
	for i in range(AudioServer.get_bus_effect_count(engine._master_bus) - 1, -1, -1):
		if AudioServer.get_bus_effect(engine._master_bus, i) == capture:
			AudioServer.remove_bus_effect(engine._master_bus, i)
	DAW.set_track_solo(track, false)
	DAW.remove_track(track)
	DAW.set_tempo_map(was)
	var rate := AudioServer.get_mix_rate()
	var offs: Array = []
	var expected: Array = []
	for b in [14.5, 15.5, 16.0, 18.5, 20.0]:
		expected.append(b0 + b)
		var centre := int(roundf((map.seconds_at(b0 + b) - first_frame_at) * rate))
		var loudest := 0.0
		for f in range(maxi(centre - int(rate) / 50, 0), mini(centre + int(rate) / 50, frames.size())):
			loudest = maxf(loudest, absf(frames[f].x))
		for f in range(maxi(centre - int(rate) / 50, 0), mini(centre + int(rate) / 50, frames.size())):
			if loudest > 0.02 and absf(frames[f].x) > loudest * 0.5:
				offs.append((f - centre) * 1000.0 / rate)
				break
	var mean := 0.0
	for o in offs:
		mean += o / maxf(offs.size(), 1)
	var worst := 0.0
	for o in offs:
		worst = maxf(worst, absf(o - mean))
	# Where the kicks would be at the first tempo, for the size of what following the map is worth.
	var flat := (map.seconds_at(b0 + 20.0) - map.seconds_at(b0 + 14.5)) - (20.0 - 14.5) * 60.0 / tempo
	print("parts: kick through a ramp from beat %.0f, windows ready in %d ms, onsets_ms %s (at one tempo the last would be %.0f ms out)" % [
			b0, ready_ms, offs.map(func(o): return snappedf(o, 0.01)), flat * 1000.0])
	check("the demo kick follows the tempo's ramp (%d of %d, %.2fms on average, each within %.2fms)" % [
			offs.size(), expected.size(), mean, worst],
			offs.size() == expected.size() and absf(mean) < PARTS_TOLERANCE_MS and worst < PARTS_SPREAD_MS)


## A recording punched in and out: begun before the loop range and stopped after it, my take is
## the range and nothing either side.
func _punch_and_measure() -> void:
	var s := DAW.state
	var ha := Session.host_audio
	var map := s.tempo_map()
	var a := map.seconds_at(ceilf(map.beat_at(s.position_seconds)) + 4.0)
	var b := a + PUNCH_SECONDS
	DAW.set_looping(false)
	DAW.set_loop_range(a, b)
	DAW.set_punch(true)
	# Two armed tracks, each recording one side of the same input: one recording, both placed.
	var was_armed: Array = s.track_indices().filter(func(i): return s.track(i).rec_arm)
	for i in was_armed:
		DAW.set_track_rec_arm(i, false)
	DAW.set_track_input(HOST_TAKE_TRACK, "audio:#1")
	DAW.set_track_input(HOST_SIDE_TRACK, "audio:#2")
	DAW.set_track_rec_arm(HOST_TAKE_TRACK, true)
	DAW.set_track_rec_arm(HOST_SIDE_TRACK, true)
	ha.target_track = 0
	ha.record_with_host = true
	_audio_placed = {}
	_placed_all.clear()
	DAW.seek(a - 0.8)
	DAW.transport_record()
	var took := false
	while s.position_seconds < b + 0.4:
		took = took or s.taking()
		await get_tree().process_frame
	DAW.transport_stop()
	var began := Time.get_ticks_msec()
	while _placed_all.size() < 2 and Time.get_ticks_msec() - began < 1500:
		await get_tree().process_frame
	ha.record_with_host = false
	DAW.set_punch(false)
	DAW.set_loop_range(0.0, 0.0)
	DAW.set_track_rec_arm(HOST_TAKE_TRACK, false)
	DAW.set_track_rec_arm(HOST_SIDE_TRACK, false)
	DAW.set_track_input(HOST_TAKE_TRACK, "")
	DAW.set_track_input(HOST_SIDE_TRACK, "")
	for i in was_armed:
		DAW.set_track_rec_arm(i, true)
	var onto: Array = _placed_all.map(func(info): return int(info["track"]))
	var levels: Array = _placed_all.map(func(info): return _loudest(info["path"]))
	print("two inputs: onto %s, starts %s, peaks %s" % [onto, _placed_all.map(func(info): return snappedf(info["start"], 0.00001)),
			levels.map(func(v): return snappedf(v, 0.001))])
	check("one recording went onto both armed tracks, each its own side (%s)" % [onto],
			_placed_all.size() == 2 and onto.has(HOST_TAKE_TRACK) and onto.has(HOST_SIDE_TRACK))
	if _placed_all.size() == 2:
		check("from the same moment", absf(float(_placed_all[0]["start"]) - float(_placed_all[1]["start"])) < 0.000001)
		# The null sink's monitor carries the click on both sides alike.
		check("each side as loud as the other, as the sink sends them (%.3f, %.3f)" % [levels[0], levels[1]],
				levels.min() > 0.05 and absf(linear_to_db(levels[0]) - linear_to_db(levels[1])) < 0.5)
		_audio_placed = _placed_all[0] if int(_placed_all[0]["track"]) == HOST_TAKE_TRACK else _placed_all[1]
	var start: float = _audio_placed.get("start", NAN)
	var seconds: float = _audio_placed.get("seconds", NAN)
	print("punch: range %.3f-%.3f, take %.4f for %.4fs (in %+.1f ms, out %+.1f ms)" % [a, b, start, seconds,
			(start - a) * 1000.0, (start + seconds - b) * 1000.0])
	check("recording punched in at the range's start (%+.1f ms)" % ((start - a) * 1000.0),
			took and absf(start - a) < PUNCH_TOLERANCE)
	check("and out at its end (%+.1f ms)" % ((start + seconds - b) * 1000.0),
			absf(start + seconds - b) < PUNCH_TOLERANCE)
	for info in _placed_all:
		DirAccess.remove_absolute(info["path"])


## The loudest sample of a take's file.
func _loudest(path: String) -> float:
	var wav := FileAccess.get_file_as_bytes(path)
	var peak := 0
	for i in range(AudioTake.HEADER_BYTES, wav.size() - 1, 2):
		peak = maxi(peak, absi(wav.decode_s16(i)))
	return peak / 32767.0


## Guest: two sound files from this machine, sent to the host to bring in, and the room told.
func _send_files() -> void:
	var tone := PackedFloat32Array()
	for f in 48000:
		var v := 0.5 * sin(TAU * 440.0 * f / 48000.0)
		tone.append_array([v, v])
	var wav := OS.get_temp_dir().path_join("Probe Tone %d.wav" % _port)
	DawKitAudioFile.write_wav(wav, tone, 2, 48000)
	var flac := ProjectSettings.globalize_path("res://vendor/dawkit/tests/fixtures/audio/flac/s16_mono_0.flac")
	var why := Session.files.send(PackedStringArray([wav, flac]), SENT_TRACK, SENT_AT)
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 2500 and not _notices.any(func(t): return t.begins_with("Grace brought in")):
		await get_tree().process_frame
	var took := Time.get_ticks_msec() - began
	DirAccess.remove_absolute(wav)
	# The items come by the mix's own channel, the notice by the room's: a moment apart.
	began = Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 500 and DAW.state.track(SENT_TRACK).items.all(func(it): return absf(it.start - SENT_AT) > 0.001):
		await get_tree().process_frame
	var told: Array = _notices.filter(func(t): return t.begins_with("Grace brought in"))
	print("sent files: %s in %d ms, told %s" % [why, took, told])
	check("I sent two files from my machine, and the room was told they came in (%s)" % [told],
			why.is_empty() and told.size() == 1 and told[0].contains("Probe Tone") and told[0].contains("s16_mono_0"))
	var mine: Array = DAW.state.track(SENT_TRACK).items.filter(func(it): return absf(it.start - SENT_AT) < 0.001)
	check("and I see the first where I let it go (%d)" % mine.size(), mine.size() == 1)


## Host: the guest's files, brought in onto the track it chose, one after the other, and nothing
## of them left in the incoming folder.
func _check_sent_files() -> void:
	# The track's own demo items start later: only the stretch the files went into.
	var items: Array = DAW.state.track(SENT_TRACK).items.filter(func(it): return it.start >= SENT_AT - 0.001 and it.start < SENT_AT + 1.5)
	items.sort_custom(func(a, b): return a.start < b.start)
	var starts: Array = items.map(func(it): return snappedf(it.start, 0.0001))
	var lengths: Array = items.map(func(it): return snappedf(it.length, 0.0001))
	print("sent files: items at %s, lengths %s" % [starts, lengths])
	check("the guest's two files were brought in where it let them go (%s)" % [starts],
			items.size() == 2 and absf(items[0].start - SENT_AT) < 0.001
			and absf(items[1].start - (SENT_AT + 1.0)) < 0.001)
	if items.size() == 2:
		check("each as long as its sound (%s)" % [lengths], absf(items[0].length - 1.0) < 0.001
				and absf(items[1].length - 5000.0 / 22050.0) < 0.001)
		for it in items:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioTake.DIR.path_join(it.source)))
	var left := DirAccess.get_files_at(FileSend.INCOMING) if DirAccess.dir_exists_absolute(FileSend.INCOMING) else PackedStringArray()
	check("and nothing of them is left in the incoming folder (%s)" % [left], left.is_empty())


func _check_audio_take() -> void:
	check("the guest's recording was placed (%s)" % [_audio_placed], not _audio_placed.is_empty())
	check("and the room was told", _notices.any(func(t): return t.begins_with("Grace recorded")))
	if _audio_placed.is_empty():
		return
	var item: MixState.ItemState = null
	for it in DAW.state.track(AUDIO_TRACK).items:
		if it.name == _audio_placed["name"]:
			item = it
	check("as an item on track %d" % AUDIO_TRACK, item != null)
	if item == null:
		return
	check("where it was placed (%.4f, %.4f)" % [item.start, _audio_placed["start"]],
			absf(item.start - float(_audio_placed["start"])) < 0.001)
	var wav := FileAccess.get_file_as_bytes(_audio_placed["path"])
	check("its file is a WAV of the whole take (%.2fs)" % _audio_placed["seconds"],
			wav.size() == AudioTake.HEADER_BYTES + int(round(float(_audio_placed["seconds"]) * AudioTake.RATE)) * 2
			and wav.decode_u32(0) == 0x46464952)
	var claps: Array[float] = []
	var last := -AudioTake.RATE
	for i in range(AudioTake.HEADER_BYTES, wav.size() - 1, 2):
		var frame := (i - AudioTake.HEADER_BYTES) / 2
		if wav.decode_s16(i) > 16000 and frame - last > AudioTake.RATE / 2:
			claps.append(item.start + float(frame) / AudioTake.RATE)
			last = frame
	var worst := 0.0
	var first := NAN
	for at in claps:
		var off := at - roundf(at)
		if at - item.start < 1.0:
			first = off
			continue
		worst = maxf(worst, absf(off))
	print("audio take: claps ", claps, " first_ms %.3f worst_ms %.3f" % [first * 1000.0, worst * 1000.0])
	check("with a clap on every click the guest heard (%d)" % claps.size(), claps.size() >= 3)
	check("each on the song second it was heard on, worst %.2fms" % (worst * 1000.0),
			worst < TAKE_TOLERANCE)


## Both takes off again: the host's undo, once for each, latest first.
## The guest's audio take trimmed, turned down and faded through the DAW verbs. On a real Reaper
## the lanes are read back from Reaper after the edits land, so what is checked is what the bridge
## did, not the host's own guess.
func _edit_the_take() -> void:
	var taken: String = _audio_placed.get("name", "-")
	var index := func() -> int:
		var items: Array = DAW.state.track(AUDIO_TRACK).items
		for i in items.size():
			if items[i].name == taken:
				return i
		return -1
	if index.call() < 0:
		check("the take is there to edit", false)
		return
	var it: MixState.ItemState = DAW.state.track(AUDIO_TRACK).items[index.call()]
	var start := it.start + 0.1
	var end := it.end() - 0.1
	var offset := it.source_offset
	DAW.trim_item(AUDIO_TRACK, index.call(), start, end)
	DAW.set_item_gain(AUDIO_TRACK, index.call(), -6.0)
	DAW.set_item_fades(AUDIO_TRACK, index.call(), 0.05, 0.1)
	# And the guest's MIDI take, two semitones up and onto the beat.
	var played := _take_notes()
	var midi_index: int = DAW.state.track(TAKE_TRACK).items.find_custom(func(m): return m.name == "Grace take 1")
	if midi_index >= 0:
		DAW.transpose_item(TAKE_TRACK, midi_index, 2)
		DAW.quantize_item(TAKE_TRACK, midi_index, 1.0)
	var reads := [0]
	var count := func(): reads[0] += 1
	DAW.timeline_changed.connect(count)
	await get_tree().create_timer(0.6).timeout
	DAW.timeline_changed.disconnect(count)
	it = DAW.state.track(AUDIO_TRACK).items[index.call()] if index.call() >= 0 else null
	check("I trimmed, turned down and faded the take, and the DAW kept it (%s)"
			% [[it.start, it.end(), it.source_offset - offset, it.gain_db, it.fade_in, it.fade_out] if it else null],
			it != null and absf(it.start - start) < 0.001 and absf(it.end() - end) < 0.001
			and absf(it.source_offset - offset - 0.1) < 0.001 and absf(it.gain_db + 6.0) < 0.01
			and absf(it.fade_in - 0.05) < 0.001 and absf(it.fade_out - 0.1) < 0.001)
	var moved := _take_notes()
	var beat := 60.0 / DAW.state.tempo
	var off_beat := moved.map(func(n): return absf(n[0] / beat - roundf(n[0] / beat)) * beat)
	check("and its MIDI take two semitones up and on the beat (%s, %s)" % [moved.map(func(n): return int(n[2])), off_beat],
			midi_index >= 0 and moved.size() == played.size() and not moved.is_empty()
			and range(moved.size()).all(func(i): return int(moved[i][2]) == int(played[i][2]) + 2)
			and off_beat.all(func(d): return d < 0.002))
	if _reaper_resource != "":
		check("as Reaper read it back after the edits (%d reads)" % reads[0], reads[0] > 0)
	for i in 5:
		DAW.undo()


## A track added at the end, renamed, coloured and removed, each read back from Reaper; then all
## undone, so the takes' own undo steps are the next ones again.
func _tracks_in_reaper() -> void:
	# Straight after the take's five undos, which go through the bridge in line with this edit.
	var count := DAW.state.project_track_count
	DAW.add_track(count + 1, "Probe track")
	await get_tree().create_timer(0.7).timeout
	var added := DAW.state.track(count + 1, false)
	DAW.rename_track(count + 1, "Probe renamed")
	await get_tree().create_timer(0.5).timeout
	var renamed := DAW.state.track(count + 1, false)
	var name_read: String = renamed.name if renamed else "-"
	# Its colour, read back by the structure poll from Reaper's own (8 bits a channel).
	var want_colour := Color(0.30, 0.68, 0.86)
	DAW.set_track_colour(count + 1, want_colour)
	await get_tree().create_timer(0.4).timeout
	if renamed:
		renamed.colour = Color.BLACK
	(DAW.backend as ReaperBackend)._structure_due = 0.0
	await get_tree().create_timer(0.6).timeout
	# A stock plugin added to it and removed again, each read back from Reaper's chain.
	DAW.add_fx(count + 1, "ReaComp")
	await get_tree().create_timer(0.6).timeout
	var fx_added: Array = DAW.state.track(count + 1).plugins().map(func(f): return DAW.state.fx(count + 1, f).name) \
			if DAW.state.tracks.has(count + 1) else []
	if not fx_added.is_empty():
		DAW.remove_fx(count + 1, DAW.state.track(count + 1).plugins()[0])
	await get_tree().create_timer(0.6).timeout
	var fx_left: int = DAW.state.track(count + 1).plugins().size() if DAW.state.tracks.has(count + 1) else -1
	check("Reaper added a stock plugin to a track and removed it, read back each time (%s, %d)" % [fx_added, fx_left],
			fx_added.size() == 1 and str(fx_added[0]).contains("ReaComp") and fx_left == 0)
	var colour_read: Color = DAW.state.track(count + 1).colour if DAW.state.tracks.has(count + 1) else Color.BLACK
	check("Reaper took the track's colour and read it back (%s)" % colour_read,
			absf(colour_read.r - want_colour.r) < 0.004 and absf(colour_read.g - want_colour.g) < 0.004
			and absf(colour_read.b - want_colour.b) < 0.004)
	DAW.remove_track(count + 1)
	await get_tree().create_timer(0.7).timeout
	check("Reaper added a track, renamed it and removed it (%d, %s, %d)"
			% [count, name_read, DAW.state.project_track_count],
			added != null and name_read == "Probe renamed" and DAW.state.project_track_count == count
			and DAW.state.track(count + 1, false) == null)
	# The tempo's changes: halved from bar 3, ramping back up from bar 5, read back from Reaper's
	# own markers.
	var tempo := DAW.state.tempo
	var want := [[0.0, tempo, DawKitTempoMap.HOLD], [8.0, tempo * 0.5, DawKitTempoMap.RAMP_SECONDS],
			[16.0, tempo, DawKitTempoMap.HOLD]]
	DAW.set_tempo_map(want)
	await get_tree().create_timer(0.7).timeout
	var got := DAW.state.tempo_points
	var close_enough := got.size() == 3
	for i in mini(got.size(), 3):
		close_enough = close_enough and absf(got[i][0] - want[i][0]) < 0.001 \
				and absf(got[i][1] - want[i][1]) < 0.001 and got[i][2] == want[i][2]
	check("Reaper took the tempo map and read it back (%s)" % [got], close_enough)
	# A marker added, moved and renamed, then removed, each read back from Reaper's timeline.
	var marks := DAW.state.markers
	DAW.add_marker(50.0, "Probe mark")
	await get_tree().create_timer(0.4).timeout
	DAW.edit_marker(50.0, 51.0, "Probe moved")
	await get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	DAW.state.markers = {}
	await get_tree().create_timer(0.5).timeout
	var moved: String = str(DAW.state.markers.get(DAWBackend.marker_key(DAW.state.markers, 51.0), "-"))
	var moved_from := not is_nan(DAWBackend.marker_key(DAW.state.markers, 50.0))
	DAW.remove_marker(51.0)
	await get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	DAW.state.markers = {51.0: "stale"}
	await get_tree().create_timer(0.5).timeout
	check("Reaper moved and renamed a marker, then removed it, read back each time (%s, %s)" % [moved, DAW.state.markers.size()],
			moved == "Probe moved" and not moved_from and is_nan(DAWBackend.marker_key(DAW.state.markers, 51.0))
			and DAW.state.markers.size() == marks.size())
	for i in 10:
		DAW.undo()
	await get_tree().create_timer(0.7).timeout
	check("and undone, it is one tempo again (%s)" % [DAW.state.tempo_points], DAW.state.tempo_points.is_empty())
	await _envelopes_in_reaper()


## Reaper's own count-in, set from here and read back from its project, and told from the take:
## Reaper says it records from the moment record is pressed, its playhead a bar back.
func _count_in_in_reaper() -> void:
	var s := DAW.state
	var items := func() -> int:
		var n := 0
		for index in s.track_indices():
			n += s.track(index).items.size()
		return n
	var before: int = items.call()
	DAW.set_count_in(1)
	await get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	s.count_in_bars = 0
	await get_tree().create_timer(0.5).timeout
	check("Reaper took a one-bar count-in and read it back (%d)" % s.count_in_bars, s.count_in_bars == 1)
	var at := 30.0
	DAW.seek(at)
	await get_tree().create_timer(0.2).timeout
	var bar := at - s.count_in_start(at)
	DAW.transport_record()
	var lowest := INF
	var counted := false
	var took_at := NAN
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < int((bar + 0.6) * 1000.0):
		lowest = minf(lowest, s.position_seconds)
		counted = counted or s.counting_in()
		if is_nan(took_at) and s.taking():
			took_at = s.position_seconds
		await get_tree().process_frame
	DAW.transport_stop()
	check("Reaper counted in a bar before recording (from %.2fs to %.2fs, a bar %.2fs)" % [lowest, at, bar],
			counted and lowest < at - bar * 0.7 and lowest > at - bar - 0.2)
	check("and the take began at the record point (%.3fs)" % took_at, absf(took_at - at) < 0.15)
	# Before playback too: projmetroen &8, read back, and Reaper counting in when it plays.
	DAW.set_count_in_play(true)
	await get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	s.count_in_play = false
	await get_tree().create_timer(0.5).timeout
	check("Reaper took a count before playback and read it back", s.count_in_play)
	DAW.seek(at)
	await get_tree().create_timer(0.2).timeout
	DAW.transport_play()
	lowest = INF
	counted = false
	began = Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < int((bar + 0.4) * 1000.0):
		lowest = minf(lowest, s.position_seconds)
		counted = counted or s.counting_in()
		await get_tree().process_frame
	var recorded := s.recording
	DAW.transport_stop()
	check("and counted in a bar before playing, not recording (from %.2fs to %.2fs)" % [lowest, at],
			counted and not recorded and lowest < at - bar * 0.7 and lowest > at - bar - 0.2)
	DAW.set_count_in_play(false)
	# Pre-roll: Reaper's own, in place of its count-in, read back, and the song run up to the take.
	DAW.set_pre_roll(true)
	await get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	s.pre_roll = false
	s.count_in_bars = 0
	await get_tree().create_timer(0.5).timeout
	check("Reaper took a one-bar pre-roll and read it back (%s, %d)" % [s.pre_roll, s.count_in_bars],
			s.pre_roll and s.count_in_bars == 1)
	DAW.seek(at)
	await get_tree().create_timer(0.2).timeout
	DAW.transport_record()
	lowest = INF
	counted = false
	took_at = NAN
	began = Time.get_ticks_msec()
	# Reaper pre-rolls from a bar line: the start of the bar before the one the record point is in.
	while Time.get_ticks_msec() - began < int((2.0 * bar + 0.6) * 1000.0):
		lowest = minf(lowest, s.position_seconds)
		counted = counted or s.counting_in()
		if is_nan(took_at) and s.taking():
			took_at = s.position_seconds
		await get_tree().process_frame
	DAW.transport_stop()
	check("Reaper pre-rolled a bar before recording (from %.2fs to %.2fs), and took from the record point (%.3fs)" % [
			lowest, at, took_at], counted and lowest > at - 2.0 * bar - 0.2 and lowest <= at - bar + 0.2
			and absf(took_at - at) < 0.15)
	DAW.set_pre_roll(false)
	DAW.set_count_in(0)
	# And its record mode: time selection auto-punch, read back.
	DAW.set_punch(true)
	await get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	s.punch = false
	await get_tree().create_timer(0.5).timeout
	check("Reaper took punching in and out and read it back", s.punch)
	# A track's record input: the stereo pair from input 1, read back, and put back.
	var was := s.input_of(3)
	DAW.set_track_input(3, "in:1/2")
	await get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	s.track(3).input = ""
	await get_tree().create_timer(0.5).timeout
	check("Reaper took a track's input and read it back (%s, of %d)" % [s.input_of(3), s.inputs.size()],
			s.input_of(3) == "in:1/2")
	if ReaperBackend.input_code(was) != ReaperBackend.INPUT_UNKNOWN:
		DAW.set_track_input(3, was)
	# A change of time signature, onto Reaper's tempo markers and back, the tempo left as it was.
	var sig := Vector2i(s.beats_per_bar, s.beat_unit)
	var tempo_before: Array = s.tempo_points.duplicate(true)
	DAW.set_time_signature_map([[0.0, sig.x, sig.y], [8.0, 7, 8]])
	await get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	s.time_signature_points = []
	await get_tree().create_timer(0.5).timeout
	check("Reaper took a change to 7/8 at bar 3 and read it back (%s, %s)" % [s.time_signature_points, s.bar_beat(s.seconds_at_beat(8.5))],
			s.time_signature_points == [[0.0, sig.x, sig.y], [8.0, 7, 8]] and s.bar_beat(s.seconds_at_beat(8.5)) == "3.2.00")
	check("with its tempo as it was (%s)" % [s.tempo_points], s.tempo_points == tempo_before)
	DAW.set_time_signature_map([[0.0, sig.x, sig.y]])
	await get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	await get_tree().create_timer(0.5).timeout
	check("and taken away again (%s)" % [s.time_signature_points], s.time_signature_points.is_empty() and s.tempo_points == tempo_before)
	DAW.set_punch(false)
	await get_tree().create_timer(0.2).timeout
	if items.call() > before:
		DAW.undo()


## Lanes written to Reaper's envelopes, read back, and Reaper's own faders moving by them.
func _envelopes_in_reaper() -> void:
	var t := DAW.state.track(1)
	var was_pan := t.pan
	var was_mute := t.mute
	var lanes := {
		"volume": [[0.0, -6.0, DawKitAutomation.HOLD], [4.0, -18.0, DawKitAutomation.HOLD]],
		"pan": [[0.0, -1.0, DawKitAutomation.HOLD]],
		"mute": [[0.0, 0.0, DawKitAutomation.HOLD], [3.0, 1.0, DawKitAutomation.HOLD]],
	}
	for target in lanes:
		DAW.set_automation(1, target, lanes[target])
	# A send's level and a plugin's parameter, on whichever tracks have them.
	var first := _first_send(DAW.state)
	var send_lane := [[0.5, -10.0, DawKitAutomation.LINEAR], [2.0, -3.0, DawKitAutomation.HOLD]]
	var send_target := "send:%d" % DAW.state.track(first[0]).sends[first[1]].resolve(DAW.state)
	DAW.set_automation(first[0], send_target, send_lane)
	var fx_track := -1
	for i in DAW.state.track_indices():
		if not DAW.state.track(i).plugins().is_empty():
			fx_track = i
			break
	var fx_target := "fx:%d:1" % DAW.state.track(fx_track).plugins()[0]
	var fx_lane := [[1.0, 0.25, DawKitAutomation.LINEAR], [3.0, 0.75, DawKitAutomation.HOLD]]
	DAW.set_automation(fx_track, fx_target, fx_lane)
	var was_master := DAW.state.master.volume
	var master_lane := [[0.0, -3.0, DawKitAutomation.HOLD]]
	DAW.set_automation(0, "volume", master_lane)
	await get_tree().create_timer(0.8).timeout
	var back := true
	for target in lanes:
		back = back and ReaperBackend._same_lane(t.automation.get(target, []), lanes[target])
	check("Reaper took the lanes as envelopes and read them back (%s)" % [t.automation], back)
	check("a send's (%s on %d: %s)" % [send_target, first[0], DAW.state.track(first[0]).automation.get(send_target)],
			ReaperBackend._same_lane(DAW.state.track(first[0]).automation.get(send_target, []), send_lane))
	check("and a plugin's (%s on %d: %s)" % [fx_target, fx_track, DAW.state.track(fx_track).automation.get(fx_target)],
			ReaperBackend._same_lane(DAW.state.track(fx_track).automation.get(fx_target, []), fx_lane))
	check("and the master's (%s)" % [DAW.state.master.automation],
			ReaperBackend._same_lane(DAW.state.master.automation.get("volume", []), master_lane))
	# Reaper reads its envelopes while it plays, into the null sink.
	DAW.seek(1.0)
	DAW.transport_play()
	await get_tree().create_timer(0.5).timeout
	check("and its faders follow them as it plays (%.2f dB, pan %.2f, mute %s, master %.2f dB)" % [t.volume_db, t.pan, t.mute, DAW.state.master.volume_db],
			absf(t.volume_db + 6.0) < 0.1 and t.pan < 0.01 and not t.mute and absf(DAW.state.master.volume_db + 3.0) < 0.1)
	DAW.seek(5.0)
	await get_tree().create_timer(0.5).timeout
	check("further on, further down, and muted (%.2f dB, %s)" % [t.volume_db, t.mute],
			absf(t.volume_db + 18.0) < 0.1 and t.mute)
	DAW.transport_stop()
	DAW.set_track_automation_mode(1, DAW.AUTOMATION_LATCH)
	await get_tree().create_timer(0.6).timeout
	check("Reaper's track is in latch, and says so (%d)" % t.automation_mode, t.automation_mode == DAW.AUTOMATION_LATCH)
	DAW.set_track_automation_mode(1, DAW.AUTOMATION_READ)
	# The master's mode, told to Reaper and read back from it: forgotten here, the next report
	# of the arrangement puts it back.
	DAW.set_track_automation_mode(0, DAW.AUTOMATION_LATCH)
	await get_tree().create_timer(0.6).timeout
	DAW.state.master.automation_mode = DAW.AUTOMATION_READ
	DAW.backend.set(&"_timeline_due", 0.0)
	await get_tree().create_timer(1.0).timeout
	check("Reaper's master is in latch, and says so (%d)" % DAW.state.master.automation_mode,
			DAW.state.master.automation_mode == DAW.AUTOMATION_LATCH)
	DAW.set_track_automation_mode(0, DAW.AUTOMATION_READ)
	await get_tree().create_timer(0.6).timeout
	check("and back in read", DAW.state.master.automation_mode == DAW.AUTOMATION_READ)
	for _i in 6:
		DAW.undo()
	DAW.seek(0.0)
	await get_tree().create_timer(0.8).timeout
	check("undone, the envelopes are gone (%s)" % [t.automation], t.automation.is_empty() and t.automation_mode == 0
			and DAW.state.track(first[0]).automation.is_empty() and DAW.state.track(fx_track).automation.is_empty()
			and DAW.state.master.automation.is_empty())
	if not is_equal_approx(DAW.state.master.volume, was_master):
		DAW.set_master_volume(was_master)
	await _render_in_reaper()
	if t.mute != was_mute:
		DAW.set_track_mute(1, was_mute)
	if not is_equal_approx(t.pan, was_pan):
		DAW.set_track_pan(1, was_pan)


## Reaper's own render through the bridge, twice over the same two seconds: with a volume lane on
## RENDER_TRACK (-6 dB, then -18 dB from halfway) and without. Its stem's level in each half, one
## render against the other, is the lane.
func _render_in_reaper() -> void:
	var s := DAW.state
	var was := [s.looping, s.loop_start, s.loop_end]
	DAW.set_automation(RENDER_TRACK, "volume", [[0.0, -6.0, DawKitAutomation.HOLD], [2.0, -18.0, DawKitAutomation.HOLD]])
	DAW.set_loop_range(1.0, 3.0)
	DAW.set_looping(true)
	await get_tree().create_timer(0.6).timeout
	var with_lane := await _reaper_render_levels()
	DAW.undo()
	await get_tree().create_timer(0.6).timeout
	var without := await _reaper_render_levels()
	# Without a lane the fader is the level, and it need not be at 0 dB.
	var fader := s.track(RENDER_TRACK).volume_db
	DAW.set_loop_range(was[1], was[2])
	DAW.set_looping(was[0])
	check("Reaper rendered the loop, mix and stems, twice (%s, %s)" % [with_lane, without],
			with_lane.size() == 4 and without.size() == 4)
	if with_lane.size() == 4 and without.size() == 4:
		check("its files are the loop and Reaper's tail of %.1fs (%.3fs)" % [DAWBackend.RENDER_TAIL_SECONDS, with_lane[2]],
				absf(float(with_lane[2]) - (2.0 + DAWBackend.RENDER_TAIL_SECONDS)) < 0.01)
		var a: float = with_lane[0] - without[0]
		var b: float = with_lane[1] - without[1]
		check("and track %d's stem is the lane: %.2f dB, then %.2f dB, against its fader at %.2f dB" % [RENDER_TRACK, a, b, fader],
				absf(a - (-6.0 - fader)) < 0.2 and absf(b - (-18.0 - fader)) < 0.2)
		DirAccess.remove_absolute(with_lane[3])


## One render of the loop with stems: RENDER_TRACK's stem's level (dB RMS) in each second of it, and
## the folder the render went to (emptied).
func _reaper_render_levels() -> Array:
	var done: Array = []
	var on_done := func(files, problems): done.append([files, problems])
	DAW.render_finished.connect(on_done, CONNECT_ONE_SHOT)
	DAW.render(true)
	var began := Time.get_ticks_msec()
	while done.is_empty() and Time.get_ticks_msec() - began < 8000:
		await get_tree().process_frame
	if done.is_empty():
		DAW.render_finished.disconnect(on_done)
		return []
	var files: PackedStringArray = done[0][0]
	var want := " - %s.wav" % DAW.state.track(RENDER_TRACK).name
	var out: Array = []
	var seconds := NAN
	for f in files:
		if f.ends_with(want):
			var sound := DawKitAudioFile.read(f)
			var rate: int = sound["rate"]
			var samples: PackedFloat32Array = sound["samples"]
			for second in 2:
				var sum := 0.0
				var n := 0
				for i in range(int((second + 0.1) * rate) * 2, int((second + 0.9) * rate) * 2):
					sum += samples[i] * samples[i]
					n += 1
				out.append(10.0 * log(maxf(sum / maxf(n, 1), 1e-20)) / log(10.0))
			seconds = int(sound["frames"]) / float(rate)
	out.append(seconds)
	for f in files:
		DirAccess.remove_absolute(f)
	if not files.is_empty():
		out.append(files[0].get_base_dir())
	return out


## The guest's MIDI take's notes, in song seconds, by pitch then time so the order survives an
## edit that moves them.
func _take_notes() -> Array:
	for it in DAW.state.track(TAKE_TRACK).items:
		if it.name == "Grace take 1":
			var notes := MidiTake.unpack_relative(it.notes, it.start)
			notes.sort_custom(func(a, b): return a[0] < b[0] if a[2] == b[2] else a[2] < b[2])
			return notes
	return []


func _undo_takes() -> void:
	DAW.undo()
	DAW.undo()
	await get_tree().create_timer(0.3).timeout
	var midi := DAW.state.track(TAKE_TRACK).items.any(func(it): return it.name == "Grace take 1")
	var taken: String = _audio_placed.get("name", "-")
	var audio := DAW.state.track(AUDIO_TRACK).items.any(func(it): return it.name == taken)
	check("and an undo each takes them off again", not midi and not audio)


func _guest(port: int) -> void:
	Session.local_name = "Grace"
	Session.modular_takes.patch = _probe_patch
	Session.grain_takes.sound = _probe_grain_sound
	# On the host's own machine, which would ordinarily mean not listening: the host's speakers
	# are already in the room. Asked for here, because the probe is what is listening.
	Session.listen_choice = 1
	Session.room_changed.connect(func(): _rooms_heard += 1)
	Session.item_used.connect(func(item: StringName, down: bool, from: int, take: int):
		_uses.append([item, down, from])
		_use_takes.append(take))
	Session.note_played.connect(_on_note_played)
	Session.item_hit.connect(func(item: StringName, velocity: int, from: int, song: float, snap: bool, take: int, zone: StringName):
		_item_hits.append([item, velocity, from, song, snap, take, zone]))
	await _until(0.3)
	Session.join("127.0.0.1", port, "XX99")
	await _until(1.4)
	check("the wrong code is turned away (%s)" % [_notices], _notices.has("That is not Ada's code."))
	check("back on my own after it", Session.role == Session.Role.SOLO)
	# Read across a room and typed in a hurry: spaces and case are not the code.
	check("joins", Session.join("127.0.0.1", port, "ab 12"))
	check("as a guest that never opens the DAW", not Session.is_authority())
	_keep_publishing(Transform3D(Basis.IDENTITY, Vector3(-0.8, 1.5, 0.9)), "")

	await _until(2.4)
	check("the roster arrived with the host on it", Session.name_of(1) == "Ada")
	check("and me under my name", Session.name_of(Session.local_peer_id) == "Grace")
	check("two in the room", Session.participants.size() == 2)
	check("the snapshot arrived: %d tracks (%d)" % [_expect_tracks, DAW.state.tracks.size()],
			DAW.state.tracks.size() == _expect_tracks)
	var host = Session.participants.get(1)
	check("the host's head has been heard", host != null and host.head.origin.is_equal_approx(
			Vector3(1.2, 1.62, 0.4)))
	check("and what it is pointing at", host != null and host.pointing_at == "MASTER  VOLUME")
	check("told who I joined", _notices.has("Joined Ada's session."))
	check("the host's room came in with me (%s)" % [Session.room], _rooms_heard == 1
			and Session.room.get("venue") == &"grid" and Session.room.get("tablets", {}).has(&"tablet_1"))
	Session.ask_room(&"open_tablet", [3, 1, "Comp", 0.1, 0.3])
	Session.ask_room(&"move_piece", [&"rack", -1.0, -0.4, 0.6])
	Session.ask_room(&"place_surface", [&"console", Transform3D(Basis.IDENTITY, Vector3(0.1, 0, 0.2))])
	# Straight at the host, past ask_room's own check: the venue is not a guest's to change.
	Session.room_seq += 1
	Session._room_asked.rpc_id(1, Session.room_seq, &"set_venue", [&"chalk"])
	# The rack being wheeled, as the hand pushing it sends it while it moves.
	Session.send_motion(&"rack", -0.9, -0.35, 0.5)

	DAW.set_track_volume(2, 0.123)
	DAW.set_tempo(GUEST_TEMPO)
	DAW.set_metronome(true)
	DAW.add_marker(GUEST_MARK, "GUEST")
	DAW.set_track_monitor(3, DAW.MONITOR_AUTO)
	var send := _first_send(DAW.state)
	check("the snapshot carried a send to turn (%s)" % [send], not send.is_empty())
	if not send.is_empty():
		DAW.set_send_volume(send[0], send[1], GUEST_SEND)
	Session.claim_hold(KEY)
	Session.claim_hold(DUCK)
	Session.send_carry(&"duck", DUCK_AT)
	Session.send_item_use(&"duck", true)
	await _until(3.2)
	check("my grab is in the table", Session.holder_of(KEY) == Session.local_peer_id)
	check("my fader move came back from the host (%.4f)" % DAW.state.track(2).volume,
			absf(DAW.state.track(2).volume - 0.123) < 0.002)
	check("and so did my tempo (%.1f)" % DAW.state.tempo, absf(DAW.state.tempo - GUEST_TEMPO) < 0.05)
	check("and the click I switched on", DAW.state.metronome)
	check("and my input monitoring", DAW.state.track(3).monitor == DAW.MONITOR_AUTO)
	check("and my marker (%s)" % [DAW.state.markers.values()], _has_guest_mark(DAW.state))
	check("the host answered all four of my asks, the refused one too (%s)" % [Session.room.get("acks")],
			int((Session.room.get("acks", {}) as Dictionary).get(Session.local_peer_id, 0)) == 4)
	check("the stand I asked for is in the host's room now", _rooms_heard >= 2
			and Session.room.get("tablets", {}).has(&"tablet_2") and Session.room.get("venue") == &"grid")
	check("and my send level", not send.is_empty()
			and absf(DAW.state.send(send[0], send[1]).volume - GUEST_SEND) < 0.002)

	await _until(4.4)
	check("the host's attempt on my fader did not take it", Session.holder_of(KEY) == Session.local_peer_id)
	check("the host's squeeze reached me (%s)" % [_uses], _uses == [[&"duck", false, 1]])
	Session.release_hold(KEY)
	check("the host has the plane", Session.holder_of(PLANE) == 1)
	Session.take_hold(PLANE)
	# Thrown -- one launch, reliably, as vectors -- then put down and let go: the host hears
	# where it is before it hears the hand is empty.
	Session.ask_room(&"throw_item", [&"duck", Vector3(0.4, 1.2, 1.5), Vector3(0.0, 2.0, 3.5), Vector3(-6.0, 0.0, 0.0)])
	Session.ask_room(&"put_item", [&"duck", 0.4, 1.9, 0.2])
	Session.release_hold(DUCK)
	# A plug off my tablet into the desk's MIX send, for my headphones.
	Session.ask_room(&"patch", [1, &"mix"])
	# And a key, as played, for anyone patched into my keys.
	Session.guest_midi.note_on(60, 100)
	Session.guest_midi.note_off(60)
	# And one from my fingertips, which says so.
	Session.guest_midi.note_on(62, 90, 0, 0.0, false, &"fingertips")
	Session.guest_midi.note_off(62, 0, 0.0, false, &"fingertips")
	await _until(5.2)
	check("my releases left only the plane I took from the host's hand (%s)" % [Session.holds],
			Session.holds == {PLANE: Session.local_peer_id})
	Session.release_hold(PLANE)
	check("the host's keys reached me as played (%s)" % [_notes],
			_notes == [[Session.Note.ON, 67, 80, 1], [Session.Note.OFF, 67, 0, 1]])
	check("and the host's harp note, saying it was the harp's (%s)" % [_sourced],
			_sourced == [[Session.Note.ON, 71, 1, &"harp"], [Session.Note.OFF, 71, 1, &"harp"]])
	check("and the host answered my throw, put-down and patch", int((Session.room.get("acks", {}) as Dictionary)
			.get(Session.local_peer_id, 0)) == 7)

	await _until(6.8)
	var heard := Session.mix_feed.stats()
	print("audio: ", heard, " clicks ", Session.mix_feed.heard_clicks)
	check("the host's mix is reaching me", heard.get("hearing", false) and int(heard.get("packets", 0)) > 1000)
	check("loud enough to be the music (%.3f)" % Session.mix_feed.heard_peak, Session.mix_feed.heard_peak > 0.15)
	if not _built_in:
		var clicks: Array = Session.mix_feed.heard_clicks
		var steady := clicks.size() >= 3
		for i in range(1, clicks.size()):
			steady = steady and absi(int(clicks[i]) - int(clicks[i - 1]) - 48000) < 480
		check("its clicks a second apart, to within 10ms (%s)" % [clicks], steady)
	check("without running dry once it started (%d)" % int(heard.get("underruns", -1)),
			int(heard.get("underruns", 99)) <= 1)
	check("or losing a packet on loopback (%d)" % int(heard.get("lost", -1)), int(heard.get("lost", 99)) == 0)
	# A real mix is captured off the host's master bus a driver block at a time (about 15ms on
	# Pulse), which the test tone, made the moment it is asked for, never pays.
	var bar := 45.0 if _built_in else 30.0
	check("and close enough behind to play along to (%.1fms, under %.0f)" % [float(heard.get("latency_ms", 999.0)), bar],
			float(heard.get("latency_ms", 999.0)) < bar)

	if not _built_in:
		var ga := Session.guest_audio
		ga.make_source = func() -> MixSource: return Clapper.new()
		ga.target_track = AUDIO_TRACK
		ga.record_with_host = true
		await _guest_records()
		print("audio drift found: %.0f ppm" % ga.drift_ppm())
		check("my recording was sent when I heard the recording stop (%s)" % [ga.last_take],
				not ga.is_recording() and float(ga.last_take.get("seconds", 0.0)) > 3.0)
		check("the host told me where my recording went",
				_notices.any(func(t): return t.begins_with("Your recording is on")))
		var mine: Array = DAW.state.track(AUDIO_TRACK).items.filter(func(it): return it.source != "")
		check("and it came back to me with its waveform",
				mine.size() == 1 and mine[0].peaks.size() > 100)
		ga.record_with_host = false
		# After the host has undone the takes (by 14.9 s, or 35.6 s on Reaper): an undo then
		# would take these off.
		await _until(36.4 if _reaper_host else 15.2)
		await _send_files()
	else:
		await _until(13.8)
		check("the host's newly opened project reached me whole (%d tracks, '%s')"
				% [DAW.state.tracks.size(), DAW.state.track(1).name],
				DAW.state.tracks.size() == 7 and DAW.state.track(1).name == "Opened")
		Session.mix_feed.heard_peak = 0.0
		# Save, pressed here: the host's file, saved where the host keeps it, and the whole
		# room told.
		DAW.save_project()
		await _until(14.3)
		check("and I know what its second track records from (%s)" % DAW.state.input_name(DAW.state.input_of(2)),
				DAW.state.input_of(2) == "audio:" and DAW.state.input_name("audio:") == "the default microphone")
		check("and I hear it play from its own files (%.3f)" % Session.mix_feed.heard_peak,
				Session.mix_feed.heard_peak > 0.15)
		check("I saved the host's project, and was told (%s)" % [_notices],
				_notices.has("Grace saved the project as dawlings_probe_%d.dawproject." % _port))
		check("and I know its name and file, not where it is (%s, %s)" % [DAW.project_title(), DAW.project_file_name()],
				not DAW.project_title().is_empty() and DAW.project_file_name() == "dawlings_probe_%d.dawproject" % _port)

	# The harp: I strum at 41, and hear the host's strum back from 43.
	await _until(40.0)
	_harped.clear()
	var harp := _harp()
	_check_bells()
	await _until(41.0)
	_strum(harp)
	# A bell rung, as the studio sends one: its one song position goes with it.
	await _until(44.0)
	_room.played.connect(func(item: InstrumentItem, velocity: int, _struck: bool, at: float, zone: StringName) -> void:
		Session.send_item_hit(item.id, velocity, at, false, -1, zone))
	InstrumentItem.clock = _ring_song
	var bell := _room.items.get(&"bell2") as HandbellItem
	if bell != null:
		bell.play(96)
	InstrumentItem.clock = Callable()
	check("I rang bell 2 as D minor's third, F5 (%d)" % (bell.last_note if bell != null else -1),
			bell != null and bell.last_note == 77)
	# My shaker, on its shelf, into track 3: asked as the studio asks (Jacks).
	await _until(44.5)
	Session.ask_room(&"plug", [&"shaker", &"track_3"])
	await _until(45.0)
	_check_strum(1, "the host's strum reached me")
	_harped.clear()

	# The host's room says where both jacks go: mine, and the bell the host plugged at 46.
	await _until(47.5)
	var jacks := Jacks.new()
	add_child(jacks)
	jacks.set_patch(Session.room.get("jacks", {}))
	check("my plug is in the host's room, and the host's beside it (%s)" % [Session.room.get("jacks")],
			jacks.sink_of(&"shaker") == &"track_3" and jacks.sink_of(&"bell1") == Jack.track_sink(PLUG_TRACK)
			and jacks.patch.size() == 2)
	jacks.free()

	# Cables (docs/spatial_loop.md slice 6): my shaker in my hand into the host's keys, and the harp
	# too; my jacks follow the host's room, as the studio's do.
	_wear_jacks()
	_jacks.set_patch(Session.room.get("jacks", {}))
	Session.room_changed.connect(func() -> void: _jacks.set_patch(Session.room.get("jacks", {})))
	await _until(48.0)
	var shaker := _room.items.get(&"shaker") as InstrumentItem
	Session.claim_hold(shaker.network_key())
	await _until(48.3)
	Session.ask_room(&"plug", [&"shaker", Jack.player_sink(1)])
	Session.ask_room(&"plug", [Jack.HARP, Jack.player_sink(1)])
	# Four hits, as the studio sends them (Jacks.hit), each with the song position it was played to.
	await _until(48.8)
	check("the host's room has my shaker and the harp into the host (%s)" % [_jacks.patch],
			_jacks.sink_of(&"shaker") == Jack.player_sink(1) and _jacks.sink_of(Jack.HARP) == Jack.player_sink(1))
	for i in 4:
		_jacks.hit(shaker, 90, _ring_song() + 1.0 + i * 0.1)
	# The host's bell 1, rung at 49 into me: its own note on my keys, and its off.
	await _until(50.0)
	var rung := _cabled.filter(func(c: Array) -> bool: return c[1] == 74)
	check("the host's bell came down its jack and played its own note, D5, on my keys, and its off (%s)" % [rung],
			rung.size() == 2 and rung[0][0] == Session.Note.ON and rung[1][0] == Session.Note.OFF
			and is_equal_approx(rung[0][2], _ring_song() + 2.0)
			and absf(rung[1][2] - (_ring_song() + 2.0 + HandbellItem.RING_SECONDS)) < 0.001)
	check("and the cable is in my keys' reach while it is plugged into me", Session.guest_midi.instruments.has(Jacks.CABLE))
	# The harp, strummed into the host's take, to a clock of my own: its strings ring out by 52.
	await _until(50.2)
	Session.guest_midi.heard_source = _given_clock(CABLE_SONG + 0.2, false)
	_strum(harp)
	check("my strum went down the jack, not onto my keys", not Session.guest_midi.held.has(HARP_STRINGS[0]))
	await _until(52.5)
	Session.guest_midi.heard_source = Callable()

	# The fifths wheel's SET, as the wheel sends a guest's (docs/spatial_loop.md slice 9): a room
	# ask carrying the bar I chose.
	await _until(53.7)
	Session.ask_room(FifthsWheel.VERB, [WHEEL_BAR, WHEEL_INSIDE])
	# And to the harp, in a headset: the host sees my ghost there by 55.
	await _until(53.8)
	await _travel_to_the_harp()

	# While the session is still on: once the host leaves, my own project is back.
	await _until(54.5)
	if _reaper_host:
		check("I know the host's Reaper project by its name and file (%s, %s)" % [DAW.project_title(), DAW.project_file_name()],
				DAW.project_title() == "rig" and DAW.project_file_name() == "rig.RPP")
	# One undo step per gesture (slice 12): pan and volume dragged at once inside an edit, as a
	# control that edits as one sends them, frame by frame. The host moves a fader of its own
	# meanwhile, at 54.7.
	var steps_before: int = DAW.state.undo_depth
	await _until(54.55)
	DAW.open_edit(EDIT_NAME)
	var from_pan: float = DAW.state.track(EDIT_TRACK).pan
	var from_volume: float = DAW.state.track(EDIT_TRACK).volume
	for i in 30:
		var f := (i + 1) / 30.0
		DAW.set_track_pan(EDIT_TRACK, lerpf(from_pan, EDIT_PAN, f))
		DAW.set_track_volume(EDIT_TRACK, lerpf(from_volume, EDIT_VOLUME, f))
		await get_tree().create_timer(0.01).timeout
	DAW.close_edit()
	await _until(55.0)
	_check_wheel("the host's")
	await _until(55.1)
	if not _reaper_host:
		check("my drag is one step in the host's history, its own fader another (%d after %d: %s)" % [
				DAW.state.undo_depth, steps_before, DAW.state.undo_names.slice(steps_before)],
				DAW.state.undo_depth == steps_before + 2 and DAW.state.undo_names.slice(steps_before).count(EDIT_NAME) == 1)
	# Controls beside the keys (slice 13): the host's keys played here, as a plug in them would;
	# a controller the host must refuse; and the host's bend, heard while its note is down and
	# rested at its note-off.
	var their := TheirKeys.new()
	their.name = "TheirKeys"
	add_child(their)
	their.set_players([1])
	Session.note_played.connect(their.play)
	Session.control_played.connect(their.control)
	await _until(55.27)
	Session.send_control(7, 100)
	await _until(55.37)
	var synth: MonitorSynth = their.synths[1]
	var down: KeysDown = their._down.get(1)
	check("the host's bend during its held note is heard on my TheirKeys (%s)" % [synth.controls],
			int(synth.controls.get(DawKitClip.PITCH_BEND, 0)) == BEND_VALUE and down != null
			and down.is_down(BEND_PITCH))
	await _until(55.55)
	check("and rests at its note-off (%s)" % [synth.controls], int(synth.controls.get(DawKitClip.PITCH_BEND, -1)) == 0
			and down != null and down.is_empty())
	Session.note_played.disconnect(their.play)
	Session.control_played.disconnect(their.control)
	their.queue_free()
	await _bend_into_a_take()
	await _tilt_into_a_take()
	await _snap_into_a_take()
	await _place_on_the_stage()
	await _clap_to_mute()
	await _tie_a_rope()
	await _write_a_lane()
	await _pull_a_cassette()
	await _paste_a_cassette()
	await _hear_a_cassette()
	await _sample_a_squeeze()
	await _spin_the_platter()
	await _crank_the_history()
	await _rearrange_the_sections()
	await _press_the_bricks()
	await _drive_their_harp()
	await _point_and_note()
	await _hear_the_spectra()
	await _carve_the_clash()
	await _strike_the_drum()
	await _press_the_weather()
	await _loop_a_layer()
	await _press_the_music_box()
	await _tie_and_pluck_a_string()
	await _build_a_marble_run()
	await _play_a_theremin()
	await _patch_the_modular()
	await _play_the_modular()
	await _patch_the_world()
	await _play_the_grains()
	await _tap_the_lyrics()
	await _until(64.88)
	print("notices: ", _notices)
	check("the host's goodbye arrived", _notices.any(func(t): return t.contains("ended the session")))
	check("and I am back on my own", Session.role == Session.Role.SOLO)
	check("and no longer listening", not Session.mix_feed.listening)
	check("with a mix of my own again", DAW.is_live() and DAW.state.tracks.size() > 0)


## Controls in takes (slice 14): a note held from 56.0 to 56.3 and bent at 56.2 by a keyboard's
## pitch wheel (an InputEventMIDI, the door a real one comes in by), recorded onto TAKE_TRACK at
## BENT_SONG to a clock of my own, and sent to the host when that clock stops recording. Where the
## bend was taken down is written for the host to look for.
func _bend_into_a_take() -> void:
	var gm := Session.guest_midi
	await _until(55.9)
	for pitch in gm.held.keys():
		gm.note_off(pitch)
	gm.target_track = TAKE_TRACK
	gm.heard_source = _given_clock(BENT_SONG, true)
	await _until(56.0)
	var key := InputEventMIDI.new()
	key.message = MIDI_MESSAGE_NOTE_ON
	key.pitch = BENT_PITCH
	key.velocity = 100
	gm._input(key)
	check("my held note is in a take of my own", gm.is_recording() and gm.held.has(BENT_PITCH))
	await _until(56.2)
	var wheel := InputEventMIDI.new()
	wheel.message = MIDI_MESSAGE_PITCH_BEND
	wheel.pitch = 8192 + BEND_VALUE
	var at := gm.stamp()
	gm._input(wheel)
	check("my keyboard's wheel bends my keys (%s)" % [gm.controls], int(gm.controls.get(DawKitClip.PITCH_BEND, 0)) == BEND_VALUE)
	var file := FileAccess.open("/tmp/r3d_probe_bend_%d.json" % _port, FileAccess.WRITE)
	file.store_string(JSON.stringify({"at": at, "value": BEND_VALUE}))
	file.close()
	await _until(56.3)
	key.message = MIDI_MESSAGE_NOTE_OFF
	key.velocity = 0
	gm._input(key)
	await _until(56.4)
	gm.heard_source = _given_clock(BENT_SONG + 0.6, false)
	await _until(56.5)
	check("and the take went to the host with the bend and its rest (%s)" % [gm.last_take],
			not gm.is_recording() and gm.last_take.get("controls", 0) == 2)
	gm.heard_source = Callable()
	gm.target_track = 0


## Bend and wobble by tilting (slice 15): a keytar in a hand of mine whose readings are a posed
## bare hand (an XRInteractor on a HandGestures, as the rig makes them), a note played on it at
## 56.65 and held to 57.25 while the hand tips TILT_DEGREES over 56.7 to 56.8, recorded onto TAKE_TRACK at TILT_SONG
## to a clock of my own and sent to the host when that clock stops. The bend it made is written
## for the host to look for.
func _tilt_into_a_take() -> void:
	var gm := Session.guest_midi
	await _until(56.6)
	gm.reach(&"keytar", true)
	gm.target_track = TAKE_TRACK
	gm.heard_source = _given_clock(TILT_SONG, true)
	var hand := HandGestures.new()
	var pad := XRInteractor.new()
	pad.gestures = hand
	var keytar := KeytarItem.new()
	keytar.midi = gm
	keytar.state = Item.State.HELD
	keytar.carried_by = pad
	var tip := func(degrees: float) -> void:
		hand.take(HandPose.posed([0, 0, 0, 0, 0], 0,
				Transform3D(Basis(Vector3.FORWARD, deg_to_rad(degrees)), Vector3(0.0, 1.2, -0.3))))
	tip.call(0.0)
	await _until(56.65)
	gm.note_on(TILT_PITCH, 100, 0, 0.0, false, &"keytar")
	check("my keytar note is in a take of my own", gm.is_recording() and gm.held.has(TILT_PITCH))
	var from := (Time.get_ticks_msec() - _start) / 1000.0 - _shift
	var now := from
	while now < 57.25:
		tip.call(TILT_DEGREES * clampf((now - from - 0.05) / 0.1, 0.0, 1.0))
		keytar._bend_by_hand(1.0 / 60.0)
		await get_tree().physics_frame
		now = (Time.get_ticks_msec() - _start) / 1000.0 - _shift
	var bent := int(gm.controls.get(DawKitClip.PITCH_BEND, 0))
	var wanted := Wobble.value_of(Wobble.bend_for(TILT_DEGREES))
	check("my neck hand's tilt bends my keytar note (%d, the tilt's own %d)" % [bent, wanted],
			absi(bent - wanted) <= 64 and keytar.wobble != null and keytar.wobble.sends > 0)
	var file := FileAccess.open("/tmp/r3d_probe_tilt_%d.json" % _port, FileAccess.WRITE)
	file.store_string(JSON.stringify({"value": bent}))
	file.close()
	gm.note_off(TILT_PITCH, 0, 0.0, false, &"keytar")
	await _until(57.3)
	gm.heard_source = _given_clock(TILT_SONG + 1.0, false)
	await _until(57.4)
	check("and the take went to the host with the bend and its rest (%s)" % [gm.last_take],
			not gm.is_recording() and int(gm.last_take.get("controls", 0)) >= 3)
	gm.reach(&"keytar", false)
	gm.heard_source = Callable()
	gm.target_track = 0
	keytar.free()
	pad.free()
	hand.free()


## The stage table (slice 18): a table of my own over the host's mix, and STAGE_TRACK's voice on it
## taken by a hand at 57.7 and placed at STAGE_PAN and STAGE_DB in fifteen moves, as a drag sends
## them: pan and volume inside one edit, intents the host carries out.
func _place_on_the_stage() -> void:
	await _until(57.7)
	var table := StageTable.new()
	table.name = "StageTable"
	StageLink.wire(table)
	add_child(table)
	table._process(0.0)
	var voice: StageVoice = table.voices.get(STAGE_TRACK)
	check("my stage table stands the host's track %d as a voice (%s)" % [STAGE_TRACK, table.voices.keys()], voice != null)
	if voice == null:
		table.queue_free()
		return
	var hand := Node.new()
	add_child(hand)
	var from := voice.position
	var to := StageTable.spot_of(STAGE_PAN, STAGE_DB)
	voice.grab_begin(hand, table.to_global(from))
	for i in 15:
		voice.grab_move(hand, table.to_global(from.lerp(to, (i + 1) / 15.0)))
		await get_tree().create_timer(0.01).timeout
	voice.grab_end(hand)
	check("and my hand put it where I meant (%s)" % voice.readout(), voice.position.is_equal_approx(to))
	hand.queue_free()
	table.queue_free()


## Clap to mute (slice 19): a clap at 58.2, my palms meeting fast and parting at once, while
## pointing at CLAP_TRACK: a latch, which asks the host to toggle its mute.
func _clap_to_mute() -> void:
	await _until(58.2)
	var clap := Clap.new()
	clap.target = func() -> int: return CLAP_TRACK
	var was := DAW.state.track(CLAP_TRACK).mute
	var dt := 1.0 / 60.0
	for gap in [0.2, 0.17, 0.14, 0.11, 0.08, 0.05, 0.03]:
		clap.step(gap <= HandPose.PALMS_TOUCH, gap, dt)
	check("my palms met fast at track %d" % CLAP_TRACK, clap.pressed and clap.track == CLAP_TRACK)
	for i in 4:
		clap.step(true, 0.02, dt)
	clap.step(false, 0.15, dt)
	check("and parted at once: a latch", not clap.pressed and clap.latches(5 * dt))
	await _until(58.35)
	check("which the host's mix gives back to me (%s, was %s)" % [DAW.state.track(CLAP_TRACK).mute, was],
			DAW.state.track(CLAP_TRACK).mute != was)


## Sidechain as a rope (slice 20): a table of my own over the host's mix at 58.5, and a rope dragged
## from ROPE_FROM's knot to ROPE_TO's voice, as a hand drags it: the compressor (if the track has
## none) and the key send, one edit of intents the host carries out. By 58.6 the host's mix gives
## the key send back to me.
func _tie_a_rope() -> void:
	await _until(58.5)
	var table := StageTable.new()
	table.name = "RopeTable"
	StageLink.wire(table)
	add_child(table)
	table._process(0.0)
	var from: StageVoice = table.voices.get(ROPE_FROM)
	check("my stage table stands the host's tracks %d and %d (%s)" % [ROPE_FROM, ROPE_TO, table.voices.keys()],
			from != null and table.voices.has(ROPE_TO))
	if from == null or not table.voices.has(ROPE_TO):
		table.queue_free()
		return
	var hand := Node.new()
	add_child(hand)
	var a := table.knot_point(ROPE_FROM)
	var b := table.knot_point(ROPE_TO)
	from.knot.grab_begin(hand, table.to_global(a))
	for i in 10:
		from.knot.grab_move(hand, table.to_global(a.lerp(Vector3(b.x, a.y, b.z), (i + 1) / 10.0)))
	check("my rope is over track %d's voice as I let go" % ROPE_TO, table.drop_target(ROPE_FROM, Vector2(b.x, b.z)) == ROPE_TO)
	from.knot.grab_end(hand)
	check("and asks for the rope's row", table.ropes.has(Sidechain.rope_key(ROPE_FROM, ROPE_TO)))
	await _until(58.6)
	check("which the host's mix gives back to me as a key send (%d)" % Sidechain.key_send(ROPE_FROM, ROPE_TO),
			Sidechain.key_send(ROPE_FROM, ROPE_TO) > 0)
	hand.queue_free()
	table.queue_free()


## Automation by gesture (slice 22): at 58.74 a write bead of my own over a fader of BEAD_TRACK on the
## host's mix, pulled as a hand pulls it and raised 0.3 m over BEAD_SECONDS of a clock of my own from
## BEAD_SONG, the song not looping: the hold, an edit of sets, the pass as the whole lane and the
## let-go, intents the host carries out. By 58.81 the host's mix gives the lane back to me.
func _write_a_lane() -> void:
	await _until(58.74)
	var fader := Fader.new()
	fader.track_index = BEAD_TRACK
	fader.automates = func() -> Array: return [BEAD_TRACK, "volume"]
	add_child(fader)
	var now := {"seconds": BEAD_SONG, "playing": true, "valid": true}
	var bead := WriteBead.new()
	add_child(bead)
	bead.control = fader
	bead.heard_source = func() -> Dictionary: return now
	var hand := Node.new()
	add_child(hand)
	check("my bead pass is not looped (the host's song is not looping)", not DAW.state.looping)
	bead.grab_begin(hand, Vector3(0, 1.0, 0))
	var ticks := roundi(BEAD_SECONDS * 60.0)
	for i in ticks:
		now["seconds"] = BEAD_SONG + (i + 1) / 60.0
		bead.grab_move(hand, Vector3(0, 1.0 + 0.3 * float(i + 1) / ticks, 0))
		bead.follow(now)
	bead.grab_end(hand)
	check("and wrote one pass", bead.passes_written == 1)
	await _until(58.81)
	var lane := WriteBead.lane_now(BEAD_TRACK, "volume")
	var inside := lane.filter(func(pt): return absf(float(pt[0]) - BEAD_SONG - BEAD_SECONDS * 0.5) <= BEAD_SECONDS * 0.5 + 0.0001)
	check("which the host's mix gives back to me as the lane (%d points)" % inside.size(),
			inside.size() == roundi(BEAD_SECONDS / WriteBead.POINT_SECONDS) + 1)
	hand.queue_free()
	bead.queue_free()
	fader.queue_free()


## Snapped gently (slice 17): two shaker hits taken down at 57.42 by a HitRecorder of my own onto
## TAKE_TRACK at SNAP_SONG, to a clock of my own, as the studio's takes them (`hit`'s `snap`, the
## player's flag): one SNAP_EARLY before a sixteenth with snap on, one SNAP_EARLY before the next
## with it off. Each goes to the room too, with its flag and its Foley take, as the studio sends a
## hit. Sent to the host when the clock stops recording; where each was played, and where the
## snapped one is to land, is written for the host to look for.
func _snap_into_a_take() -> void:
	await _until(57.42)
	var rec := HitRecorder.new()
	rec.name = "SnapRecorder"
	add_child(rec)
	rec.heard_source = _given_clock(SNAP_SONG, true)
	var shaker := _room.items.get(&"shaker") as InstrumentItem
	var first := HitRecorder.nearest_sixteenth(SNAP_SONG + 0.2, DAW.state) - SNAP_EARLY
	var second := HitRecorder.nearest_sixteenth(first + 0.3, DAW.state) - SNAP_EARLY
	rec.hit(shaker, 90, first, TAKE_TRACK, 1)
	rec.hit(shaker, 90, second, TAKE_TRACK, 0)
	Session.send_item_hit(shaker.id, 90, first, true, 5)
	Session.send_item_hit(shaker.id, 90, second, false, 6)
	var file := FileAccess.open("/tmp/r3d_probe_snap_%d.json" % _port, FileAccess.WRITE)
	file.store_string(JSON.stringify({"first": first, "second": second,
			"snapped": HitRecorder.snapped_at(first, DAW.state)}))
	file.close()
	check("my snapped hit is half way to its sixteenth in my take, my other where I played it",
			is_equal_approx(HitRecorder.snapped_at(first, DAW.state), first + SNAP_EARLY * HitRecorder.SNAP_PULL)
			and rec.jacked_tracks() == [TAKE_TRACK])
	await _until(57.46)
	rec.heard_source = _given_clock(SNAP_SONG + 1.0, false)
	await _until(57.5)
	check("and the take went to the host (%s)" % [rec.last_take],
			int(rec.last_take.get("notes", 0)) == 2 and int(rec.last_take.get("track", 0)) == TAKE_TRACK)
	rec.queue_free()


## Plays a take into track TAKE_TRACK while the host records, through the same door a MIDI
## keyboard uses (InputEventMIDI), timed against the clicks of the host's test tone: it clicks
## on every whole second of the song, so a click heard at frame n says song second S was at the
## "speaker" at the moment the drain took frame n. A note played t seconds after that click was
## played at S + t, and that is where it has to land.
func _guest_records() -> void:
	var gm := Session.guest_midi
	gm.target_track = TAKE_TRACK
	var changed_usec := [0]
	gm.changed.connect(func(): changed_usec[0] = Time.get_ticks_usec())
	var expected: Array = []
	var ons := {}
	var seen := Session.mix_feed.clicks_heard().size()
	var clicks_used := 0
	var settled := 0
	var ref_usec := 0
	var ref_second := 0.0
	var timeout_at := _start + int((12.6 + _shift) * 1000.0)
	var pending_72 := 0
	while Time.get_ticks_msec() < timeout_at and clicks_used < 3 or pending_72 > 0:
		await get_tree().process_frame
		if Time.get_ticks_msec() > timeout_at + 500:
			break
		var clicks: Array = Session.mix_feed.clicks_heard()
		var now := Time.get_ticks_usec()
		if pending_72 == 1 and now - ref_usec >= 250000 and clicks_used >= 1:
			pending_72 = 2
			var t := await _play(true, 72, 70, changed_usec)
			ons[72] = ref_second + (t - ref_usec) / 1000000.0
		elif pending_72 == 2 and now - ref_usec >= 500000:
			pending_72 = 0
			var t := await _play(false, 72, 0, changed_usec)
			expected.append([72, ons[72], ref_second + (t - ref_usec) / 1000000.0])
		if clicks.size() <= seen:
			continue
		seen = clicks.size()
		if not gm.is_recording() or clicks_used >= 3:
			continue
		print("take: click at %.2fs (settled %d, used %d)" % [(Time.get_ticks_msec() - _start) / 1000.0 - _shift, settled, clicks_used])
		if settled < SETTLE_CLICKS:
			settled += 1
			continue
		var click: Array = clicks.back()
		var h := Session.mix_feed.heard_position()
		ref_usec = click[1]
		ref_second = roundf(float(h["seconds"]) - (now - ref_usec) / 1000000.0)
		clicks_used += 1
		var at := func(t: int) -> float: return ref_second + (t - ref_usec) / 1000000.0
		match clicks_used:
			1:
				ons[60] = at.call(await _play(true, 60, 100, changed_usec))
				pending_72 = 1
			2:
				var t := await _play(false, 60, 0, changed_usec)
				expected.append([60, ons[60], at.call(t)])
				ons[64] = at.call(await _play(true, 64, 90, changed_usec))
			3:
				ons[67] = at.call(await _play(true, 67, 110, changed_usec))
				var t := await _play(false, 64, 0, changed_usec)
				expected.append([64, ons[64], at.call(t)])
				expected.append([67, ons[67], null])
	check("the take ran while the host recorded, with notes played on three clicks (%d)" % clicks_used,
			clicks_used == 3 and gm.is_recording())
	var file := FileAccess.open("/tmp/r3d_probe_take_%d.json" % _port, FileAccess.WRITE)
	file.store_string(JSON.stringify({"notes": expected, "hanging": 67}))
	file.close()
	await _until(13.8)
	check("the take was sent when I heard the recording stop", not gm.is_recording()
			and gm.last_take.get("notes", 0) == 4)
	check("the host told me where it went (%s)" % [_notices],
			_notices.any(func(t): return t.begins_with("Your take is on")))
	var back: Array = DAW.state.track(TAKE_TRACK).items.filter(func(it): return it.name == "Grace take 1")
	check("and it came back to me, notes and all",
			back.size() == 1 and MidiTake.unpack_relative(back[0].notes, back[0].start).size() == 4)


## One key, down or up, as a MIDI keyboard would send it. Returns when the guest stamped it.
func _play(down: bool, pitch: int, velocity: int, changed_usec: Array) -> int:
	var before: int = changed_usec[0]
	var e := InputEventMIDI.new()
	e.message = MIDI_MESSAGE_NOTE_ON if down else MIDI_MESSAGE_NOTE_OFF
	e.pitch = pitch
	e.velocity = velocity
	e.channel = 0
	Input.parse_input_event(e)
	while changed_usec[0] == before:
		await get_tree().process_frame
	return changed_usec[0]


func _keep_publishing(head: Transform3D, pointing: String) -> void:
	_head = head
	_pointing = pointing
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.autostart = true
	timer.timeout.connect(func(): Session.publish_presence(_head, _pointing, _pointing_local))
	add_child(timer)


## The harp's seat in the room's venue (Session.room), in the session's frame, as both halves
## stand it: Stations.seat with nothing to say where a person fits, since neither half here stands
## a studio's furniture round it. Null where the venue stands no harp.
func _harp_seat() -> Variant:
	var venue := Venue.make(Session.room.get("venue", Venue.IDS[0]))
	var seat: Variant = Stations.seat(venue, &"harp")
	venue.free()
	return seat


## Going to a station in a headset (docs/spatial_loop.md slice 11), as the studio does it: a
## simulated rig in the session's frame (RoomAnchor, handed over whole) travels to the harp's
## seat, and from then on the head this half publishes is the one Presence would, wherever the
## travel put it.
func _travel_to_the_harp() -> void:
	var anchor := RoomAnchor.new()
	add_child(anchor)
	anchor.adopt_virtual_frame(1.2)
	var rig := XRRig.new()
	rig.simulated = true
	add_child(rig)
	rig.head.position = TRAVEL_OFFSET
	var seat: Variant = _harp_seat()
	check("the room's venue stands a harp to go to", seat != null)
	if seat == null:
		return
	rig.travel(seat as Transform3D)
	await get_tree().create_timer(XRRig.FADE * 2.0 + 0.1).timeout
	var presence := Presence.new()
	presence.head_node = rig.head
	presence.frame = anchor
	_head = presence.head_in_session()
	presence.free()
	var wanted := (seat as Transform3D) * TRAVEL_OFFSET
	check("my travel put my head at the harp's seat, as I stood in my play space (%.3f m)" % _head.origin.distance_to(wanted),
			_head.origin.distance_to(wanted) < 0.05 and rig.away and rig.veil() == 0.0)


## The first send that goes somewhere, as [track, slot]: the same answer on both halves, since
## the guest's copy of the project is the host's.
static func _first_send(state: MixState) -> Array:
	for index in state.track_indices():
		var t := state.track(index)
		var slots: Array = t.sends.keys()
		slots.sort()
		for slot in slots:
			if int(slot) >= 1 and (t.sends[slot] as MixState.SendState).resolve(state) > 0:
				return [index, int(slot)]
	return []


## The guest's SET, as `whose` markers have it: a marker of brackets alone at WHEEL_BAR's start,
## the harmony from there by it (its second bar C), and the bar before it still the harp's D minor.
func _check_wheel(whose: String) -> void:
	var s := DAW.state
	var at := s.bar_to_seconds(WHEEL_BAR + 1.0)
	var key := DAWBackend.marker_key(s.markers, at)
	var named: String = s.markers.get(key, "") if not is_nan(key) else ""
	check("the guest's SET is a marker in %s markers at bar %d (%s)" % [whose, WHEEL_BAR + 1, named],
			named == "[%s]" % WHEEL_INSIDE)
	var second := Harmony.at(s, s.bar_to_seconds(WHEEL_BAR + 2.0) + 0.01)
	var before := Harmony.at(s, at - 0.05)
	print("wheel: %s at %.3f; bar %d is %s in %s, the bar before %s in %s" % [named, at, WHEEL_BAR + 2,
			second.chord_name, second.key_name, before.chord_name, before.key_name])
	check("and Harmony.at reads it there: C in E minor, after D minor's Dm (%s, %s)" % [second.chord_name, before.chord_name],
			second.chord_name == "C" and second.key_name == "E minor" and before.chord_name == "Dm")


func _other_id() -> int:
	for id in Session.participants:
		if id != Session.local_peer_id:
			return id
	return 0


## A note from the other half, by what played it: plain keys into `_notes`, an instrument's into
## `_sourced`.
func _on_note_played(kind: int, pitch: int, velocity: int, from: int, song: float,
		source := &"") -> void:
	if source == ChordHarp.SOURCE:
		_harped.append([kind, pitch, from, song])
	if source == &"":
		_notes.append([kind, pitch, velocity, from])
	else:
		_sourced.append([kind, pitch, from, source])


## A room of items, as the studio keeps one, and the four handbells in it.
func _check_bells() -> void:
	_room = ItemRoom.new()
	add_child(_room)
	# Made items' rows are the session's, as the studio shares them (slice 23).
	_room.made = Session.made
	# The chord ledge's sixteen slots (slice 31), as the studio holds them, here in front of the room.
	_room.set_holder(ChordBrick.LEDGE, ChordLedge.slots_in(Transform3D(Basis.IDENTITY, Vector3(0, 0.76, 1.0))))
	# The sampler (slice 26), as the studio stands one: its cassettes into this room.
	if Session.role == Session.Role.HOST:
		_sampler = Sampler.new()
		_sampler.items = _room
		_sampler.authority = Session.is_authority
		_sampler.local_peer = func() -> int: return Session.local_peer_id
		_sampler.name_of = Session.name_of
		add_child(_sampler)
	var bells := ["bell1", "bell2", "bell3", "bell4"].filter(func(id: String) -> bool:
		return _room.items.get(StringName(id)) is HandbellItem)
	check("the four handbells are in my room's items (%s)" % [bells], bells.size() == HandbellItem.COUNT)


## The host's answer to a plug, as the studio's: the host's rule (Jacks.refusal), and the room
## published with the jack in it.
func _answer_plug(args: Array, from: int) -> void:
	var item: Item = _room.items.get(args[0]) if _room != null else null
	var holder := Session.holder_of(item.network_key()) if item != null else 0
	var room: Dictionary = Session.room.duplicate(true)
	var rows: Dictionary = room.get("jacks", {})
	var now := StringName(str(rows.get(String(args[0]), "")))
	if Jacks.plug_refusal(args[0], item, args[1], from, holder, now, Session.participants.keys()) != "":
		return
	if args[1] == &"":
		rows.erase(String(args[0]))
	else:
		rows[String(args[0])] = String(args[1])
	room["jacks"] = rows
	Session.publish_room(room)
	if _jacks != null:
		_jacks.set_patch(rows)


## The host's answer to a guest's pull (slice 23), as the studio's: the clip packed from my own song,
## minted, its row sent once, the cassette put in the guest's hand by the holds, and the room naming
## it.
func _answer_make(args: Array, from: int) -> void:
	var made := _room.mint(args[0], ItemRoom.made_data(args[0], args[1]), from) if _room != null else null
	check("the guest's pull is one I can mint (%s)" % (_room.mint_refusal if _room != null else "no room"), made != null)
	if made == null:
		return
	Session.publish_made(made.id)
	# A guest's MAKE BRICKS (slice 31): onto my ledge, at the end of its row, as the studio's.
	if made is ChordBrick and ChordBrick.into_ledge(str(args[1])):
		var n := _room.next_in_order(ChordBrick.LEDGE)
		check("there is a free slot on my ledge for the guest's %s brick (%d)" % [(made as ChordBrick).chord, n], n >= 0)
		if n >= 0:
			_room.slot(made, ChordBrick.LEDGE, n)
		_bricks_for_guest.append(made.id)
		_publish_brick_room()
		return
	Session.hand_to(from, made.network_key())
	_made_for_guest.append(made.id)
	var room: Dictionary = Session.room.duplicate(true)
	room["made"] = _room.made_ids()
	Session.publish_room(room)


## A cassette of my own, minted here and handed to the guest, as the studio's give does it.
func _give_a_cassette() -> void:
	var guest := _other_id()
	var made := _room.mint(CassetteItem.KIND, ItemRoom.made_data(CassetteItem.KIND, PULL_FROM))
	check("I mint a cassette of my own (%s)" % _room.mint_refusal, made != null)
	if made == null:
		return
	Session.publish_made(made.id)
	Session.hand_to(guest, made.network_key())
	_made_for_guest.append(made.id)
	var room: Dictionary = Session.room.duplicate(true)
	room["made"] = _room.made_ids()
	Session.publish_room(room)


## Both cassettes are the guest's, as my table has it, and their rows mine.
func _check_cassettes_given() -> void:
	var guest := _other_id()
	check("the guest's pull and my give are two cassettes (%s)" % [_made_for_guest],
			_made_for_guest == [&"cassette1", &"cassette2"])
	for id in _made_for_guest:
		var item: Item = _room.items.get(id)
		check("%s is in the guest's glove, as my table has it (%d)" % [id, Session.holder_of(item.network_key()) if item != null else -1],
				item != null and Session.holder_of(item.network_key()) == guest)
		check("and its row is the room's (%s)" % id, Session.made.has(id))
	var pulled := _room.items.get(&"cassette1") as CassetteItem
	var from := DAW.state.item(PULL_TRACK, 0)
	if pulled != null and from != null:
		var clip := MixWire.unpack_item(pulled.clip)
		check("and the pulled one is my clip (%s, %.2f s)" % [pulled.clip_name(), pulled.length()],
				clip != null and is_equal_approx(clip.start, from.start) and is_equal_approx(clip.length, from.length))


## The host's answer to a guest's paste (slice 24), as the studio's: only the cassette in the
## asker's hand, its clip from my own row, pasted as one step for the guest, or refused with why.
func _answer_paste(args: Array, from: int) -> void:
	_paste_asked = args
	var cassette := _room.items.get(args[0]) as CassetteItem if _room != null else null
	if cassette == null or Session.holder_of(cassette.network_key()) != from:
		_paste_said = "not in the asker's hand"
		return
	_paste_said = DAW.paste_item(args[1], args[2], cassette.clip)
	Session.tell(from, _paste_said if not _paste_said.is_empty() else "Pasted.")


## The guest's paste, as my DAW has it: asked by the cassette's id, PASTE_TRACK and its time at
## PASTE_BAR, and an item there that is the cassette's clip but for its start and track, one step.
## The demo song's items are windows of parts, so on Reaper (which has none) it is refused, and says so.
func _check_pasted() -> void:
	check("the guest's paste names the cassette I gave it, track %d and a time at bar %d (%s)" % [PASTE_TRACK, int(PASTE_BAR), _paste_asked],
			_paste_asked.size() == 3 and _paste_asked[0] == &"cassette2" and _paste_asked[1] == PASTE_TRACK
			and DAW.state.bar_beat(float(_paste_asked[2])).begins_with("%d.1." % int(PASTE_BAR)))
	var cassette := _room.items.get(&"cassette2") as CassetteItem
	if cassette != null and cassette.clip.has("part") and not DAW.can(DAWBackend.Capability.DEMO_PARTS):
		check("on Reaper a demo part is refused, and it says why (%s)" % _paste_said, _paste_said.contains("built-in engine"))
		return
	check("and I pasted it (%s)" % ("yes" if _paste_said.is_empty() else _paste_said), _paste_said.is_empty())
	var it: MixState.ItemState = null
	if _paste_asked.size() == 3:
		for item: MixState.ItemState in DAW.state.track(PASTE_TRACK).items:
			if absf(item.start - float(_paste_asked[2])) < 0.001:
				it = item
	var mine := MixWire.pack_item(it) if it != null else {}
	var theirs := cassette.clip.duplicate() if cassette != null else {}
	mine.erase("start")
	theirs.erase("start")
	check("on track %d at bar %d is the cassette's clip but for its start and track (%s)" % [PASTE_TRACK, int(PASTE_BAR), it.name if it != null else "none"],
			it != null and not theirs.is_empty() and mine == theirs)


## Host: the bricks minted for the guest's MAKE BRICKS (slice 31), and the history's depth before
## the section they are pressed onto.
var _bricks_for_guest: Array[StringName] = []
var _brick_depth := -1


## The song's seconds at a bar of the bricks' section, BRICK_BAR from 0.
func _brick_at(bars: float) -> float:
	return DAW.state.bar_to_seconds(BRICK_BAR + 1.0 + bars)


## The room with my bricks in it, as the studio publishes it: their ids, where they are (the room's
## `items`, only theirs here) and their lengths (`bricks`).
func _publish_brick_room() -> void:
	var room: Dictionary = Session.room.duplicate(true)
	room["made"] = _room.made_ids()
	var where := _room.state()
	var items := {}
	var bricks := {}
	for id in _room.items:
		var brick := _room.items[id] as ChordBrick
		if brick != null:
			bricks[id] = brick.bars
			if where.has(id):
				items[id] = where[id]
	room["items"] = items
	room["bricks"] = bricks
	Session.publish_room(room)


## The guest's nudge of a brick (slice 31), as the studio answers it: a length that is one, of a
## brick nobody else holds.
func _answer_bricks(args: Array, from: int) -> void:
	var brick := _room.items.get(args[0]) as ChordBrick if _room != null else null
	var holder := Session.holder_of(brick.network_key()) if brick != null else 0
	if brick == null or not int(args[1]) in ChordBrick.LENGTHS or (holder != 0 and holder != from):
		return
	brick.bars = int(args[1])
	_publish_brick_room()


## A section of mine past the arrangement's, four bars, its marker at its start (slice 31).
func _lay_out_a_brick_section() -> void:
	_brick_depth = DAW.state.undo_depth
	DAW.add_region(_brick_at(0.0), _brick_at(4.0), BRICK_SECTION)
	DAW.add_marker(_brick_at(0.0), BRICK_SECTION)


## The guest's bricks and its press of their row (slice 31), as my room and my DAW have them: three
## on my ledge in its order, made by the guest, the second 2 bars; and the section's marker
## bracketed with the row, as one step, so the third bar of it is in F and its first in A minor.
func _check_bricks_pressed() -> void:
	var guest := _other_id()
	var row := ChordBrick.ledge_row(_room)
	check("the guest's MAKE BRICKS is %d bricks on my ledge, in order (%s)" % [BRICK_CHORDS.size(), ChordBrick.chords_text(row)],
			row.map(func(b: ChordBrick) -> String: return b.chord) == BRICK_CHORDS
			and row.map(func(b: ChordBrick) -> int: return b.slot_n) == range(BRICK_CHORDS.size()))
	var theirs := func(b: ChordBrick) -> bool:
		return Session.made.has(b.id) and int(Session.made[b.id][1]) == guest and b.key == BRICK_KEY
	check("each made by the guest, minted from its words, a chord and its key (%s)" % [row.map(func(b): return b.data)],
			row.all(theirs))
	check("its nudge made the second 2 bars, my room's row (%s)" % [Session.room.get("bricks", {})],
			row.size() == 3 and row[1].bars == 2 and int(Session.room.get("bricks", {}).get(row[1].id, 0)) == 2)
	var at := DAWBackend.marker_key(DAW.state.markers, _brick_at(0.0))
	var named := str(DAW.state.markers[at]) if not is_nan(at) else ""
	check("its press of the row onto my section block bracketed the section's marker (%s)" % named, named == BRICK_MARKER)
	var third := Harmony.at(DAW.state, _brick_at(2.0) + 0.05)
	var first := Harmony.at(DAW.state, _brick_at(0.0) + 0.05)
	check("so the section's third bar is in F and its first in A minor (%s, %s)" % [third.chord_name if third != null else "none",
			first.chord_name if first != null else "none"], third != null and third.chord_name == "F" and first != null
			and first.chord_name == "Am")
	var sets := _room_asks.filter(func(a: Array) -> bool: return a[0] == FifthsWheel.VERB)
	check("as the wheel's ask with the section's bar (%s)" % [sets.slice(-1)], sets.size() == 2
			and sets[-1][1] == [int(BRICK_BAR), "A minor: Am F - C"] and sets[-1][2] == guest)


## The section and its harmony taken back, and the bricks gone.
func _take_back_the_bricks() -> void:
	if _brick_depth >= 0 and DAW.state.undo_depth >= 0:
		DAW.undo_to(_brick_depth)
	else:
		for _i in 3:
			DAW.undo()
	for id in _bricks_for_guest:
		_room.unmake(id)
		Session.drop_made(id)
	_publish_brick_room()


## Host: how many steps the sections' layout made (slice 29), the rearrangement among them, so all
## of it is taken back; and the history's depth before them, where the DAW says it.
var _arrange_steps := 0
var _arrange_depth := -1


## The song's seconds at a bar of the sections' stretch, ARRANGE_BAR from 0.
func _arrange_at(bars: float) -> float:
	return DAW.state.bar_to_seconds(ARRANGE_BAR + 1.0 + bars)


## Three regions of mine past the song, two bars each, a marker inside the second and a take of
## mine inside the third (slice 29), for the guest to rearrange.
func _lay_out_sections() -> void:
	_arrange_depth = DAW.state.undo_depth
	for k in 3:
		DAW.add_region(_arrange_at(2.0 * k), _arrange_at(2.0 * k + 2.0), ARRANGE_NAMES[k])
	DAW.add_marker(_arrange_at(3.5), "Probe hook")
	DAW.insert_midi_take(HOST_MIDI_TRACK, _arrange_at(4.5), _arrange_at(5.5),
			[[_arrange_at(4.75), _arrange_at(5.0), 60, 100, 0]], "Probe take")
	_arrange_steps = 5


## The guest's order C A B (slice 29), as my DAW has it: C first, where A was, with my take in it, and
## B last with its marker; as one step named for it, on the built-in engine.
func _check_rearranged() -> void:
	var regions: Array = DAW.state.regions
	var named := func(n: String) -> Array:
		for r in regions:
			if r[2] == n:
				return r
		return []
	var a: Array = named.call("Probe A")
	var b: Array = named.call("Probe B")
	var c: Array = named.call("Probe C")
	check("the guest's order put C first, then A, then B, where the three were (%s)" % [[a, b, c]],
			not c.is_empty() and absf(float(c[0]) - _arrange_at(0.0)) < 0.002 and not a.is_empty()
			and absf(float(a[0]) - _arrange_at(2.0)) < 0.002 and not b.is_empty() and absf(float(b[0]) - _arrange_at(4.0)) < 0.002)
	var hook := false
	for t in DAW.state.markers:
		if DAW.state.markers[t] == "Probe hook" and absf(float(t) - _arrange_at(5.5)) < 0.002:
			hook = true
	check("the marker inside B went with it", hook)
	var take := false
	for it: MixState.ItemState in DAW.state.track(HOST_MIDI_TRACK).items:
		if it.name == "Probe take" and absf(it.start - _arrange_at(0.5)) < 0.002:
			take = true
	check("and my take inside C with C", take)
	if not c.is_empty() and absf(float(c[0]) - _arrange_at(0.0)) < 0.002:
		_arrange_steps += 1
	if _reaper_resource == "" and DAW.state.undo_depth > 0:
		var last := str(DAW.state.undo_names[DAW.state.undo_depth - 1])
		check("as one step of mine, called for it (%s)" % last, last == "arrange sections")


## The rearrangement and the layout taken back: to where the history was, or a step at a time where
## the DAW does not say its depth.
func _take_back_the_sections() -> void:
	if _arrange_depth >= 0 and DAW.state.undo_depth >= 0:
		DAW.undo_to(_arrange_depth)
	else:
		for _i in _arrange_steps:
			DAW.undo()


## The paste taken back, one step, and the made items gone.
func _take_back_the_paste() -> void:
	if _paste_said.is_empty():
		DAW.undo()
	for id in _made_for_guest:
		_room.unmake(id)
		Session.drop_made(id)


## The host's answer to the guest's REC (slice 26), as the studio's: on for its next sound, or off,
## and the room published with the row.
func _answer_sampler(args: Array, from: int) -> void:
	if _sampler == null:
		return
	_sampler.armed_by = from if args[0] else 0
	_publish_sampler_room()


func _publish_sampler_room() -> void:
	var room: Dictionary = Session.room.duplicate(true)
	room["sampler"] = _sampler.armed_by if _sampler != null else 0
	room["made"] = _room.made_ids() if _room != null else []
	Session.publish_room(room)


## A use the host hears (Session.item_used), for the sampler, as the studio's: only of what is in
## its user's hand. Caught, its cassette's row goes to everyone and the room names it, REC off.
func _sample_a_use(id: StringName, down: bool, from: int, take: int) -> void:
	if _sampler == null or _room == null or not down or from == Session.local_peer_id:
		return
	var item: Item = _room.items.get(id)
	if item == null or Session.holder_of(item.network_key()) != from:
		return
	var file_name := _sampler.next_name(item.use_kind(true))
	var made := _sampler.heard(item, item.use_kind(true), take, from, item.use_pitch())
	if made == null:
		return
	_sampled = [made.id, file_name, from]
	Session.publish_made(made.id)
	_publish_sampler_room()


## The guest's squeeze, as I caught it: its take came with it, one WAV of exactly Foley's stream for
## that take, a cassette the guest made of it, and REC off.
func _check_sampled() -> void:
	var guest := _other_id()
	var takes: Array = []
	for n in _uses.size():
		if _uses[n][0] == &"duck" and _uses[n][1] and _uses[n][2] == guest:
			takes.append(_use_takes[n])
	check("the guest's squeeze reached me with the take its hand rang (%s)" % [takes], takes.has(SAMPLE_TAKE))
	check("my sampler caught it (%s)" % [_sampled], _sampled.size() == 3 and _sampled[2] == guest)
	if _sampled.size() != 3:
		return
	var path := DAW.backend.media_path(_sampled[1])
	var bytes := FileAccess.get_file_as_bytes(path)
	var body := bytes.slice(AudioTake.HEADER_BYTES) if bytes.size() > AudioTake.HEADER_BYTES else PackedByteArray()
	check("as one WAV in my media, %s, equal to Foley's stream for take %d (%d bytes)" % [_sampled[1], SAMPLE_TAKE, body.size()],
			String(_sampled[1]).begins_with("duck_squeeze_") and body == Foley.take_of(&"duck_squeeze", SAMPLE_TAKE).data)
	var cassette := _room.items.get(_sampled[0]) as CassetteItem
	check("and a sample cassette of it, made by the guest", cassette != null and cassette.data.get("sample") == "duck_squeeze"
			and cassette.clip.get("source") == _sampled[1] and (Session.made[_sampled[0]] as Array)[1] == guest)
	check("and REC is off, in the room too (%s)" % [Session.room.get("sampler")], _sampler.armed_by == 0
			and int(Session.room.get("sampler", -1)) == 0)


## The sample cassette and its file taken away again.
func _take_back_the_sample() -> void:
	if _sampled.size() == 3:
		_room.unmake(_sampled[0])
		Session.drop_made(_sampled[0])
		DirAccess.remove_absolute(DAW.backend.media_path(_sampled[1]))
		_publish_sampler_room()


## Anything can be a sample (slice 26): at 59.36 I press the host's sampler's REC, as the studio's
## press asks; by 59.42 the room's row is mine. At 59.44 I take the duck, and at 59.48 squeeze it,
## my hand ringing SAMPLE_TAKE. By 59.55 the host's sample cassette of it is mine, its row here and
## the room naming it, and REC is off.
func _sample_a_squeeze() -> void:
	await _until(59.36)
	var seq := Session.ask_room(Sampler.VERB, [true])
	check("my REC is asked of the host (seq %d)" % seq, seq > 0)
	await _until(59.42)
	check("and the room's sampler row is mine: REC replicates (%s)" % [Session.room.get("sampler")],
			int(Session.room.get("sampler", 0)) == Session.local_peer_id)
	await _until(59.44)
	Session.claim_hold(DUCK)
	await _until(59.48)
	check("the duck is in my hand, as the host's table has it", Session.holder_of(DUCK) == Session.local_peer_id)
	Session.send_item_use(&"duck", true, SAMPLE_TAKE)
	Session.send_item_use(&"duck", false, SAMPLE_TAKE + 1)
	await _until(59.55)
	check("REC is off again in the host's room (%s)" % [Session.room.get("sampler")], int(Session.room.get("sampler", -1)) == 0)
	var mine: Array = []
	for id in Session.made:
		var row: Array = Session.made[id]
		var data: Variant = bytes_to_var(row[2]) if row.size() == 3 and row[2] is PackedByteArray else null
		if data is Dictionary and data.get("sample") == "duck_squeeze" and int(row[1]) == Session.local_peer_id:
			mine.append(id)
	check("and the host's sample cassette of my squeeze is here, made by me (%s)" % [mine], mine.size() == 1)
	check("named in the room", mine.size() == 1 and (Session.room.get("made", []) as Array).has(mine[0]))
	Session.release_hold(DUCK)


## The guest's spin of its platter, as my DAW has it (slice 27): my playhead at PLATTER_TURNS, a bar a
## turn, or just past it if the song played on when the guest let go.
func _check_platter_seek() -> void:
	var at := Platter.seconds_of(PLATTER_TURNS)
	var now := DAW.state.position_seconds
	check("the guest's spin of its platter moved my playhead to bar %d (%.3f s, wanted %.3f)" % [roundi(PLATTER_TURNS) + 1, now, at],
			now >= at - 0.01 and now <= at + (0.3 if DAW.state.playing else 0.01))


## The guest's crank, as my history has it (slice 28): CRANK_NOTCHES steps back from `from`, in one
## jump. Where my DAW does not say its depth, that it asked two undos is the guest's check.
func _check_cranked(from: int) -> void:
	if from < 0:
		check("my DAW does not say its history's depth, so the guest's crank asked undos (checked there)", true)
		return
	check("the guest's history crank took my history %d back, from %d to %d" % [CRANK_NOTCHES, from,
			DAW.state.undo_depth], from >= CRANK_NOTCHES and DAW.state.undo_depth == from - CRANK_NOTCHES)


## Chord bricks (slice 31): at 60.42 my MAKE BRICKS asks the host for BRICK_CHORDS onto the ledge, as
## the studio's wheel does, by their words; by 60.46 the host's room has them in a row on my copy of
## its ledge. I nudge the second to 2 bars (the room's `bricks`), and at 60.5, the host's row saying
## so, press my ledge's row onto the host's section block: the wheel's `harmony` ask with that
## section's bar. By 60.56 my copy of the host's markers has the section bracketed with the row.
func _press_the_bricks() -> void:
	await _until(60.42)
	for c in BRICK_CHORDS:
		Session.ask_room(&"make", [ChordBrick.KIND, ChordBrick.from_text(true, BRICK_KEY, c)])
	await _until(60.46)
	_apply_brick_room()
	var row := ChordBrick.ledge_row(_room)
	check("the host's room has my bricks on its ledge, in order, here too (%s)" % ChordBrick.chords_text(row),
			row.map(func(b: ChordBrick) -> String: return b.chord) == BRICK_CHORDS
			and row.all(func(b: ChordBrick) -> bool: return Session.made.has(b.id)))
	if row.size() != BRICK_CHORDS.size():
		return
	var seq := Session.ask_room(&"bricks", [row[1].id, 2])
	check("my nudge of the second is asked of the host as the room's bricks row (seq %d)" % seq, seq > 0)
	await _until(60.5)
	_apply_brick_room()
	check("and the host's row has it 2 bars (%s)" % [Session.room.get("bricks", {})], row[1].bars == 2)
	var start := NAN
	for r in DAW.state.regions:
		if r[2] == BRICK_SECTION:
			start = float(r[0])
	check("I have the host's section %s (%s)" % [BRICK_SECTION, start], not is_nan(start))
	if is_nan(start):
		return
	var asked := ChordBrick.section_ask(row, DAW.state, start)
	check("my ledge's row pressed onto its block asks [%s] at its bar (%s)" % [asked[1], asked],
			asked == [int(BRICK_BAR), "A minor: Am F - C"])
	Session.ask_room(FifthsWheel.VERB, asked)
	await _until(60.56)
	var at := DAWBackend.marker_key(DAW.state.markers, start)
	var named := str(DAW.state.markers[at]) if not is_nan(at) else ""
	check("and my copy of the host's markers has the section bracketed with the row (%s)" % named, named == BRICK_MARKER)
	var third := Harmony.at(DAW.state, DAW.state.bar_to_seconds(BRICK_BAR + 3.0) + 0.05)
	check("its third bar in F here too (%s)" % (third.chord_name if third != null else "none"), third != null and third.chord_name == "F")


## The host's bricks, as its room has them (slice 31): made real here, laid in my copy of its ledge
## where it says, each its length. Only the bricks: everything else in the room stays as it is.
func _apply_brick_room() -> void:
	_room.apply_made(Session.room.get("made", []))
	var where: Dictionary = Session.room.get("items", {})
	var entries := {}
	var others := {}
	for id in _room.items:
		if _room.items[id] is ChordBrick:
			if where.has(id):
				entries[id] = where[id]
			elif where.has(String(id)):
				entries[id] = where[String(id)]
		else:
			others[id] = true
	_room.apply(entries, others)
	var lengths: Dictionary = Session.room.get("bricks", {})
	for id in lengths:
		var brick := _room.items.get(StringName(id)) as ChordBrick
		if brick != null and int(lengths[id]) in ChordBrick.LENGTHS:
			brick.bars = int(lengths[id])


## Sections rearranged (slice 29): at 60.24 I ask the order C A B of the host's three probe regions,
## as my copy of its regions has them, its other regions where they are; nothing moves here until the
## host's mix says so. By 60.34 my copy has C first, and the room's notice names the new order.
func _rearrange_the_sections() -> void:
	await _until(60.24)
	var regions: Array = DAW.state.regions
	var at: Array = []
	for n in ARRANGE_NAMES:
		for i in regions.size():
			if regions[i][2] == n:
				at.append(i)
	check("I have the host's three probe sections, one after another (%s)" % [at], at.size() == 3
			and at[1] == at[0] + 1 and at[2] == at[1] + 1)
	if at.size() != 3:
		return
	var order: Array = range(regions.size())
	order[at[0]] = at[2]
	order[at[1]] = at[0]
	order[at[2]] = at[1]
	var said := DAW.arrange_sections(order)
	check("my order is asked of the host (%s)" % ("asked" if said.is_empty() else said), said.is_empty())
	await _until(60.34)
	var first: Array = DAW.state.regions[at[0]] if DAW.state.regions.size() > at[0] else []
	check("and my copy has C where A was (%s)" % [first], not first.is_empty() and first[2] == "Probe C")
	check("and the room was told the new order (%s)" % [_notices.filter(func(t): return t.contains("sections"))],
			_notices.any(func(t): return t.contains("rearranged the sections") and t.contains("Probe C · Probe A · Probe B")))


## A tape reel for undo history (slice 28): at 59.78 I turn a history crank of my own, as the
## studio's on the tape deck, back CRANK_NOTCHES a notch at a time, and leave it to settle. Not
## played back, so the host's transport is as the end needs it. It asks the host one undo_to, and
## by 60.12 my copy of the host's history is there.
func _crank_the_history() -> void:
	await _until(59.78)
	var crank := ReelCrank.new()
	crank.plays_back = false
	add_child(crank)
	Session.keep_intents = true
	Session.kept_intents.clear()
	var from: int = DAW.state.undo_depth
	for n in CRANK_NOTCHES:
		crank.turn_to(-(n + 1))
		await get_tree().process_frame
	await _until(60.08)
	var asks := Session.kept_intents.filter(func(i: Array) -> bool: return i[0] in [&"undo_to", &"undo", &"redo"])
	if from >= 0:
		check("my crank, settled, asked the host one undo_to(%d) (%s)" % [from - CRANK_NOTCHES, asks], asks.size() == 1
				and asks[0][0] == &"undo_to" and int(asks[0][1][0]) == from - CRANK_NOTCHES and crank.clicks == CRANK_NOTCHES)
	else:
		check("my crank, settled, asked the host %d undos, its depth unsaid (%s)" % [CRANK_NOTCHES, asks],
				asks.size() == CRANK_NOTCHES and asks.all(func(i: Array) -> bool: return i[0] == &"undo"))
	Session.keep_intents = false
	Session.kept_intents.clear()
	await _until(60.12)
	if from >= 0:
		check("and the host's history came back %d steps back (%d, from %d)" % [CRANK_NOTCHES, DAW.state.undo_depth, from],
				DAW.state.undo_depth == from - CRANK_NOTCHES and crank.standing() == from - CRANK_NOTCHES)
	crank.queue_free()


## A DJ platter (slice 27): at 59.6 I take hold of a platter of my own, as the studio's on the deck's
## cart, and turn it to PLATTER_TURNS over the next frames, letting go once my hand has been still on
## it long enough to read as still (from where the sections before leave the song, well past bar 7, a
## quick turn back let go at once would be a flick, and spin back). My turns are seeks asked of the host,
## SEEK_HZ a second at most, and never a scrub: the host's DAW is the host's.
func _spin_the_platter() -> void:
	await _until(59.6)
	var platter := Platter.new()
	platter.authority = Session.is_authority
	add_child(platter)
	Session.keep_intents = true
	Session.kept_intents.clear()
	var began := Time.get_ticks_msec()
	platter.hold()
	var from := platter.turns
	var frames := 0
	while (Time.get_ticks_msec() - began) / 1000.0 < 0.04:
		frames += 1
		platter.turn_to(lerpf(from, PLATTER_TURNS, minf((Time.get_ticks_msec() - began) / 30.0, 1.0)))
		await get_tree().process_frame
	platter.turn_to(PLATTER_TURNS)
	await get_tree().process_frame
	var still_from := Time.get_ticks_msec()
	while absf(platter.speed()) > 0.001 and Time.get_ticks_msec() - still_from < 250:
		await get_tree().process_frame
	platter.let_go()
	await _until(59.72)
	var seconds := (Time.get_ticks_msec() - began) / 1000.0
	var seeks := Session.kept_intents.filter(func(i: Array) -> bool: return i[0] == &"seek")
	check("my platter's turns were seeks asked of the host, %d in %.2f s, %d a second at most" % [seeks.size(), seconds,
			roundi(Platter.SEEK_HZ)], not seeks.is_empty() and seeks.size() <= ceili(seconds * Platter.SEEK_HZ) + 1
			and is_equal_approx(float(seeks[-1][1][0]), Platter.seconds_of(PLATTER_TURNS)))
	check("and never a scrub", not Session.kept_intents.any(func(i: Array) -> bool: return i[0] == &"scrub"))
	Session.keep_intents = false
	Session.kept_intents.clear()
	platter.queue_free()


## The file the ear's cassette plays (slice 25): in my media folder only, named for this run's port.
func _ear_file() -> String:
	return "Probe Ear %d.wav" % _port


## A cassette at the ear (slice 25): an audio cassette of EAR_FILE, a file only my media folder has,
## minted and named in the room. Its clip names the file, so a guest may fetch it (FileSend._plays_here).
func _mint_an_ear_cassette() -> void:
	var path := ProjectSettings.globalize_path(AudioTake.DIR.path_join(_ear_file()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AudioTake.DIR))
	var tone := PackedFloat32Array()
	for n in int(EAR_SECONDS * 48000):
		tone.append(sin(n * 0.04) * 0.3)
	DawKitAudioFile.write_wav(path, tone, 1, 48000)
	var clip := {"start": 0.0, "length": EAR_SECONDS, "name": "Probe ear", "source": _ear_file()}
	var made := _room.mint(CassetteItem.KIND, {"clip": clip, "track": SENT_TRACK, "index": 0, "track_name": "EAR"})
	check("I mint an audio cassette of a file only I have (%s)" % _room.mint_refusal, made != null and FileAccess.file_exists(path))
	if made == null:
		return
	_ear_cassette = made.id
	Session.publish_made(made.id)
	var room: Dictionary = Session.room.duplicate(true)
	room["made"] = _room.made_ids()
	Session.publish_room(room)


## The guest's ear asked me for the file, once, and I sent it whole; then the cassette and file go.
func _check_ear_file_sent() -> void:
	check("the guest's ear fetched the file from me, once (%d sent)" % Session.files.fetches_served,
			Session.files.fetches_served == 1)
	if _ear_cassette != &"":
		_room.unmake(_ear_cassette)
		Session.drop_made(_ear_cassette)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioTake.DIR.path_join(_ear_file())))


## A cassette at the ear (slice 25): at 59.2 I hold the host's audio cassette to my ear (an EarCue, as
## the studio's), with no file of it here: FETCHING, and asked of the host once. By 59.32 the copy is
## in FETCHED, byte for byte the host's, and it plays on the keys' bus.
func _hear_a_cassette() -> void:
	await _until(59.2)
	_room.apply_made(Session.room.get("made", []))
	var tape: CassetteItem = null
	for id in _room.items:
		var c := _room.items[id] as CassetteItem
		if c != null and str(c.clip.get("source", "")) == _ear_file():
			tape = c
	check("the host's audio cassette is real here (%s)" % (tape.clip_name() if tape != null else "none"), tape != null)
	var ear := EarCue.new()
	add_child(ear)
	ear.hold(tape)
	check("held to my ear with no file of it here, it is FETCHING, asked once (%s, %d)" % [ear.tag(), Session.files.fetches_asked],
			ear.hearing == EarCue.Hearing.FETCHING and tape != null and tape.hearing == "FETCHING"
			and Session.files.fetches_asked == 1)
	await _until(59.32)
	var copy := Session.files.fetched_path(_ear_file())
	var theirs := ProjectSettings.globalize_path(AudioTake.DIR.path_join(_ear_file()))
	check("the host's file is in my FETCHED folder (%s)" % copy, not copy.is_empty() and copy.contains("fetched"))
	if FileAccess.file_exists(theirs):
		check("byte for byte the host's", FileAccess.get_file_as_bytes(copy) == FileAccess.get_file_as_bytes(theirs))
	check("and it plays at my ear, on the keys' bus (%s)" % ear.tag(), ear.hearing == EarCue.Hearing.PLAYING
			and ear.player.bus == AudioPorts.MONITOR)
	check("asked only once", Session.files.fetches_asked == 1)
	ear.hold(null)
	ear.queue_free()


## Clips as cassettes (slice 23): at 58.86 I pull PULL_TRACK's first clip, as the studio's pull asks;
## by 58.97 the host has minted it and handed me one of its own, and both are in my glove: their
## rows here, the holds mine, and the room naming them made real.
func _pull_a_cassette() -> void:
	await _until(58.86)
	var seq := Session.ask_room(&"make", [CassetteItem.KIND, PULL_FROM])
	check("my pull is asked of the host (seq %d)" % seq, seq > 0)
	await _until(58.97)
	_room.apply_made(Session.room.get("made", []))
	for id: StringName in [&"cassette1", &"cassette2"]:
		var item := _room.items.get(id) as CassetteItem
		check("%s's row reached me before the room named it (%s)" % [id, Session.made.keys()], Session.made.has(id))
		check("and it is real here, carrying its clip (%s)" % (item.clip_name() if item != null else "none"),
				item != null and not item.clip.is_empty() and item.length() > 0.0)
		check("in my glove: the host's table says so (%d)" % [Session.holder_of(item.network_key()) if item != null else -1],
				item != null and Session.holder_of(item.network_key()) == Session.local_peer_id)
	var pulled := _room.items.get(&"cassette1") as CassetteItem
	check("the one I pulled is the host's clip from track %d" % PULL_TRACK,
			pulled != null and pulled.from_track == PULL_TRACK and pulled.from_index == 0)


## A cassette onto a track (slice 24): at 58.99 I paste the cassette the host gave me (cassette2) onto
## PASTE_TRACK at PASTE_BAR, as the studio's press asks: its id, the track and the time, never the
## clip. By 59.08 the host's mix has given me the item there, the clip it was but for its start.
func _paste_a_cassette() -> void:
	await _until(58.99)
	var at := DAW.state.bar_to_seconds(PASTE_BAR)
	var cassette := _room.items.get(&"cassette2") as CassetteItem
	var seq := Session.ask_room(&"paste", [&"cassette2", PASTE_TRACK, at])
	check("my paste of the host's cassette is asked by its id, track and time (seq %d)" % seq, seq > 0 and cassette != null)
	await _until(59.08)
	if _reaper_host and cassette != null and cassette.clip.has("part"):
		check("on Reaper the host refused my demo part, and said why (%s)" % [_notices.slice(-3)],
				_notices.any(func(t): return str(t).contains("built-in engine")))
		return
	var it: MixState.ItemState = null
	for item: MixState.ItemState in DAW.state.track(PASTE_TRACK).items:
		if absf(item.start - at) < 0.001:
			it = item
	check("the host's mix gives me it on track %d at bar %d (%s)" % [PASTE_TRACK, int(PASTE_BAR), it.name if it != null else "none"],
			it != null and cassette != null and it.name == cassette.clip_name()
			and is_equal_approx(it.length, cassette.length()))
	check("and the host told me (%s)" % [_notices.slice(-2)], _notices.any(func(t): return str(t) == "Pasted."))


## Jacks of this half's own, as the studio keeps them: what comes down a cable plays this half's
## keys, and is kept, as is what it played there.
func _wear_jacks() -> void:
	_jacks = Jacks.new()
	add_child(_jacks)
	_jacks.keys = Session.guest_midi
	Session.jack_played.connect(_jacks.received)
	Session.jack_played.connect(func(source: StringName, kind: int, pitch: int, _v: int, from: int, song: float) -> void:
		_jacked.append([source, kind, pitch, from, song]))
	Session.guest_midi.note.connect(func(kind: int, pitch: int, _v: int, song: float, source: StringName) -> void:
		if source == Jacks.CABLE:
			_cabled.append([kind, pitch, song]))


## A clock to hear the song by (GuestMidi.heard_source): playing from `from_seconds` now, on.
func _given_clock(from_seconds: float, recording: bool) -> Callable:
	var t0 := Time.get_ticks_usec()
	return func() -> Dictionary:
		return {"seconds": from_seconds + (Time.get_ticks_usec() - t0) / 1e6, "playing": true,
				"recording": recording, "valid": true}


## Where the guest rings its bell: a quarter second past the host's D minor marker.
func _ring_song() -> float:
	for t in DAW.state.markers:
		if str(DAW.state.markers[t]) == HARP_KEY:
			return float(t) + 0.25
	return -1.0


## Host: the guest's chord hand, plugged into me (part two, slice 33), holding IV of D minor: my
## chord hand takes Gm from them, my harp's strings and crown are theirs, and a strum plays Gm's
## tones on my keys.
func _check_chord_into_me(chords: ChordHand, harp: ChordHarp) -> void:
	var source := Jack.chord_source(_other_id())
	var key := Harmony.at(DAW.state, DAW.state.position_seconds)
	var gm_tones := ChordHand.with_chord(key, "Gm").tones(ChordHarp.LOWEST, ChordHarp.STRINGS)
	check("the guest's chord hand is plugged into me (%s)" % [_jacks.patch],
			_jacks.sink_of(source) == Jack.player_sink(1))
	check("and its chord came down the jack: IV of D minor, Gm, from the guest (%s from %d)"
			% [chords.their_chord(key), chords.their_player()],
			chords.their_chord(key) == "Gm" and chords.their_player() == _other_id() and chords.plays_theirs())
	harp._process(0.016)
	check("my harp's strings are Gm's, and its crown says whose (%s, %s)" % [harp.tuning(), harp._chord_label.text],
			harp.tuning() == gm_tones and harp._chord_label.text == "iv from %s" % Session.name_of(_other_id()).to_upper())
	var ons: Array = []
	var heard := func(kind: int, pitch: int, _v: int, _song: float, from: StringName) -> void:
		if kind == Session.Note.ON and from == ChordHarp.SOURCE:
			ons.append(pitch)
	Session.guest_midi.note.connect(heard)
	_strum(harp)
	Session.guest_midi.note.disconnect(heard)
	check("and my strum plays Gm's tones on my keys (%s)" % [ons], ons == Array(gm_tones))
	harp._physics_process(ChordHarp.RING + 0.01)


## Guest: my chord hand's jack into the host at 60.62, as P in the chord layer asks it; IV held at
## 60.66, sent down it as Jacks.send_chord does each frame; unplugged at 60.74.
func _drive_their_harp() -> void:
	await _until(60.62)
	var chords := ChordHand.new()
	add_child(chords)
	var mine := Jack.chord_source(Session.local_peer_id)
	Session.ask_room(&"plug", [mine, Jack.player_sink(1)])
	await _until(60.66)
	check("the host's room has my chord hand into the host (%s)" % [_jacks.patch], _jacks.sink_of(mine) == Jack.player_sink(1))
	chords.pick(3)
	var key := Harmony.at(DAW.state, chords.now())
	check("I hold IV, which in D minor is Gm (%s)" % chords.own_chord(chords.now()),
			chords.own_chord(chords.now()) == "Gm" and ChordHand.numeral_of(key, 3) == "iv")
	await _until(60.74)
	Session.ask_room(&"plug", [mine, &""])
	await _until(60.78)
	check("and unplugged it (%s)" % [_jacks.patch], _jacks.sink_of(mine) == &"")
	chords.queue_free()


## Guest: from 60.82 my ruler point at POINT_AT on the presence stream, as Presence.pointing_of says a
## time on the ruler, and a sticky note at NOTE_AT, as PointAndMark.add_note makes one: an add_marker
## intent. I stop pointing at 60.94.
func _point_and_note() -> void:
	await _until(60.82)
	_pointing = Presence.RULER_KEY + ("%.3f" % POINT_AT)
	_pointing_local = Vector3.ZERO
	check("my sticky note is asked as a marker", PointAndMark.add_note(NOTE_AT, NOTE_WORDS))
	await _until(60.94)
	_pointing = ""


## Host: the guest's point, heard on the presence stream as the song time it means, and its note in
## my markers (slice 35).
func _check_point_and_note() -> void:
	var guest: Session.Participant = Session.participants.get(_other_id())
	var said := guest.pointing_at if guest != null else ""
	check("the guest's ruler point arrived as the time it means (%s)" % said, said.begins_with(Presence.RULER_KEY)
			and absf(said.trim_prefix(Presence.RULER_KEY).to_float() - POINT_AT) < 0.001)
	var at := DAWBackend.marker_key(DAW.state.markers, NOTE_AT)
	check("and its sticky note is in my markers (%s)" % [DAW.state.markers.get(at, "-") if not is_nan(at) else "-"],
			not is_nan(at) and str(DAW.state.markers[at]) == Harmony.note_named(NOTE_WORDS))


## The host's measure for the probe's spectra (slice 36): the kick's and the bass's bands, the rest
## of every track silent.
static func _probe_spectrum(track: int) -> PackedFloat32Array:
	var out := Spectra.silent()
	for spec in [[SPECTRA_KICK, SPECTRA_KICK_BANDS, SPECTRA_KICK_DB], [SPECTRA_BASS, SPECTRA_BASS_BANDS, SPECTRA_BASS_DB]]:
		if track == spec[0]:
			for i in range(spec[1][0], spec[1][1] + 1):
				out[i] = spec[2]
	return out


## Guest: by 61.1 the host's spectra are mine, as the wall reads them (a Spectra of my own, as the
## studio stands one): the kick's and the bass's bands within a byte's half step, and the two found
## clashing over the bands they share.
func _hear_the_spectra() -> void:
	await _until(61.1)
	var mine := Spectra.new()
	add_child(mine)
	var shown := mine.latest()
	var step := (Spectra.TOP_DB - Spectra.FLOOR_DB) / 255.0
	var near := func(track: int, band: int, db: float) -> bool:
		return shown.has(track) and absf((shown[track] as PackedFloat32Array)[band] - db) <= step * 0.5 + 0.001
	check("the host's spectra reached me (%d tracks, %s)" % [shown.size(), mine.reason()],
			mine.reason() == "" and near.call(SPECTRA_KICK, 5, SPECTRA_KICK_DB) and near.call(SPECTRA_BASS, 5, SPECTRA_BASS_DB)
			and near.call(SPECTRA_KICK, 0, Spectra.FLOOR_DB) and near.call(SPECTRA_BASS, 8, SPECTRA_BASS_DB))
	var clashes := Spectra.clashes(shown)
	check("and the kick and the bass clash where they meet (%s)" % [clashes],
			clashes.size() == 1 and clashes[0]["a"] == SPECTRA_KICK and clashes[0]["b"] == SPECTRA_BASS
			and clashes[0]["from"] == SPECTRA_BASS_BANDS[0] and clashes[0]["to"] == SPECTRA_KICK_BANDS[1])
	mine.queue_free()


## Guest: from 61.14 my own EQ wall over the probe's kick and bass, their glow clicked without a push
## (which asks for nothing), then grabbed on the bass's side and dragged CARVE_SHARE of a full push down, held until 61.22 so the host's EQ comes back to
## me while the push is still one edit; by 61.24 the host's mix gives the carve back to me.
func _carve_the_clash() -> void:
	await _until(61.14)
	var given := {SPECTRA_KICK: _probe_spectrum(SPECTRA_KICK), SPECTRA_BASS: _probe_spectrum(SPECTRA_BASS)}
	var wall := EqWall.new()
	wall.name = "CarveWall"
	wall.spectra = func() -> Dictionary: return given
	wall.reference = func() -> float: return 0.0
	add_child(wall)
	wall._process(0.0)
	var glow: EqWall.Clash = wall.glows[0] if not wall.glows.is_empty() else null
	check("my wall lights the kick's and the bass's clash, the bass on its right (%s)" % [glow.clash if glow != null else {}],
			glow != null and glow.visible and glow.right_track() == SPECTRA_BASS and EqCarve.choice() != "")
	if glow == null or not glow.visible:
		wall.queue_free()
		return
	var hand := Node.new()
	add_child(hand)
	var mid := (EqWall.y_of_hz(Spectra.edges(glow.clash["from"]).x) + EqWall.y_of_hz(Spectra.edges(glow.clash["to"]).y)) * 0.5
	var at := Vector3(EqWall.middle_x() + 0.05, mid, 0.022)
	# A click first, as a desk does to see what a glow does: no push, so nothing asked for, and the
	# host's chain has only the push's EQ after (_check_carve), not a flat one of the click's too.
	glow.grab_begin(hand, wall.to_global(at))
	glow.grab_end(hand)
	check("a click on the glow with no push asks for no EQ", glow.push.is_empty() and not EqWall.Clash.asked_for(SPECTRA_BASS))
	glow.grab_begin(hand, wall.to_global(at))
	glow.grab_move(hand, wall.to_global(at - Vector3(0, EqCarve.PUSH_FULL * CARVE_SHARE, 0)))
	check("my push is on the bass (%s)" % glow.readout(), not glow.push.is_empty() and int(glow.push["track"]) == SPECTRA_BASS)
	await _until(61.22)
	glow.grab_end(hand)
	await _until(61.24)
	var fx := EqCarve.carver_on(SPECTRA_BASS)
	check("the host's mix gives my carve back to me: an EQ on the bass (%s)" % [DAW.state.fx(SPECTRA_BASS, fx).name if fx >= 0 else "none"],
			fx >= 0)
	if fx >= 0 and EqCarve.engine() == &"built_in":
		var f := DAW.state.fx(SPECTRA_BASS, fx)
		var bands := EqCarve.bands_for(SPECTRA_BASS_BANDS[0], SPECTRA_KICK_BANDS[1])
		var cut := bands.map(func(b: int) -> float: return EqCarve.eq21_db(float(f.params.get(b, 0.5))))
		check("its bands in the clash cut %.0f dB (%s)" % [CARVE_DB, cut], cut.all(func(db: float) -> bool: return absf(db - CARVE_DB) < 0.05))
	hand.queue_free()
	wall.queue_free()


## Host: the guest's carve (slice 37), as my DAW has it: an EQ at the end of the bass's chain, on the
## built-in engine its bands in the clash at CARVE_DB, as one step named for the carve, which one
## undo takes back. On Reaper the ReaEQ is taken away by hand; its band waits on its parameters'
## names, which the stand-in does not have, so only the built-in engine's cut is checked.
func _check_carve(chain_was: int, depth_was: int) -> void:
	var t := DAW.state.track(SPECTRA_BASS)
	var fx := EqCarve.carver_on(SPECTRA_BASS)
	check("the guest's push is an EQ at the end of my track %d's chain (%s, %s from %d)" % [SPECTRA_BASS, DAW.state.fx(SPECTRA_BASS, fx).name if fx >= 0 else "none", t.plugins(), chain_was],
			fx >= 0 and t.plugins().size() == chain_was + 1 and t.plugins()[-1] == fx)
	var from: int = SPECTRA_BASS_BANDS[0]
	var to: int = SPECTRA_KICK_BANDS[1]
	if fx >= 0 and EqCarve.engine() == &"built_in":
		var f := DAW.state.fx(SPECTRA_BASS, fx)
		var bands := EqCarve.bands_for(from, to)
		var cut := bands.map(func(b: int) -> float: return EqCarve.eq21_db(float(f.params.get(b, 0.5))))
		var flat := range(21).filter(func(b: int) -> bool: return not bands.has(b)) \
				.all(func(b: int) -> bool: return is_equal_approx(EqCarve.eq21_db(float(f.params.get(b, 0.5))), 0.0))
		check("its bands in the clash cut %.0f dB, the rest flat (%s, %s)" % [CARVE_DB, EqCarve.bands_words(bands), cut],
				cut.all(func(db: float) -> bool: return absf(db - CARVE_DB) < 0.05) and flat)
		var engine := DAW.backend as GodotBackend
		if engine != null:
			var effect := AudioServer.get_bus_effect(engine._bus[SPECTRA_BASS], 1 + fx) as AudioEffectEQ21
			check("an EQ21 on the bass's bus, cut there too", effect != null and absf(effect.get_band_gain_db(bands[0]) - CARVE_DB) < 0.05)
	if _reaper_resource == "":
		var last: String = str(DAW.state.undo_names[DAW.state.undo_depth - 1]) if DAW.state.undo_depth > 0 else ""
		var named := "%s: carve %s" % [t.display_name(), Spectra.span_words(from, to)]
		check("as one step, called the carve (%s, %d after %d: %s)" % [last, DAW.state.undo_depth, depth_was, DAW.state.undo_names.slice(maxi(depth_was - 2, 0), DAW.state.undo_depth)], DAW.state.undo_depth == depth_was + 1 and last == named)
		DAW.undo()
		check("which one undo takes back whole", EqCarve.carver_on(SPECTRA_BASS) == -1 and t.plugins().size() == chain_was)
	elif fx >= 0:
		DAW.remove_fx(SPECTRA_BASS, fx)


## Guest: the test drum stood at DRUM_HOME by 61.28, as the host stands its own, and at 61.3 my
## fingertip down through its rim at DRUM_SPEED, as Strike reads a tracked hand, to DRUM_SONG: the
## slap, sent to the host as a hit by my room's `played` (Session.send_item_hit, with its zone).
func _strike_the_drum() -> void:
	await _until(61.28)
	var drum := _room.spawn(&"testdrum", &"testdrum", DRUM_HOME) as TestDrumItem
	var strike := Strike.new()
	strike.set_physics_process(false)
	add_child(strike)
	await _until(61.3)
	var clock := InstrumentItem.clock
	InstrumentItem.clock = func() -> float: return DRUM_SONG
	var face: Dictionary = drum.faces()[0]
	var rim: Vector3 = (face["frame"] as Transform3D).origin + Vector3(TestDrumItem.HEAD_RADIUS * 0.9, 0, 0)
	var dt := 1.0 / 90.0
	for i in 6:
		strike.step({[&"probe", 0]: rim + Vector3.UP * (0.05 - i * DRUM_SPEED * dt)}, dt)
	InstrumentItem.clock = clock
	check("my fingertip through the test drum's rim plays its slap (%s)" % drum.last_zone,
			drum.last_zone == &"slap" and drum.state == Item.State.HOME)
	# The djembe (slice 40), which my room has had put away since it was made: stood as the host
	# stands its own, and slapped at its rim at 61.32.
	_room.stand(&"djembe", DJEMBE_HOME)
	var djembe := _room.items.get(&"djembe") as HandDrum
	await _until(61.32)
	InstrumentItem.clock = func() -> float: return DJEMBE_SONG
	var head: Vector3 = (djembe.faces()[0]["frame"] as Transform3D).origin + Vector3(djembe.head_radius() * 0.92, 0, 0)
	for i in 6:
		strike.step({[&"probe", 1]: head + Vector3.UP * (0.05 - i * DRUM_SPEED * dt)}, dt)
	InstrumentItem.clock = clock
	check("my fingertip through the djembe's rim plays its slap (%s)" % djembe.last_zone,
			_room.stands(&"djembe") and djembe.last_zone == &"slap" and djembe.state == Item.State.HOME)
	# Drum pads on anything (slice 41): a pad of my own marked on a surface by a fingertip's dwell, the
	# kit's face, and struck at once, to PAD_SONG.
	var kit := _room.items.get(KitItem.KIND) as KitItem
	_room.stand(KitItem.KIND, KIT_HOME)
	var pads := SurfacePads.new()
	pads.path = PAD_FILE
	pads.hands = true
	pads.set_physics_process(false)
	add_child(pads)
	pads.clear()
	kit.surface = pads
	pads.set_marking(true)
	for i in 10:
		pads.dwell({[&"probe", 2]: PAD_AT + Vector3.UP * (0.05 - i * 0.005)}, dt)
	for i in ceili(SurfacePads.DWELL / dt) + 2:
		pads.dwell({[&"probe", 2]: PAD_AT}, dt)
	pads.set_marking(false)
	InstrumentItem.clock = func() -> float: return PAD_SONG
	var pad: Vector3 = (pads.pad_frame(0).origin if pads.pads.size() == 1 else PAD_AT)
	for i in 6:
		strike.step({[&"probe", 3]: pad + Vector3.UP * (0.05 - i * DRUM_SPEED * dt)}, dt)
	InstrumentItem.clock = clock
	check("my fingertip's dwell marks a pad, and coming down through it plays the kit's kick (%s)" % kit.last_zone,
			pads.pads.size() == 1 and kit.last_zone == &"kick" and kit.state == Item.State.HOME)
	pads.clear()
	kit.surface = null
	pads.queue_free()
	# The rooftop's railing (slice 42), stood as the host stands its own: my fingertip into the third
	# tuned baluster's front, toward the parapet, to RAILING_SONG.
	var spec := _stand_the_railing()
	var baluster := _room.items.get(VenueInstrument.bar_id(RAILING_BAR)) as VenueInstrument.Bar
	InstrumentItem.clock = func() -> float: return RAILING_SONG
	var middle: Vector3 = (spec["spot"] as Transform3D) * (VenueInstrument.bar_frame(spec, RAILING_BAR).origin
			+ Vector3(0, VenueInstrument.bar_length(spec, RAILING_BAR) * 0.5, 0))
	for i in 6:
		strike.step({[&"probe", 4]: middle + Vector3.BACK * (0.05 - i * DRUM_SPEED * dt)}, dt)
	InstrumentItem.clock = clock
	var tone := VenueInstrument.scale_tone(Harmony.at(DAW.state, RAILING_SONG), int(spec["low"]), RAILING_BAR)
	check("my fingertip into the railing's third baluster rings its scale tone (%d, %d)" % [baluster.last_note, tone],
			_room.stands(baluster.id) and baluster.last_note == tone and baluster.state == Item.State.HOME)
	strike.queue_free()


## Host: the guest's strike on the test drum (slice 38) reached me from the guest with its zone and
## the song position it was played to, and, as Presence plays a bandmate's strike, my drum rings it
## where it stands: nobody holds it.
func _check_drum_strike() -> void:
	var hits := _item_hits.filter(func(h: Array) -> bool: return h[0] == &"testdrum")
	check("the guest's strike on the test drum reached me with its zone and song (%s)" % [hits],
			hits.size() == 1 and hits[0][2] == _other_id() and hits[0][6] == &"slap"
			and is_equal_approx(float(hits[0][3]), DRUM_SONG) and int(hits[0][1]) == InstrumentItem.velocity_for(DRUM_SPEED))
	var drum := _room.items.get(&"testdrum") as TestDrumItem
	if hits.size() != 1 or drum == null:
		return
	var presence := Presence.new()
	presence.items = _room
	var was := drum._take
	var hit: Array = hits[0]
	presence._on_item_hit(hit[0], hit[1], hit[2], hit[3], hit[4], hit[5], hit[6])
	check("and my drum plays it where it stands, on the slap, held by nobody",
			drum._take == was + 1 and drum.last_zone == &"slap" and drum.state == Item.State.HOME
			and Session.holder_of(drum.network_key()) == 0)
	presence.free()


## Host: the guest's slap on the djembe (slice 40) reached me from the guest with its zone and song,
## and my djembe, which stands where the guest's does, rings it there on its slap, held by nobody.
func _check_djembe_slap() -> void:
	var hits := _item_hits.filter(func(h: Array) -> bool: return h[0] == &"djembe")
	check("the guest's slap on the djembe reached me with its zone and song (%s)" % [hits],
			hits.size() == 1 and hits[0][2] == _other_id() and hits[0][6] == &"slap"
			and is_equal_approx(float(hits[0][3]), DJEMBE_SONG) and int(hits[0][1]) == InstrumentItem.velocity_for(DRUM_SPEED))
	var djembe := _room.items.get(&"djembe") as HandDrum
	if hits.size() != 1 or djembe == null:
		return
	var presence := Presence.new()
	presence.items = _room
	var was := djembe._take
	var hit: Array = hits[0]
	presence._on_item_hit(hit[0], hit[1], hit[2], hit[3], hit[4], hit[5], hit[6])
	check("and my djembe plays it where it stands, its slap's sound, held by nobody",
			_room.stands(&"djembe") and djembe._take == was + 1 and djembe.last_zone == &"slap"
			and djembe.kind_of_hit(true, djembe.last_zone) == &"djembe_slap" and Session.holder_of(djembe.network_key()) == 0)
	presence.free()


## The rooftop's railing (slice 42), as the studio stands it there: the room's venue bars dressed as
## its set and stood on its spot. Answers the set.
func _stand_the_railing() -> Dictionary:
	var rooftop := RooftopVenue.new()
	var spec := VenueInstrument.filled(rooftop.instrument())
	rooftop.free()
	VenueInstrument.dress(_room, spec)
	for id: StringName in VenueInstrument.homes(spec):
		_room.stand(id, VenueInstrument.homes(spec)[id])
	return spec


## The loft's Thunderstorm (slice 44), as the studio stands it in the loft's storm, and what it
## schedules over WEATHER_BAR of this half's song: [step, note, velocity] for each drop, in order.
func _weather_schedule() -> Array:
	var loft := Venue.make(&"loft", LoftVenue.STORM)
	var spec := Weather.spec_of(loft)
	var venue_seed := Weather.seed_of(loft.venue_id())
	loft.free()
	var out: Array = []
	if spec.is_empty():
		return out
	var from := DAW.state.bar_to_seconds(WEATHER_BAR)
	for drop: Dictionary in Weather.drops(spec, venue_seed, DAW.state, from, DAW.state.bar_to_seconds(WEATHER_BAR + 1.0)):
		out.append([int(drop["step"]), int(drop["note"]), int(drop["velocity"])])
	return out


## Host: my schedule of the Thunderstorm's bar (slice 44) in my room for the guest to set its own
## beside, and the switch OFF, as a room starts.
func _publish_the_weather() -> void:
	var room: Dictionary = Session.room.duplicate(true)
	room["weather_probe"] = _weather_schedule()
	room[Weather.VERB] = false
	Session.publish_room(room)
	check("my Thunderstorm schedules drops over its gusting bar (%d)" % (room["weather_probe"] as Array).size(),
			not (room["weather_probe"] as Array).is_empty())


## The host's answer to the guest's press on the weather's switch (slice 44), as the studio's: the
## room's row `weather`, LISTEN or OFF, published.
func _answer_weather(args: Array, _from: int) -> void:
	var room: Dictionary = Session.room.duplicate(true)
	room[Weather.VERB] = bool(args[0])
	Session.publish_room(room)


## The host's answer to the guest's slap on the looper (slice 45), as the studio's (Looper.answer): the
## room's row `looper` [player, from bar, bars], published. What the answer did to my transport and
## loop is kept first, to be put back when the probe is done with it.
var _looper_was: Dictionary = {}
var _looper_layers: Array = []


func _answer_looper(args: Array, from: int) -> void:
	if _looper_was.is_empty():
		var s := DAW.state
		_looper_was = {"playing": s.playing, "at": s.position_seconds, "looping": s.looping,
				"loop": [s.loop_start, s.loop_end]}
	var out := Looper.answer(Session.room.get(Looper.VERB, []), int(args[0]), int(args[1]), from, Session.name_of)
	var room: Dictionary = Session.room.duplicate(true)
	room[Looper.VERB] = out["row"]
	Session.publish_room(room)


## The host's answer to the guest's layer (slice 45), as the studio's: written onto a track of the
## guest's own (Looper.write_layer) while the row is theirs, and the row cleared.
func _answer_looper_layer(args: Array, from: int) -> void:
	var row: Array = Session.room.get(Looper.VERB, [])
	if row.is_empty() or int(row[0]) != from:
		return
	_looper_layers.append(Looper.write_layer(Session.name_of(from), float(args[0]), float(args[1]), args[2]))
	var room: Dictionary = Session.room.duplicate(true)
	room[Looper.VERB] = []
	Session.publish_room(room)


## Host: the guest's slap asked me for the looper and was given the next bar, not the far one it
## named; its layer is on "<GUEST> LOOP 1" in the LOOPER folder, its key and its hit over the span
## the row gave it; and the row is clear. On Reaper with more of the project than the bank, the
## tracks are made but not yet in my mirror when write_layer looks them up (see docs/spatial_loop.md).
func _check_looper_layer() -> void:
	var asks := _room_asks.filter(func(a: Array) -> bool: return a[0] == Looper.VERB)
	var layers := _room_asks.filter(func(a: Array) -> bool: return a[0] == Looper.LAYER_VERB)
	check("the guest's slap on the looper reached me (%s)" % [asks],
			asks.size() == 1 and asks[0][1] == [LOOPER_ASKED_BAR, LOOPER_BARS] and asks[0][2] == _other_id())
	check("and its layer (%d)" % layers.size(), layers.size() == 1 and layers[0][2] == _other_id())
	var named := Looper.layer_name(Session.name_of(_other_id()), 1)
	var index := Looper.track_named(DAW.state, named)
	var folder := Looper.folder_of(DAW.state)
	check("which is on a track of its own, %s, in the LOOPER folder (track %d, folder %d)" % [named, index, folder],
			index > 0 and folder > 0 and index > folder and Looper.folder_end(DAW.state, folder) >= index)
	var t := DAW.state.tracks.get(index) as MixState.TrackState
	var notes: Array = []
	if t != null and t.items.size() == 1:
		notes = MidiTake.unpack_relative(t.items[0].notes, t.items[0].start)
	var span: Array = [layers[0][1][0], layers[0][1][1]] if layers.size() == 1 else []
	check("its key and its hit, one item over the %d bars it was given (%s)" % [LOOPER_BARS, notes],
			notes.size() == LOOPER_NOTES.size() and not span.is_empty()
			and is_equal_approx(t.items[0].start, float(span[0]))
			and is_equal_approx(t.items[0].start + t.items[0].length, float(span[1]))
			and notes.map(func(n: Array) -> int: return int(n[2])) == [60, 38])
	check("and my room's looper row is clear", (Session.room.get(Looper.VERB, [0]) as Array).is_empty())


## Host: the guest's pull on its layer's ring (slice 46) took "<GUEST> LOOP 1" out of my project and
## left the LOOPER folder; on the built-in engine as one step, named for the ring (the edit the guest
## opened round its grab). On Reaper the mute is an OSC write, an undo point of Reaper's own.
func _check_ring_pulled() -> void:
	var named := Looper.layer_name(Session.name_of(_other_id()), 1)
	var index := Looper.track_named(DAW.state, named)
	check("the guest's pull on its looper ring deleted %s from my project (track %d), the LOOPER folder left (%d)" % [named, index, Looper.folder_of(DAW.state)],
			index == 0 and Looper.folder_of(DAW.state) > 0)
	if _reaper_resource == "":
		var last: String = str(DAW.state.undo_names[DAW.state.undo_depth - 1]) if DAW.state.undo_depth > 0 else ""
		check("as one step, named for the ring (%s)" % last, last == "%s: ring" % named)


## Host: the guest's layer and the LOOPER folder taken out again, last first, and my transport and
## loop as they were before its slap.
func _take_back_the_looper() -> void:
	for at in [Looper.track_named(DAW.state, Looper.layer_name(Session.name_of(_other_id()), 1)),
			Looper.folder_of(DAW.state)]:
		if at > 0:
			DAW.remove_track(at)
	if _looper_was.is_empty():
		return
	DAW.set_loop_range(_looper_was["loop"][0], _looper_was["loop"][1])
	DAW.set_looping(_looper_was["looping"])
	if not _looper_was["playing"]:
		DAW.transport_stop()
	DAW.seek(_looper_was["at"])


## Guest: the looper slapped (slice 45), asking for a far bar; by 61.68 the host's row gives me the
## next bar instead, LOOPER_BARS of it; my layer over that span sent; by 61.82 my mirror of the host's
## mix has it on a track of my own in the LOOPER folder. At 61.84 I pull its ring off (slice 46), and by
## 61.98 my mirror no longer has it.
func _loop_a_layer() -> void:
	await _until(61.6)
	var seq := Session.ask_room(Looper.VERB, [LOOPER_ASKED_BAR, LOOPER_BARS])
	check("my slap on the looper is asked of the host (seq %d)" % seq, seq > 0)
	await _until(61.68)
	var row: Array = Session.room.get(Looper.VERB, [])
	var span := Looper.span_of(row, DAW.state)
	check("and the host's row gives me the looper, %d bars from a bar of its choosing (%s)" % [LOOPER_BARS, row],
			row.size() == 3 and int(row[0]) == Session.local_peer_id and int(row[1]) != LOOPER_ASKED_BAR
			and int(row[2]) == LOOPER_BARS and not span.is_empty())
	if span.is_empty():
		return
	var notes: Array = []
	for n: Array in LOOPER_NOTES:
		notes.append([span[0] + n[0], span[0] + n[1], n[2], n[3], n[4]])
	Session.ask_room(Looper.LAYER_VERB, [float(span[0]), float(span[1]), notes])
	await _until(61.82)
	var named := Looper.layer_name(Session.name_of(Session.local_peer_id), 1)
	var index := Looper.track_named(DAW.state, named)
	var folder := Looper.folder_of(DAW.state)
	check("and my copy of the host's mix has %s in its LOOPER folder (track %d, folder %d)" % [named, index, folder],
			index > folder and folder > 0 and Looper.folder_end(DAW.state, folder) >= index)
	check("and the room's looper row is clear again", (Session.room.get(Looper.VERB, [0]) as Array).is_empty())
	# Its ring (slice 46): a stand of my own from my mirror, a hand closed on the layer's ring and pulled
	# 0.5 m off it, then opened.
	await _until(61.84)
	var rings := LooperRings.new()
	add_child(rings)
	rings.set_physics_process(false)
	rings.set_process(false)
	rings.refresh()
	var ring := rings.ring_named(named)
	check("my stand has %s's ring, from my mirror of the host's LOOPER folder (%d rings)" % [named, rings.rings.size()], ring != null)
	if ring != null:
		var at := rings.global_transform * (LooperRings.rest_of(ring.slot) + Vector3(0, 0, LooperRings.RADIUS))
		rings.step_hands([{"hand": &"probe", "at": at, "closed": true}], 1.0 / 60.0)
		rings.step_hands([{"hand": &"probe", "at": at + Vector3(0, 0, 0.5), "closed": true}], 1.0 / 60.0)
		rings.step_hands([{"hand": &"probe", "at": at + Vector3(0, 0, 0.5), "closed": false}], 1.0 / 60.0)
		check("and my pull takes it off my stand at once, asked of the host", rings.ring_named(named) == null)
	await _until(61.98)
	check("by 61.98 my copy of the host's mix no longer has %s" % named, Looper.track_named(DAW.state, named) == 0)
	rings.queue_free()


## A music box hearing the song at MUSIC_BOX_SONG, stood still: what either half's reads its pegs by.
func _probe_music_box() -> MusicBox:
	var box := MusicBox.new()
	box.heard_source = func() -> Dictionary: return {"seconds": MUSIC_BOX_SONG, "playing": false, "valid": true}
	add_child(box)
	return box


## Where MUSIC_BOX_CELL's note is in `state`: the MUSIC BOX track, the bar's span, the row's pitch in
## the song's key there, and the step's time.
func _music_box_note(state: MixState) -> Dictionary:
	var span := MusicBox.span_of(state, 1, MUSIC_BOX_SONG)
	var rows := MusicBox.rows_of(MusicBox.key_of(state, span), MusicBox.DEFAULT_ROW)
	return {"track": MusicBox.named_track(state), "span": span, "pitch": rows[MUSIC_BOX_CELL.x],
			"on": MusicBox.step_time(state, span, MUSIC_BOX_CELL.y)}


## Whether `state`'s MUSIC BOX track has one item over the box's bar, its one note MUSIC_BOX_CELL's.
func _has_music_box_peg(state: MixState) -> bool:
	var want := _music_box_note(state)
	var t := state.tracks.get(int(want["track"])) as MixState.TrackState
	if t == null or t.items.size() != 1:
		return false
	var it := t.items[0] as MixState.ItemState
	var notes := MidiTake.unpack_relative(it.notes, it.start)
	return notes.size() == 1 and int(notes[0][2]) == int(want["pitch"]) \
			and absf(float(notes[0][0]) - float(want["on"])) < TAKE_TOLERANCE \
			and absf(it.start - (want["span"] as Vector2).x) < TAKE_TOLERANCE


## Host: the guest's peg on its music box (slice 47) is a note in my MUSIC BOX track's item, at its
## row's pitch and its step's time; on the built-in engine one step named for the pegs; and a box of
## my own reads it back as that peg.
func _check_music_box_peg() -> void:
	var want := _music_box_note(DAW.state)
	var t := DAW.state.tracks.get(int(want["track"])) as MixState.TrackState
	check("the guest's peg on its music box is a note in my MUSIC BOX track's item (track %d, pitch %d at %.3fs: %s)" % [
			want["track"], want["pitch"], want["on"], str(t.items[0].notes) if t != null and t.items.size() > 0 else "none"],
			int(want["track"]) > 0 and _has_music_box_peg(DAW.state))
	if _reaper_resource == "":
		var last: String = str(DAW.state.undo_names[DAW.state.undo_depth - 1]) if DAW.state.undo_depth > 0 else ""
		check("the track and its item, one step named for the pegs (%s)" % last, last == "%s: pegs" % MusicBox.TRACK_NAME)
	# Stood still at the song's place, as its first frame would show it: the bar it reads is the one
	# the guest's box was showing.
	var box := _probe_music_box()
	box.set_process(false)
	box.show_at(MUSIC_BOX_SONG, 0.0)
	check("and a music box of my own reads it back as the guest's peg (%s)" % [box.pegs().keys()],
			box.pegs().keys() == [MUSIC_BOX_CELL])
	box.queue_free()


## Host: the MUSIC BOX track taken out again.
func _take_back_the_music_box() -> void:
	var track := MusicBox.named_track(DAW.state)
	if track > 0:
		DAW.remove_track(track)


## Guest: a peg pressed on a music box of my own (slice 47) at 62.02, shown at once and asked of the
## host as the MUSIC BOX track and its item; by 62.18 my mirror of the host's mix has it as the note.
func _press_the_music_box() -> void:
	await _until(62.02)
	var box := _probe_music_box()
	var had := MusicBox.named_track(DAW.state)
	box.press(MUSIC_BOX_CELL)
	check("my press on my music box shows its peg at once, the MUSIC BOX track asked of the host (had %d)" % had,
			box.has_peg(MUSIC_BOX_CELL) and had == 0)
	await _until(62.18)
	check("by 62.18 my copy of the host's mix has my peg as the note in its MUSIC BOX item, and my box still shows it",
			_has_music_box_peg(DAW.state) and box.has_peg(MUSIC_BOX_CELL) and box.peg_count() == 1)
	box.queue_free()


## Host: the guest's string tied (slice 48), answered as the studio answers it (RoomString.answer): the
## room's row `strings` with it, published, or the refusal told to the guest.
func _answer_string(args: Array, from: int) -> void:
	var rows: Dictionary = (Session.room.get(RoomString.ROW, {}) as Dictionary).duplicate()
	var refusal := RoomString.answer(rows, args[0], args[1], args[2], from)
	if refusal != "":
		Session.tell(from, refusal)
		return
	var room: Dictionary = Session.room.duplicate(true)
	room[RoomString.ROW] = rows
	Session.publish_room(room)


## Host: the guest's string (slice 48) is in my room's row, at its ends, with the guest as its maker.
func _check_string_tied() -> void:
	var asks := _room_asks.filter(func(a: Array) -> bool: return a[0] == RoomString.VERB)
	var row: Variant = (Session.room.get(RoomString.ROW, {}) as Dictionary).get(STRING_ID)
	check("the guest's string reached me as the room's ask (%s)" % [asks],
			asks.size() == 1 and asks[0][2] == _other_id())
	check("and is in my room's strings, at its ends, the guest its maker (%s)" % [row],
			row is Array and (row[0] as Vector3).is_equal_approx(STRING_A) and (row[1] as Vector3).is_equal_approx(STRING_B)
			and int(row[2]) == _other_id())


## Host: the guest's pluck on its string (slice 48) heard here with the string's source, and in the
## take it sent me: one note on TAKE_TRACK at STRING_SONG, the string's note in my song's key there.
func _check_string_take() -> void:
	var want := RoomString.pitch_in(STRING_A.distance_to(STRING_B), Harmony.at(DAW.state, STRING_SONG))
	var heard := _sourced.filter(func(n: Array) -> bool: return n[3] == RoomString.SOURCE and n[0] == Session.Note.ON)
	check("the guest's pluck reached me as a note from its string (%s, wanted %d)" % [heard, want],
			heard.size() == 1 and int(heard[0][1]) == want and int(heard[0][2]) == _other_id())
	var takes: Array = DAW.state.track(TAKE_TRACK).items.filter(func(it: MixState.ItemState) -> bool:
			return it.start > STRING_SONG - 0.1 and it.start < STRING_SONG + 1.0)
	check("and its take is an item on track %d (%d)" % [TAKE_TRACK, takes.size()], takes.size() == 1)
	if takes.size() != 1:
		return
	var item: MixState.ItemState = takes[0]
	var notes := MidiTake.unpack_relative(item.notes, item.start)
	check("named for the string, with its one note (%s, %s)" % [item.name, notes],
			item.name.contains("string") and notes.size() == 1 and int(notes[0][2]) == want)


## Guest: a string tied (slice 48) at 62.3, asked of the host; by 62.36 my mirror of the room has it,
## and I pluck a string of my own at its ends onto TAKE_TRACK, my clock at STRING_SONG, sent when the
## clock stops at 62.42.
func _tie_and_pluck_a_string() -> void:
	await _until(62.3)
	var seq := Session.ask_room(RoomString.VERB, [STRING_ID, STRING_A, STRING_B])
	check("my string is asked of the host (seq %d)" % seq, seq > 0)
	await _until(62.36)
	var row: Variant = (Session.room.get(RoomString.ROW, {}) as Dictionary).get(STRING_ID)
	check("and by 62.36 the room's strings have it, mine (%s)" % [row],
			row is Array and int(row[2]) == Session.local_peer_id)
	var gm := Session.guest_midi
	gm.reach(RoomString.SOURCE, true)
	gm.target_track = TAKE_TRACK
	gm.heard_source = _given_clock(STRING_SONG, true)
	var string := RoomString.new()
	string.id = STRING_ID
	string.a = STRING_A
	string.b = STRING_B
	string.tips = func() -> Dictionary: return {}
	add_child(string)
	# The keys begin their take as they next hear the clock recording (GuestMidi.follow, a frame on).
	await get_tree().process_frame
	await get_tree().process_frame
	string.pluck(RoomString.PLUCK_VELOCITY)
	check("my pluck is in a take of my own", gm.is_recording() and gm.held.has(string.pitch()))
	await _until(62.4)
	string.silence()
	await _until(62.42)
	gm.heard_source = _given_clock(STRING_SONG + 1.0, false)
	await _until(62.48)
	check("and the take went to the host, my one note from STRING_SONG (%s)" % [gm.last_take],
			not gm.is_recording() and int(gm.last_take.get("notes", 0)) == 1
			and absf(float(gm.last_take.get("start", 0.0)) - STRING_SONG) < 0.1)
	gm.reach(RoomString.SOURCE, false)
	gm.heard_source = Callable()
	gm.target_track = 0
	string.queue_free()


## Host: the guest's block (slice 49), answered as the studio answers it (MarbleRun.answer): the room's
## row `marbles` with it, published, or the refusal told to the guest.
func _answer_marble(args: Array, from: int) -> void:
	var rows: Dictionary = (Session.room.get(MarbleRun.ROW, {}) as Dictionary).duplicate()
	var refusal := MarbleRun.answer(rows, args[0], args[1], args[2])
	if refusal != "":
		Session.tell(from, refusal)
		return
	var room: Dictionary = Session.room.duplicate(true)
	room[MarbleRun.ROW] = rows
	Session.publish_room(room)


## The bells the marbles ring over MARBLE_BAR in `rows`, in this side's song: [beat, cell, note] each.
func _marble_rings(rows: Dictionary) -> Array:
	var from := DAW.state.bar_to_seconds(MARBLE_BAR)
	return MarbleRun.rings(rows, [], DAW.state, from, DAW.state.bar_to_seconds(MARBLE_BAR + 1.0)).map(
			func(r: Dictionary) -> Array: return [snappedf(float(r["beat"]), 0.0001), r["cell"], int(r["note"])])


## Host: the guest's two blocks (slice 49) are in my room's row, its third outside the lattice not;
## and my rings over MARBLE_BAR published (`marbles_probe`) for the guest to set its own beside.
func _check_and_publish_the_marbles() -> void:
	var asks := _room_asks.filter(func(a: Array) -> bool: return a[0] == MarbleRun.VERB)
	var rows: Dictionary = Session.room.get(MarbleRun.ROW, {})
	check("the guest's three blocks reached me as the room's asks (%d)" % asks.size(),
			asks.size() == 3 and asks.all(func(a: Array) -> bool: return a[2] == _other_id()))
	check("and its two in the lattice are my room's blocks, the one outside not (%s)" % [rows],
			rows.size() == 2 and rows.get(MARBLE_TOP) == [&"ramp", 1] and rows.get(MARBLE_BELL) == [&"bell", 1])
	var room: Dictionary = Session.room.duplicate(true)
	room["marbles_probe"] = _marble_rings(rows)
	Session.publish_room(room)
	check("over MARBLE_BAR my run rings its bell once, a sixteenth into the bar (%s)" % [room["marbles_probe"]],
			(room["marbles_probe"] as Array).size() == 1 and room["marbles_probe"][0][1] == MARBLE_BELL)


## Guest: two blocks of the lattice asked of the host at 62.56 (slice 49), and one outside it, which
## it refuses to me in words; by 62.68 my mirror of the room has the two, and my own rings over
## MARBLE_BAR, from my copy of the host's song, are the host's.
func _build_a_marble_run() -> void:
	await _until(62.56)
	var seq := Session.ask_room(MarbleRun.VERB, [MARBLE_TOP, &"ramp", 1])
	Session.ask_room(MarbleRun.VERB, [MARBLE_BELL, &"bell", 1])
	Session.ask_room(MarbleRun.VERB, [MARBLE_OUTSIDE, &"bell", 0])
	check("my blocks are asked of the host (seq %d)" % seq, seq > 0)
	await _until(62.68)
	var rows: Dictionary = Session.room.get(MarbleRun.ROW, {})
	check("and by 62.68 the room's blocks are my two (%s)" % [rows],
			rows.size() == 2 and rows.get(MARBLE_TOP) == [&"ramp", 1] and rows.get(MARBLE_BELL) == [&"bell", 1])
	check("the one outside the lattice was refused to me, in words",
			_notices.any(func(t) -> bool: return String(t).begins_with("That cell is outside the lattice")))
	var theirs: Array = Session.room.get("marbles_probe", [])
	var mine := _marble_rings(rows)
	check("my run rings the host's bells over MARBLE_BAR, bell for bell (%s / %s)" % [mine, theirs],
			not mine.is_empty() and mine == theirs)


## Host: the guest's cable or knob on the modular wall (slice 51), answered as the studio answers it
## (Modular.answer_patch, answer_knob): the room's row `modular` with it, published, or the refusal
## told to the guest.
func _answer_modular(verb: StringName, args: Array, from: int) -> void:
	var patch := Modular.clean(Session.room.get(Modular.ROW, Modular.default_patch()))
	var refusal := Modular.answer_patch(patch, args[0], args[1]) if verb == Modular.PATCH_VERB \
			else Modular.answer_knob(patch, args[0], args[1])
	if refusal != "":
		Session.tell(from, refusal)
		return
	var room: Dictionary = Session.room.duplicate(true)
	room[Modular.ROW] = patch
	Session.publish_room(room)
	# Into a take through the modular, at the song it was asked at, as the studio does (slice 52).
	if verb == Modular.PATCH_VERB:
		Session.modular_takes.cable(args[0], args[1], args[2])
	else:
		Session.modular_takes.knob(args[0], args[1], args[2])


## The grain cloud's sound on both halves (slice 55): two seconds of a tone swelling from silence, at
## GrainVoice.RATE, every place in it different, standing in for a sample both machines have.
func _probe_grain_sound() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(2 * GrainVoice.RATE)
	for i in out.size():
		out[i] = sin(float(i) * 0.05) * 0.6 * float(i) / out.size()
	return out


## Host: the guest's take on the grain cloud (slice 55), as my DAW has it: every event heard from the
## guest in order, and one audio take named `grains` on TAKE_TRACK at its first event's song; its
## start, frames and digest published for the guest.
func _check_the_grain_take() -> void:
	var heard := _grains_heard.filter(func(g: Array) -> bool: return g[1] == _other_id())
	var ticks: Array = heard.map(func(g: Array) -> int: return int((g[0] as PackedFloat32Array)[GrainVoice.TICK]))
	check("the guest's grain events reached me, every one, in order (%s)" % [ticks],
			heard.size() == GRAINS and range(ticks.size()).all(func(i: int) -> bool: return ticks[i] == ticks[0] + i))
	var near := DAW.state.track(TAKE_TRACK).items.filter(func(it: MixState.ItemState) -> bool:
			return it.start > GRAINS_SONG - 0.1 and it.start < GRAINS_SONG + 1.0)
	check("and its take is one audio take named grains on track %d at its first event's song (%s)" % [TAKE_TRACK,
			near.map(func(it: MixState.ItemState) -> String: return "%s %.3f %.3f" % [it.name, it.start, it.length])],
			near.size() == 1 and near[0].name == GrainTakes.NAME and near[0].source.ends_with(".wav")
			and _grains_placed.size() == 1 and not heard.is_empty() and absf(near[0].start - float(heard[0][2])) < 1e-3)
	if _grains_placed.size() != 1:
		return
	var info: Dictionary = _grains_placed[0]
	var bytes := FileAccess.get_file_as_bytes(info["path"])
	var frames := (bytes.size() - AudioTake.HEADER_BYTES) / 2
	check("rendered from my own sound: %d frames, %.3f s from %.3f" % [frames, info["seconds"], info["start"]],
			frames > 0 and info["peer"] == _other_id())
	var room: Dictionary = Session.room.duplicate(true)
	room["grains_probe"] = [info["start"], frames, _digest(bytes.slice(AudioTake.HEADER_BYTES))]
	Session.publish_room(room)


## Guest: the grain cloud played (slice 55) from 64.08, GRAINS events a frame apart stamped with the
## song I hear from GRAINS_SONG, recording onto TAKE_TRACK; the clock stopped at 64.3 ends the take.
## By 64.46 the host's WAV of it is my own render of it, at my first event's song.
func _play_the_grains() -> void:
	await _until(64.08)
	var gm := Session.guest_midi
	var gt := Session.grain_takes
	gm.target_track = TAKE_TRACK
	gm.heard_source = _given_clock(GRAINS_SONG, true)
	for n in GRAINS:
		Session.send_grains(GrainVoice.event(777 + n, 0.2 + n * 0.05, 0.03 + n * 0.01, 12.0 + n * 3.0, 0.1), gt.song())
		await get_tree().process_frame
	check("recording, my grains are a take of my own (%d events)" % (gt.mine.events.size() if gt.mine != null else -1),
			gt.mine != null and gt.mine.events.size() == GRAINS)
	await _until(64.3)
	gm.heard_source = _given_clock(GRAINS_SONG + 2.0, false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("the song stopped, my take is ended and kept, from my first event's song (%.3f)" % (gt.last_mine.lands() if gt.last_mine != null else -1.0),
			gt.mine == null and gt.last_mine != null and gt.last_mine.events.size() == GRAINS
			and absf(gt.last_mine.lands() - GRAINS_SONG - GrainVoice.latency_seconds()) < 0.25)
	gm.heard_source = Callable()
	gm.target_track = 0
	await _until(64.46)
	var theirs: Array = Session.room.get("grains_probe", [])
	var mine := ModularTake.pcm(GrainTake.at_take_rate(gt.last_mine.render(_probe_grain_sound()))) if gt.last_mine != null else PackedByteArray()
	check("and the host's audio take of it is my own render: at my first event's song, as long, the same samples (%s)" % [theirs],
			theirs.size() == 3 and gt.last_mine != null and absf(float(theirs[0]) - gt.last_mine.lands()) < 1e-6
			and int(theirs[1]) == mine.size() / 2 and theirs[2] == _digest(mine))


## Host: the guest's lyrics (slice 56), as my song has them: its two lines, the first stamped by its
## TAP at the song it heard, LYRIC_SONG, and the second still untimed.
func _check_the_guests_tap() -> void:
	var lyr := Lyrics.parse(DAW.state.lyrics)
	var lines := lyr.lines
	check("the guest's lyrics are my song's: two lines (%s)" % DAW.state.lyrics.c_escape(),
			lines.size() == 2 and str(lines[0]["text"]) == "line one" and str(lines[1]["text"]) == "line two")
	check("its TAP stamped the first at the song it heard, the second still untimed",
			lines.size() == 2 and absf(float(lines[0]["t"]) - LYRIC_SONG) < 0.1 and float(lines[1]["t"]) == Lyrics.UNTIMED)


## Guest: a lyric board of my own (slice 56): at 64.52 it writes two untimed lines, and at 64.6,
## hearing the song from LYRIC_SONG, TAP stamps the first. Both are intents the host's song takes.
func _tap_the_lyrics() -> void:
	await _until(64.52)
	var board := LyricBoard.new()
	add_child(board)
	check("my board writes two lines to the host's song", board.write_text("line one\nline two") == "")
	await _until(64.6)
	board.heard_source = _given_clock(LYRIC_SONG, true)
	var why := board.tap()
	check("and TAP, the song playing, stamps the first (%s)" % why, why.is_empty())
	board.queue_free()


## The modular's patch as both halves hear it here: the room's row (slice 52's takes start from it).
func _probe_patch() -> Dictionary:
	return Modular.clean(Session.room.get(Modular.ROW, Modular.default_patch()))


## The MD5 of `bytes`, hex.
static func _digest(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## Host: the guest's take through the modular (slice 52), as my DAW has it: one audio take named
## `modular` on TAKE_TRACK at MODULAR_SONG, no MIDI take of it there, its notes heard as the
## modular's and its sweep as it streamed; its start, frames and digest published for the guest.
func _check_the_modular_take() -> void:
	var notes := _sourced.filter(func(n: Array) -> bool: return n[3] == Modular.SOURCE and n[2] == _other_id())
	check("the guest's keys at the wall reached me as the modular's (%s)" % [notes],
			notes.size() >= 2 and int(notes[0][1]) == MODULAR_PITCH)
	var sweep := _knobs_heard.filter(func(k: Array) -> bool: return k[2] == _other_id()).slice(MODULAR_TURNS.size())
	check("and its sweep as it streamed (%d of %d)" % [sweep.size(), MODULAR_SWEEP.size()],
			sweep.size() == MODULAR_SWEEP.size() and range(sweep.size()).all(func(i: int) -> bool:
				return is_equal_approx(sweep[i][1], MODULAR_SWEEP[i])))
	var near := DAW.state.track(TAKE_TRACK).items.filter(func(it: MixState.ItemState) -> bool:
			return it.start > MODULAR_SONG - 0.1 and it.start < MODULAR_SONG + 1.0)
	check("and its take is one audio take named modular on track %d at its song, no MIDI (%s)" % [TAKE_TRACK,
			near.map(func(it: MixState.ItemState) -> String: return "%s %.3f %.3f" % [it.name, it.start, it.length])],
			near.size() == 1 and near[0].name == ModularTakes.NAME and near[0].notes.is_empty()
			and near[0].source.ends_with(".wav") and _modular_placed.size() == 1)
	if _modular_placed.size() != 1:
		return
	var info: Dictionary = _modular_placed[0]
	var bytes := FileAccess.get_file_as_bytes(info["path"])
	var frames := (bytes.size() - AudioTake.HEADER_BYTES) / 2
	check("rendered from what reached me: %d frames, %.3f s from %.3f" % [frames, info["seconds"], info["start"]],
			frames > 0 and info["peer"] == _other_id())
	var room: Dictionary = Session.room.duplicate(true)
	room["modular_probe"] = [info["start"], frames, _digest(bytes.slice(AudioTake.HEADER_BYTES))]
	Session.publish_room(room)


## Guest: the modular played (slice 52) from 63.06 at the wall, onto TAKE_TRACK at MODULAR_SONG:
## MODULAR_PITCH held, the wheel moved up at 63.1 (its move to the host reliable, behind the notes:
## ModularTakes.bend) and the cutoff swept down from then a frame at a time, let go at 63.24, the
## clock stopped at 63.26 and the take ended. By 63.68 the host's WAV of it is my own render of it.
func _play_the_modular() -> void:
	await _until(63.06)
	var gm := Session.guest_midi
	var mt := Session.modular_takes
	gm.target_track = TAKE_TRACK
	gm.heard_source = _given_clock(MODULAR_SONG, true)
	gm.reach(Modular.SOURCE, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("at the wall my keys record through the modular (%s)" % [mt.mine],
			gm.is_recording() and gm.through_modular() and mt.mine != null)
	gm.note_on(MODULAR_PITCH, 100)
	await _until(63.1)
	gm.control(DawKitClip.PITCH_BEND, 4096)
	for v: float in MODULAR_SWEEP:
		Session.send_knob(&"vcf.cutoff", v, gm.song())
		await get_tree().physics_frame
	await _until(63.24)
	gm.note_off(MODULAR_PITCH)
	await _until(63.26)
	gm.heard_source = _given_clock(MODULAR_SONG + 1.0, false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("ended, my take is the modular's, from MODULAR_SONG, and no MIDI take was sent (%s)" % [gm.last_take],
			not gm.is_recording() and gm.last_take.get("modular", false) and mt.last_mine != null
			and absf(mt.last_mine.start - MODULAR_SONG) < 0.1
			and mt.last_mine.events.filter(func(e: Array) -> bool: return e[1] == Modular.Event.KNOB).size() == MODULAR_SWEEP.size()
			and mt.last_mine.events.any(func(e: Array) -> bool: return e[1] == Modular.Event.BEND and e[2] == 4096))
	gm.reach(Modular.SOURCE, false)
	gm.heard_source = Callable()
	gm.target_track = 0
	await _until(63.68)
	var theirs: Array = Session.room.get("modular_probe", [])
	var mine := ModularTake.pcm(mt.last_mine.render()) if mt.last_mine != null else PackedByteArray()
	check("and the host's audio take of it is my own render: at my song, as long, the same samples (%s)" % [theirs],
			theirs.size() == 3 and absf(float(theirs[0]) - mt.last_mine.start) < 1e-6 and int(theirs[1]) == mine.size() / 2
			and theirs[2] == _digest(mine))


## WEATHER_BAR of the loft's Thunderstorm through `patch` (slice 53): MODULAR_PITCH held from its start,
## and the weather's level and drops played into the patch from this half's song
## (ModularWorld.weather_events), as both halves work it out.
func _world_render(patch: Dictionary) -> PackedFloat32Array:
	var loft := Venue.make(&"loft", LoftVenue.STORM)
	var spec := Weather.spec_of(loft)
	var venue_seed := Weather.seed_of(loft.venue_id())
	loft.free()
	var from := DAW.state.bar_to_seconds(WEATHER_BAR)
	var to := DAW.state.bar_to_seconds(WEATHER_BAR + 1.0)
	var events := [[from, Modular.Event.ON, MODULAR_PITCH, 100]] + ModularWorld.weather_events(spec, venue_seed, DAW.state, from, to)
	return Modular.render(patch, events, from, roundi((to - from) * Modular.RATE))


## Host: the guest's weather into my VCF's CV (slice 53) is my room's row, the LFO it pulled out of
## there gone, and my render of the storm's bar through it is published for the guest (`world_probe`).
func _check_the_world_patched() -> void:
	var patch := Modular.clean(Session.room.get(Modular.ROW, {}))
	var asks := _room_asks.filter(func(a: Array) -> bool:
			return a[0] == Modular.PATCH_VERB and a[2] == _other_id() and Modular.is_world(StringName(a[1][0])))
	check("the guest's weather into the VCF's CV reached me as the room's ask, and is my row (%s)" % [patch["cables"]],
			asks.size() == 1 and Modular.source_of(patch, &"vcf.cv") == &"world:weather"
			and not Modular.sinks_of(patch, &"lfo.out").has(&"vcf.cv"))
	var out := _world_render(patch)
	var loudest := 0.0
	for v in out:
		loudest = maxf(loudest, absf(v))
	check("my render of the storm's bar through it sounds (%d frames, %.3f)" % [out.size(), loudest], loudest > 0.05)
	var room: Dictionary = Session.room.duplicate(true)
	room["world_probe"] = [out.size(), _digest(out.to_byte_array())]
	Session.publish_room(room)


## Guest: at 63.74 the LFO out of the room's VCF's CV and the weather's socket into it (slice 53), each
## asked of the host; by 63.86 my mirror of the room's patch has it, and my render of the storm's bar
## through it is, by 64.0, the host's, sample for sample.
func _patch_the_world() -> void:
	await _until(63.74)
	var song := Session.guest_midi.song() if Session.guest_midi != null else -1.0
	Session.ask_room(Modular.PATCH_VERB, [&"vcf.cv", &"", song])
	var seq := Session.ask_room(Modular.PATCH_VERB, [&"world:weather", &"vcf.cv", song])
	check("the weather into the VCF's CV is asked of the host (seq %d)" % seq, seq > 0)
	await _until(63.86)
	var patch := Modular.clean(Session.room.get(Modular.ROW, {}))
	check("and by 63.86 the room's patch has the weather on the VCF's CV (%s)" % [patch["cables"]],
			Modular.source_of(patch, &"vcf.cv") == &"world:weather")
	var mine := _world_render(patch)
	# The host's render of the bar takes it most of a tenth of a second past 63.8 before it publishes.
	await _until(64.0)
	var theirs: Array = Session.room.get("world_probe", [])
	check("both renders of the storm's bar through it agree, sample for sample (%s)" % [theirs],
			theirs.size() == 2 and int(theirs[0]) == mine.size() and theirs[1] == _digest(mine.to_byte_array()))


## Host: the guest's re-patch (slice 51) is in my room's row, its cable into a taken input not; its
## knob let go is the row's, and its turn reached me as it streamed, from the guest, in order.
func _check_the_modular() -> void:
	var asks := _room_asks.filter(func(a: Array) -> bool: return a[0] == Modular.PATCH_VERB or a[0] == Modular.KNOB_VERB)
	var patch := Modular.clean(Session.room.get(Modular.ROW, {}))
	check("the guest's two cables and its knob reached me as the room's asks (%d)" % asks.size(),
			asks.size() == 3 and asks.all(func(a: Array) -> bool: return a[2] == _other_id()))
	check("and my room's patch has its LFO on the VCF's CV, not the noise refused there (%s)" % [patch["cables"]],
			Modular.source_of(patch, &"vcf.cv") == &"lfo.out" and patch["cables"].size() == Modular.DEFAULT_CABLES.size() + 1)
	check("and its knob let go (%.2f)" % patch["knobs"][&"vcf.cutoff"], is_equal_approx(patch["knobs"][&"vcf.cutoff"], MODULAR_KNOB))
	var turned := _knobs_heard.filter(func(k: Array) -> bool: return k[2] == _other_id())
	check("its knob's turn reached me as it streamed, in order, from the guest (%s)" % [turned],
			turned.size() == MODULAR_TURNS.size() and turned.all(func(k: Array) -> bool: return k[0] == &"vcf.cutoff")
			and range(turned.size()).all(func(i: int) -> bool: return is_equal_approx(turned[i][1], MODULAR_TURNS[i])))


## Guest: the room's modular re-patched at 62.94 (slice 51): an LFO onto the VCF's CV asked of the
## host, and the noise into the same input, which it refuses to me in words; a knob's turn streamed
## and let go. By 63.04 my mirror of the room has the cable and the knob.
func _patch_the_modular() -> void:
	await _until(62.94)
	var song := Session.guest_midi.song() if Session.guest_midi != null else -1.0
	var seq := Session.ask_room(Modular.PATCH_VERB, [&"lfo.out", &"vcf.cv", song])
	Session.ask_room(Modular.PATCH_VERB, [&"noise.out", &"vcf.cv", song])
	for v: float in MODULAR_TURNS:
		Session.send_knob(&"vcf.cutoff", v, song)
	Session.ask_room(Modular.KNOB_VERB, [&"vcf.cutoff", MODULAR_KNOB, song])
	check("my cables and my knob are asked of the host (seq %d)" % seq, seq > 0)
	await _until(63.04)
	var patch := Modular.clean(Session.room.get(Modular.ROW, {}))
	check("and by 63.04 the room's patch has my LFO on the VCF's CV and my knob (%s)" % [patch["cables"]],
			Modular.source_of(patch, &"vcf.cv") == &"lfo.out" and is_equal_approx(patch["knobs"][&"vcf.cutoff"], MODULAR_KNOB))
	check("the noise into the same input was refused to me, in words",
			_notices.any(func(t) -> bool: return String(t).contains("VCF CV IN has a cable in it already")))


## Host: the guest's press on the weather's switch (slice 44) reached me from the guest, and my
## room's row is LISTEN.
func _check_weather_asked() -> void:
	var asks := _room_asks.filter(func(a: Array) -> bool: return a[0] == Weather.VERB)
	check("the guest's press on the weather's switch reached me (%s)" % [asks],
			asks.size() == 1 and asks[0][1] == [true] and asks[0][2] == _other_id())
	check("and my room's weather row is LISTEN", Session.room.get(Weather.VERB, false) == true)


## Guest: the weather's switch pressed (slice 44), LISTEN asked of the host, and by 61.56 its room's
## row says so; and my own schedule of the Thunderstorm's bar, from my copy of the host's song, is
## the host's drop for drop.
func _press_the_weather() -> void:
	await _until(61.46)
	var seq := Session.ask_room(Weather.VERB, [true])
	check("my press on the weather's switch is asked of the host (seq %d)" % seq, seq > 0)
	await _until(61.56)
	check("and the room's weather row is LISTEN (%s)" % [Session.room.get(Weather.VERB)],
			Session.room.get(Weather.VERB, false) == true)
	var theirs: Array = Session.room.get("weather_probe", [])
	var mine := _weather_schedule()
	check("both halves schedule the same drops over the Thunderstorm's bar (%d here, %d there)" % [mine.size(), theirs.size()],
			not mine.is_empty() and mine == theirs)


## Host: the guest's strike on the railing's third baluster (slice 42) reached me from the guest with
## its song, and my baluster, which stands where the guest's does, rings it there on the song's
## scale tone at that moment, its own sound, held by nobody.
func _check_railing_strike() -> void:
	var id := VenueInstrument.bar_id(RAILING_BAR)
	var hits := _item_hits.filter(func(h: Array) -> bool: return h[0] == id)
	check("the guest's strike on the railing reached me with its song (%s)" % [hits],
			hits.size() == 1 and hits[0][2] == _other_id() and is_equal_approx(float(hits[0][3]), RAILING_SONG)
			and int(hits[0][1]) == InstrumentItem.velocity_for(DRUM_SPEED))
	var baluster := _room.items.get(id) as VenueInstrument.Bar
	if hits.size() != 1 or baluster == null:
		return
	var presence := Presence.new()
	presence.items = _room
	var was := baluster._take
	var hit: Array = hits[0]
	presence._on_item_hit(hit[0], hit[1], hit[2], hit[3], hit[4], hit[5], hit[6])
	var tone := VenueInstrument.scale_tone(Harmony.at(DAW.state, RAILING_SONG), int(baluster.set_spec["low"]), RAILING_BAR)
	check("and my baluster rings it where it stands, on the song's scale tone there (%d), held by nobody" % baluster.last_note,
			_room.stands(id) and baluster._take == was + 1 and baluster.last_note == tone
			and baluster.sound_kind(true) == &"baluster" and Session.holder_of(baluster.network_key()) == 0)
	presence.free()


## Host: the guest's hit on a pad of its own (slice 41) reached me on the kit with its drum and song,
## and my kit rings it: from the guest's ghost where there is one, here at the kit, held by nobody.
func _check_pad_hit() -> void:
	var hits := _item_hits.filter(func(h: Array) -> bool: return h[0] == KitItem.KIND)
	check("the guest's pad hit reached me on the kit with its drum and song (%s)" % [hits],
			hits.size() == 1 and hits[0][2] == _other_id() and hits[0][6] == &"kick"
			and is_equal_approx(float(hits[0][3]), PAD_SONG) and int(hits[0][1]) == InstrumentItem.velocity_for(DRUM_SPEED))
	var kit := _room.items.get(KitItem.KIND) as KitItem
	if hits.size() != 1 or kit == null:
		return
	var presence := Presence.new()
	presence.items = _room
	var was := kit._take
	var hit: Array = hits[0]
	presence._on_item_hit(hit[0], hit[1], hit[2], hit[3], hit[4], hit[5], hit[6])
	check("and my kit rings it, its kick's sound, held by nobody",
			kit._take == was + 1 and kit.last_zone == &"kick" and kit.kind_of_hit(true, kit.last_zone) == &"kick"
			and Session.holder_of(kit.network_key()) == 0)
	presence.free()


func _take_back_the_note() -> void:
	var at := DAWBackend.marker_key(DAW.state.markers, NOTE_AT)
	if not is_nan(at):
		DAW.remove_marker(at)


## A chord harp of my own, on my keys, as the studio stands one.
func _harp() -> ChordHarp:
	var harp := ChordHarp.new()
	add_child(harp)
	return harp


## A strum across all eight strings, low to high, through the grab contract a mouse uses. Its
## strings ring out by themselves, RING later, and their note-offs go too.
func _strum(harp: ChordHarp) -> void:
	var hand := Node.new()
	add_child(hand)
	harp.grab_begin(hand, harp.to_global(Vector3(ChordHarp.string_x(0), 1.0, 0)))
	harp.grab_move(hand, harp.to_global(Vector3(ChordHarp.string_x(ChordHarp.STRINGS - 1) + 0.01, 1.0, 0)))
	harp.grab_end(hand)
	hand.queue_free()


## The strum heard from `from`: eight harp notes on, low to high, each the string's tone of the
## chord at the song position it was played to (the playhead, the song stopped), and each let go.
func _check_strum(from: int, label: String) -> void:
	var ons := _harped.filter(func(n: Array) -> bool: return n[0] == Session.Note.ON and n[2] == from)
	var offs := _harped.filter(func(n: Array) -> bool: return n[0] == Session.Note.OFF and n[2] == from)
	var pitches := ons.map(func(n: Array) -> int: return int(n[1]))
	var tuned := true
	for i in ons.size():
		var song: float = ons[i][3]
		var at := song if song >= 0.0 else DAW.state.position_seconds
		var wanted := Harmony.at(DAW.state, at).tones(ChordHarp.LOWEST, ChordHarp.STRINGS)
		tuned = tuned and i < wanted.size() and wanted[i] == int(ons[i][1])
	check("%s as harp notes of the chord, low to high (%s)" % [label, pitches],
			ons.size() == ChordHarp.STRINGS and tuned)
	check("the chord the host wrote, D minor's strings", pitches == HARP_STRINGS)
	check("and each rang out and was let go (%d)" % offs.size(), offs.size() == ChordHarp.STRINGS)


## Waits until `seconds` into the probe by this process's clock, never before. A timer made at the end
## of a long frame is credited with that whole frame on its first tick and so can fire early by as
## much (the first ring of a sound made is tens of milliseconds), so it is waited out again until the
## clock agrees.
func _until(seconds: float) -> void:
	var left := seconds + _shift - (Time.get_ticks_msec() - _start) / 1000.0
	while left > 0.0:
		await get_tree().create_timer(left).timeout
		left = seconds + _shift - (Time.get_ticks_msec() - _start) / 1000.0


func check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])


# The guest's marker, found by its name: it is dropped at GUEST_MARK seconds, but the guest
# changes the tempo too, and Reaper's markers keep their beat, so in seconds it moves.
static func _has_guest_mark(state: MixState) -> bool:
	return state.markers.values().has("GUEST")


## A microphone in front of a perfect player: a clap on every click the guest hears, at the
## moment it hears it. Frames are made by the wall clock, HOLD_MS behind it, so every click is
## heard before the frames around it are made -- which makes HOLD_MS this microphone's latency.
class Clapper extends MixSource:
	const HOLD_MS := 40.0
	const RATE := 48000.0
	var _start_usec := 0
	var _made := 0

	func start() -> bool:
		_start_usec = Time.get_ticks_usec()
		_made = 0
		return true

	func read() -> PackedVector2Array:
		var due := int((Time.get_ticks_usec() - _start_usec - HOLD_MS * 1000.0) * RATE / 1000000.0)
		var out := PackedVector2Array()
		if due <= _made:
			return out
		out.resize(due - _made)
		for c in Session.mix_feed.clicks_heard():
			var at := int((int(c[1]) - _start_usec) * RATE / 1000000.0)
			for k in 48:
				if at + k >= _made and at + k < due:
					out[at + k - _made] = Vector2(0.9, 0.9)
		_made = due
		return out

	func latency_ms() -> float:
		return HOLD_MS

	func rate() -> float:
		return RATE

	func describe() -> String:
		return "A clapping test microphone"


## Host: the guest's theremin glide (slice 50), as my DAW has it: one item on TAKE_TRACK at
## THEREMIN_SONG named for the theremin, its notes rising from THEREMIN_FROM and each down before the
## last let go, its bends and its CC 11 in it; and its notes heard with the theremin's source.
func _check_theremin_take() -> void:
	var heard := _sourced.filter(func(n: Array) -> bool: return n[3] == Theremin.SOURCE and n[0] == Session.Note.ON)
	check("the guest's theremin reached me as notes from it, handed on (%s)" % [heard],
			heard.size() >= 2 and int(heard[0][1]) == roundi(THEREMIN_FROM) and int(heard[0][2]) == _other_id())
	var takes: Array = DAW.state.track(TAKE_TRACK).items.filter(func(it: MixState.ItemState) -> bool:
			return it.start > THEREMIN_SONG - 0.1 and it.start < THEREMIN_SONG + 1.0)
	check("and its take is an item on track %d (%d)" % [TAKE_TRACK, takes.size()], takes.size() == 1)
	if takes.size() != 1:
		return
	var item: MixState.ItemState = takes[0]
	var notes := MidiTake.unpack_relative(item.notes, item.start)
	notes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var legato := notes.size() >= 2 and int(notes[0][2]) == roundi(THEREMIN_FROM)
	for i in range(1, notes.size()):
		legato = legato and int(notes[i][2]) > int(notes[i - 1][2]) and notes[i][0] <= notes[i - 1][1] + 0.001
	check("named for the theremin, its notes rising, each down before the last let go (%s, %s)" % [item.name, notes],
			item.name.contains("theremin") and legato)
	var bends := 0
	var swells: Array = []
	for o in range(0, item.controls.size() - DawKitClip.CONTROL_WIDTH + 1, DawKitClip.CONTROL_WIDTH):
		if int(item.controls[o + 1]) == DawKitClip.PITCH_BEND:
			bends += 1
		elif int(item.controls[o + 1]) == 11:
			swells.append(int(item.controls[o + 2]))
	check("with its glide's bends and its CC 11 from the loop, half way up (%d bends, CC 11 %s)" % [bends, swells],
			bends >= 3 and not swells.is_empty() and swells[0] == 64)


## Guest: a theremin of my own (slice 50) played from 62.72 by two hands of mine, its pitch hand
## gliding in from THEREMIN_FROM to THEREMIN_TO by 62.84, onto TAKE_TRACK at THEREMIN_SONG; the volume
## hand down at 62.84, the clock stopped at 62.86, and the take sent.
func _play_a_theremin() -> void:
	await _until(62.72)
	var gm := Session.guest_midi
	gm.reach(Theremin.SOURCE, true)
	gm.target_track = TAKE_TRACK
	gm.heard_source = _given_clock(THEREMIN_SONG, true)
	var t := Theremin.new()
	t.keys = gm
	t.snap = Theremin.Snap.FREE
	var at := {"pitch": THEREMIN_FROM, "volume": Theremin.VOLUME_SPAN * 0.5 + 0.001}
	t.hands = func() -> Array:
		return [{"at": t.to_global(Vector3(Theremin.ROD.x + Theremin.distance_for(float(at["pitch"])), Theremin.GUIDE_Y,
				Theremin.ROD.y)), "by": self},
				{"at": t.to_global(Theremin.LOOP + Vector3(0, Theremin.LOOP_REST + float(at["volume"]), 0)), "by": t}]
	t.clock = func() -> float: return float(gm.heard_source.call()["seconds"])
	add_child(t)
	# Its first step: physics_frame is emitted before the frame's _physics_process, so the second one
	# is the first after the theremin has read its hands. The glide begins from there.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var began := Time.get_ticks_msec()
	check("my theremin holds A4 at half volume, recording (%d, %d)" % [t.note, t.expression],
			t.note == roundi(THEREMIN_FROM) and t.expression == 64 and gm.is_recording())
	while (Time.get_ticks_msec() - _start) / 1000.0 - _shift < 62.84:
		var gone := (Time.get_ticks_msec() - began) / 1000.0
		at["pitch"] = lerpf(THEREMIN_FROM, THEREMIN_TO, clampf(gone / 0.06, 0.0, 1.0))
		await get_tree().physics_frame
	check("and glided in past the bend's edge it handed its note on (%d hand-ons, at %d)" % [t.handed_on, t.note],
			t.handed_on >= 2 and t.note > roundi(THEREMIN_FROM) + 2)
	at["volume"] = -0.01
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("the volume hand down on the loop, it is silent", not t.sounding() and gm.held.is_empty())
	await _until(62.86)
	gm.heard_source = _given_clock(THEREMIN_SONG + 1.0, false)
	await _until(62.9)
	check("and the take went to the host from THEREMIN_SONG, with its controls (%s)" % [gm.last_take],
			not gm.is_recording() and int(gm.last_take.get("notes", 0)) >= 2 and int(gm.last_take.get("controls", 0)) >= 3
			and absf(float(gm.last_take.get("start", 0.0)) - THEREMIN_SONG) < 0.1)
	gm.reach(Theremin.SOURCE, false)
	gm.heard_source = Callable()
	gm.target_track = 0
	t.queue_free()
