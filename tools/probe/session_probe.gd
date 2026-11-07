class_name SessionProbe
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
## The key the host writes from the playhead's bar: one chord, so either half reads the same
## harmony wherever the playhead is in it.
const KEY_MARKER := "[D minor: Dm]"
## The track the guest records onto.
const TAKE_TRACK := 7
## The track the guest's microphone records onto, in the same take as its keys.
const AUDIO_TRACK := 8
## Where the guest's files from its own machine go, and from when: a second of tone as a WAV,
## then a FLAC, one after the other.
const SENT_TRACK := 12
## Cables (docs/spatial_loop.md slice 6): the chord tones the guest's four cowbell hits play on the
## host's keys: D minor's, voiced at Jacks.TRIGGER_CENTRE.
const CABLE_TONES := [62, 65, 69, 74]
const SENT_AT := 30.0
## The fifths wheel (docs/spatial_loop.md slice 9): the bar the guest's SET names, well past
## everything else the probe writes or plays at, and what it writes there. Its second bar is C.
const WHEEL_BAR := 420
const WHEEL_INSIDE := "E minor: Em C G D"
## Where the guest's head is in its play space when it travels to a station (slice 11): off the
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
## Snapped gently (slice 17): where in the song the guest records two cowbell hits onto TAKE_TRACK
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
## How far a placed note may be from the moment the guest heard it, in seconds.
const TAKE_TOLERANCE := 0.005
## The lyrics in the booth (slice 56): at 64.52 the guest's own board (a LyricBoard of its own, not in
## a room) writes two untimed lines, which is a set_lyrics intent to the host; at 64.6, hearing the
## song from LYRIC_SONG, it TAPs, which is a second intent stamping the first line. By 64.7 the
## host's lyrics are those two lines, the first stamped at LYRIC_SONG as the guest heard it and the
## second still untimed. The session ends at 64.76.
const LYRIC_SONG := 980.0
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
## The host's sends a track when the guest arrived, {track: count}: a track with one more by the
## time it checks is the send the guest's bay pin asked for.
var _sends_before := {}
## The guest's routing bay and the crossing it pressed, [from, to], for the check once it is back.
var _bay: PatchbaySurface = null
var _bay_pin: Array = []
## That pin's send as the host found it, [track, slot], taken out again at the end.
var _pinned: Array = []
## Seconds added to every step of the timeline, on both halves: a host on a real Reaper needs a
## moment to hear the project before it has anything to share.
var _shift := 0.0
var _port := 7342
## PROBE_NORAY=1 (or punch): the guest joins by the host's code through a noray server
## (DAWLINGS_NORAY, tools/noray_local.sh) and the punch; PROBE_NORAY=relay: through its relay.
## Every other check is the same, which is the point: by a code is the same session.
var _noray := OS.get_environment("PROBE_NORAY")
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
## The other half's item hits, as Session.item_hit gives them: [item, velocity, from, song, snap,
## take, zone].
var _item_hits: Array = []
## Each half's room of items, as the studio keeps one.
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
## The head this half publishes (`_keep_publishing`), until the guest travels (`_travel_to_the_wheel`).
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


## Host: how many steps the sections' layout made (slice 29), the rearrangement among them, so all
## of it is taken back; and the history's depth before them, where the DAW says it.
var _arrange_steps := 0
var _arrange_depth := -1
## The host's answer to the guest's slap on the looper (slice 45), as the studio's (Looper.answer): the
## room's row `looper` [player, from bar, bars], published. What the answer did to my transport and
## loop is kept first, to be put back when the probe is done with it.
var _looper_was: Dictionary = {}
var _looper_layers: Array = []


## The host's half of the timeline.
var hosting := SessionProbeHost.new(self)
## Checks on bent, snapped and placed takes and the host recording itself.
var host_takes := SessionProbeTakes.new(self)
## Count-in, parts, punch and the files sent, measured; then Reaper's side.
var host_render := SessionProbeRender.new(self)
## The guest's half of the timeline.
var guesting := SessionProbeGuest.new(self)
## Playing, the wheel, the room, cassettes and sections.
var room_checks := SessionProbeRoom.new(self)
## Jacks, chords, spectra, the drum, weather and the looper.
var item_checks := SessionProbeItems.new(self)

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
		hosting._write_epoch()
		await hosting._host(port)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(hosting._epoch_path()))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(hosting._code_path()))
	else:
		await hosting._share_the_hosts_epoch()
		await guesting._guest(port)
	print("\n[%s] %d session checks, %d failed" % [role, _checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _answer_looper(args: Array, from: int) -> void: item_checks._answer_looper(args, from)

## `SessionProbeItems.check`.
func check(label: String, ok: bool) -> void: item_checks.check(label, ok)


# The guest's marker, found by its name: it is dropped at GUEST_MARK seconds, but the guest
# changes the tempo too, and Reaper's markers keep their beat, so in seconds it moves.


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
