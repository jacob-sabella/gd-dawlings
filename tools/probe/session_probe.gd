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
## The track the guest records onto.
const TAKE_TRACK := 7
## The track the guest's microphone records onto, in the same take as its keys.
const AUDIO_TRACK := 8
## How far a placed note may be from the moment the guest heard it, in seconds.
const TAKE_TOLERANCE := 0.005
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
## Host: the guest's recording, as Session placed it.
var _audio_placed := {}
## Host: what guests asked of the room, as [verb, args, from].
var _room_asks: Array = []
## Host: where the guest said something was while pushing it.
var _motions: Array = []
## Guest: how many times the host's room arrived.
var _rooms_heard := 0
## Heard from the other side: [item, local or down, from] for carries and uses.
var _carries: Array = []
var _uses: Array = []
## Notes heard from the other half, as Session.note_played gives them.
var _notes: Array = []
## Who the host's table said had the duck when the guest's put-down reached it.
var _duck_holder_at_put := -1
## Who has had the plane, in turn, as the host's table said.
var _plane_holders: Array = []


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
	Session.audio_take_placed.connect(func(info: Dictionary): _audio_placed = info)
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
	Session.note_played.connect(func(kind: int, pitch: int, velocity: int, from: int, _song: float):
		_notes.append([kind, pitch, velocity, from]))
	Session.room_asked.connect(func(verb: StringName, args: Array, from: int):
		_room_asks.append([verb, args, from])
		if verb == &"put_item":
			_duck_holder_at_put = Session.holder_of(DUCK)
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
	check("and its plug in the MIX send, for its own headphones (%s)" % [_room_asks[5] if _room_asks.size() > 5 else null],
			_room_asks.size() == 6 and _room_asks[5][0] == &"patch" and _room_asks[5][1] == [1, &"mix"]
			and _room_asks[5][2] == guest_id)
	Session.claim_hold(KEY)
	check("so the host can take it now", Session.holder_of(KEY) == 1)
	Session.release_hold(KEY)

	# The guest records a take against what it hears: see _guest_records. Not on the built-in
	# engine's song, which has no clicks to time the notes against.
	await _until(7.0)
	if not _built_in:
		DAW.transport_record()
	await _until(12.8)
	if not _built_in:
		DAW.transport_stop()
	else:
		# A different project opened mid-session reaches the guest whole: six tracks, the first
		# renamed, where there were thirteen.
		var other := ProjectBridge.capture(DAW.backend as OfflineBackend)
		other.tracks.resize(6)
		for t in other.tracks:
			t.sends = t.sends.filter(func(sd): return other.track(sd.target) != null)
		other.tracks[0].name = "Opened"
		var refused := ProjectBridge.load(other, DAW.backend as OfflineBackend)
		check("I opened another project mid-session (%s)" % [refused], refused.is_empty())
	await _until(14.0)
	if not _built_in:
		_check_placed_take()
		_check_audio_take()
		await _undo_takes()

	await _until(14.4)
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
	await _until(15.4)


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
	Session.note_played.connect(func(kind: int, pitch: int, velocity: int, from: int, _song: float):
		_notes.append([kind, pitch, velocity, from]))
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
	await _until(5.2)
	check("my releases left only the plane I took from the host's hand (%s)" % [Session.holds],
			Session.holds == {PLANE: Session.local_peer_id})
	Session.release_hold(PLANE)
	check("the host's keys reached me as played (%s)" % [_notes],
			_notes == [[Session.Note.ON, 67, 80, 1], [Session.Note.OFF, 67, 0, 1]])
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
	else:
		await _until(13.8)
		check("the host's newly opened project reached me whole (%d tracks, '%s')"
				% [DAW.state.tracks.size(), DAW.state.track(1).name],
				DAW.state.tracks.size() == 6 and DAW.state.track(1).name == "Opened")

	await _until(15.0)
	print("notices: ", _notices)
	check("the host's goodbye arrived", _notices.any(func(t): return t.contains("ended the session")))
	check("and I am back on my own", Session.role == Session.Role.SOLO)
	check("and no longer listening", not Session.mix_feed.listening)
	check("with a mix of my own again", DAW.is_live() and DAW.state.tracks.size() > 0)


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
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.autostart = true
	timer.timeout.connect(func(): Session.publish_presence(head, pointing, Vector3.ZERO))
	add_child(timer)


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


func _other_id() -> int:
	for id in Session.participants:
		if id != Session.local_peer_id:
			return id
	return 0


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
