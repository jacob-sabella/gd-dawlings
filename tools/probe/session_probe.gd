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
## Not the stand-in's tempo nor the rig's, so arriving at it means the write travelled.
const GUEST_TEMPO := 133.5
## A send level neither the stand-in nor the rig starts at.
const GUEST_SEND := 0.345
const GUEST_MARK := 1.25
## The track the guest records onto.
const TAKE_TRACK := 7
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
	Session.local_name = "Ada"
	var restore := NAN
	var tempo_restore := NAN
	var send_restore := NAN
	var monitor_restore := -1
	if _reaper_resource != "":
		check("opens the link to Reaper", DAW.use(ReaperBackend.new(), true, {
				"bridge_dir": _reaper_resource.path_join("Scripts/reaper3d_bridge_data")}))
		await _until(-0.5)
		restore = DAW.state.track(2).volume
		tempo_restore = DAW.state.tempo
		monitor_restore = DAW.state.track(3).monitor
		var first := _first_send(DAW.state)
		if not first.is_empty():
			send_restore = DAW.state.send(first[0], first[1]).volume
	else:
		var offline := OfflineBackend.new()
		offline.track_count = 20
		DAW.use(offline)
	Session.code = "AB12"
	Session.mix_source = func(): return MixSource.Tone.new()
	check("hosts", Session.host(port))
	check("and shares its mix's audio", Session.mix_feed.sending)
	_keep_publishing(Transform3D(Basis(Vector3.UP, 0.6), Vector3(1.2, 1.62, 0.4)), "MASTER  VOLUME")

	# Between the guest's wrong knock (0.3) and its right one (1.4), with room either side: two
	# processes started a moment apart do not share a clock to the millisecond.
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
	check("and the guest is listening to the mix", Session.mix_feed.listener_count() == 1)

	# Reach for the fader the guest is holding: the host's own hand is refused too.
	Session.claim_hold(KEY)
	await _until(4.0)
	check("the host is refused a control the guest holds",
			_refused.size() == 1 and _refused[0][0] == KEY and _refused[0][1] == guest_id)
	check("and the hold stays the guest's", Session.holder_of(KEY) == guest_id)

	await _until(6.0)
	check("the guest's release cleared the table", Session.holds.is_empty())
	Session.claim_hold(KEY)
	check("so the host can take it now", Session.holder_of(KEY) == 1)
	Session.release_hold(KEY)

	# The guest records a take against what it hears: see _guest_records.
	await _until(7.0)
	DAW.transport_record()
	await _until(11.8)
	DAW.transport_stop()
	await _until(13.0)
	_check_placed_take()

	await _until(13.4)
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
	await _until(14.4)


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
	var depth := DAW.state.undo_depth
	DAW.undo()
	await get_tree().create_timer(0.3).timeout
	var still := DAW.state.track(TAKE_TRACK).items.any(func(it): return it.name == "Grace take 1")
	check("and one undo takes it off again", not still)


func _guest(port: int) -> void:
	Session.local_name = "Grace"
	# On the host's own machine, which would ordinarily mean not listening: the host's speakers
	# are already in the room. Asked for here, because the probe is what is listening.
	Session.listen_choice = 1
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
	await _until(3.2)
	check("my grab is in the table", Session.holder_of(KEY) == Session.local_peer_id)
	check("my fader move came back from the host (%.4f)" % DAW.state.track(2).volume,
			absf(DAW.state.track(2).volume - 0.123) < 0.002)
	check("and so did my tempo (%.1f)" % DAW.state.tempo, absf(DAW.state.tempo - GUEST_TEMPO) < 0.05)
	check("and the click I switched on", DAW.state.metronome)
	check("and my input monitoring", DAW.state.track(3).monitor == DAW.MONITOR_AUTO)
	check("and my marker (%s)" % [DAW.state.markers.values()], _has_guest_mark(DAW.state))
	check("and my send level", not send.is_empty()
			and absf(DAW.state.send(send[0], send[1]).volume - GUEST_SEND) < 0.002)

	await _until(4.4)
	check("the host's attempt on my fader did not take it", Session.holder_of(KEY) == Session.local_peer_id)
	Session.release_hold(KEY)
	await _until(5.2)
	check("my release emptied the table", Session.holds.is_empty())

	await _until(6.8)
	var heard := Session.mix_feed.stats()
	print("audio: ", heard, " clicks ", Session.mix_feed.heard_clicks)
	check("the host's mix is reaching me", heard.get("hearing", false) and int(heard.get("packets", 0)) > 1000)
	check("loud enough to be the tone (%.3f)" % Session.mix_feed.heard_peak, Session.mix_feed.heard_peak > 0.15)
	var clicks: Array = Session.mix_feed.heard_clicks
	var steady := clicks.size() >= 3
	for i in range(1, clicks.size()):
		steady = steady and absi(int(clicks[i]) - int(clicks[i - 1]) - 48000) < 480
	check("its clicks a second apart, to within 10ms (%s)" % [clicks], steady)
	check("without running dry once it started (%d)" % int(heard.get("underruns", -1)),
			int(heard.get("underruns", 99)) <= 1)
	check("or losing a packet on loopback (%d)" % int(heard.get("lost", -1)), int(heard.get("lost", 99)) == 0)
	check("and close enough behind to play along to (%.1fms)" % float(heard.get("latency_ms", 999.0)),
			float(heard.get("latency_ms", 999.0)) < 30.0)

	await _guest_records()

	await _until(14.0)
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
	var timeout_at := _start + int((11.6 + _shift) * 1000.0)
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
	await _until(12.8)
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
