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
## How far a placed note may be from the moment the guest heard it, in seconds.
const TAKE_TOLERANCE := 0.005
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
## Host: where the guest said something was while pushing it.
var _motions: Array = []
## Guest: how many times the host's room arrived.
var _rooms_heard := 0
## Heard from the other side: [item, local or down, from] for carries and uses.
var _carries: Array = []
var _uses: Array = []
## Notes heard from the other half, as Session.note_played gives them: plain keys' here, and an
## instrument's [kind, pitch, from, source] in `_sourced`.
var _notes: Array = []
var _sourced: Array = []
## The other half's harp notes, from when the strums begin: [kind, pitch, from, song].
var _harped: Array = []
## The other half's item hits, as Session.item_hit gives them: [item, velocity, from, song, snap,
## take].
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
## Host: the history's depth before the guest's two-value drag (slice 12), and the guest's track's
## pan and volume and the host's own track's volume then.
var _edit_depth := 0
var _edit_was: Array = [0.5, 0.5, 0.5]


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
		await _host(port)
	else:
		await _guest(port)
	print("\n[%s] %d session checks, %d failed" % [role, _checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _host(port: int) -> void:
	Session.audio_take_placed.connect(func(info: Dictionary):
		_audio_placed = info
		_placed_all.append(info))
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
	Session.item_used.connect(func(item: StringName, down: bool, from: int):
		_uses.append([item, down, from]))
	Session.note_played.connect(_on_note_played)
	Session.item_hit.connect(func(item: StringName, velocity: int, from: int, song: float, snap: bool, take: int):
		_item_hits.append([item, velocity, from, song, snap, take]))
	Session.room_asked.connect(func(verb: StringName, args: Array, from: int):
		_room_asks.append([verb, args, from])
		if verb == &"put_item":
			_duck_holder_at_put = Session.holder_of(DUCK)
		if verb == &"plug":
			_answer_plug(args, from)
		if verb == FifthsWheel.VERB:
			# As the studio answers a guest's SET: written at the bar the guest chose.
			FifthsWheel.answer(args[0], args[1])
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
	_room.played.connect(func(item: InstrumentItem, velocity: int, _struck: bool, at: float) -> void:
		_jacks.hit(item, velocity, at))
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
	await _until(55.35)
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

	# How much of the time before the end the work took: the end has moved three times as it grew.
	if DAW.backend is GodotBackend:
		print("engine: %s" % ("native lanes" if (DAW.backend as GodotBackend).lanes != null else "players"))
	print("host work done at %.1fs of 57.8" % ((Time.get_ticks_msec() - _start) / 1000.0 - _shift))
	await _until(57.8)
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
	await _until(58.7)


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
	var shakes := _item_hits.filter(func(h: Array) -> bool: return h[0] == &"shaker" and h.size() == 6)
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
	# On the host's own machine, which would ordinarily mean not listening: the host's speakers
	# are already in the room. Asked for here, because the probe is what is listening.
	Session.listen_choice = 1
	Session.room_changed.connect(func(): _rooms_heard += 1)
	Session.item_used.connect(func(item: StringName, down: bool, from: int):
		_uses.append([item, down, from]))
	Session.note_played.connect(_on_note_played)
	Session.item_hit.connect(func(item: StringName, velocity: int, from: int, song: float, snap: bool, take: int):
		_item_hits.append([item, velocity, from, song, snap, take]))
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
	_room.played.connect(func(item: InstrumentItem, velocity: int, _struck: bool, at: float) -> void:
		Session.send_item_hit(item.id, velocity, at))
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
	await _until(55.33)
	var synth: MonitorSynth = their.synths[1]
	var down: KeysDown = their._down.get(1)
	check("the host's bend during its held note is heard on my TheirKeys (%s)" % [synth.controls],
			int(synth.controls.get(DawKitClip.PITCH_BEND, 0)) == BEND_VALUE and down != null
			and down.is_down(BEND_PITCH))
	await _until(55.39)
	check("and rests at its note-off (%s)" % [synth.controls], int(synth.controls.get(DawKitClip.PITCH_BEND, -1)) == 0
			and down != null and down.is_empty())
	Session.note_played.disconnect(their.play)
	Session.control_played.disconnect(their.control)
	their.queue_free()
	await _bend_into_a_take()
	await _tilt_into_a_take()
	await _snap_into_a_take()
	await _until(58.3)
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
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.autostart = true
	timer.timeout.connect(func(): Session.publish_presence(_head, pointing, Vector3.ZERO))
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


func _until(seconds: float) -> void:
	var left := seconds + _shift - (Time.get_ticks_msec() - _start) / 1000.0
	if left > 0.0:
		await get_tree().create_timer(left).timeout


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
