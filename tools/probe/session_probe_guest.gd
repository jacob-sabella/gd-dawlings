class_name SessionProbeGuest
extends RefCounted

## The guest's half of the probe: Reaper's render levels, the take notes, undoing takes and the guest's whole timeline,
## with its first moves of takes, stage, clap, rope, lane and snap.
## Moved out of `tools/probe/session_probe.gd` without change of behaviour; the state stays on the probe node, which keeps a one-line delegate for each name another file or a string reaches.

var probe: SessionProbe


func _init(of: SessionProbe) -> void:
	probe = of


## One render of the loop with stems: RENDER_TRACK's stem's level (dB RMS) in each second of it, and
## the folder the render went to (emptied).
func _reaper_render_levels() -> Array:
	var done: Array = []
	var on_done := func(files, problems): done.append([files, problems])
	DAW.render_finished.connect(on_done, probe.CONNECT_ONE_SHOT)
	DAW.render(true)
	var began := Time.get_ticks_msec()
	while done.is_empty() and Time.get_ticks_msec() - began < 8000:
		await probe.get_tree().process_frame
	if done.is_empty():
		DAW.render_finished.disconnect(on_done)
		return []
	var files: PackedStringArray = done[0][0]
	var want := " - %s.wav" % DAW.state.track(SessionProbe.RENDER_TRACK).name
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
	for it in DAW.state.track(SessionProbe.TAKE_TRACK).items:
		if it.name == "Grace take 1":
			var notes := MidiTake.unpack_relative(it.notes, it.start)
			notes.sort_custom(func(a, b): return a[0] < b[0] if a[2] == b[2] else a[2] < b[2])
			return notes
	return []


func _undo_takes() -> void:
	DAW.undo()
	DAW.undo()
	await probe.get_tree().create_timer(0.3).timeout
	var midi := DAW.state.track(SessionProbe.TAKE_TRACK).items.any(func(it): return it.name == "Grace take 1")
	var taken: String = probe._audio_placed.get("name", "-")
	var audio := DAW.state.track(SessionProbe.AUDIO_TRACK).items.any(func(it): return it.name == taken)
	probe.check("and an undo each takes them off again", not midi and not audio)


func _guest(port: int) -> void:
	Session.local_name = "Grace"
	# On the host's own machine, which would ordinarily mean not listening: the host's speakers
	# are already in the room. Asked for here, because the probe is what is listening.
	Session.listen_choice = 1
	Session.room_changed.connect(func(): probe._rooms_heard += 1)
	Session.item_used.connect(func(item: StringName, down: bool, from: int, take: int):
		probe._uses.append([item, down, from])
		probe._use_takes.append(take))
	Session.note_played.connect(probe.room_checks._on_note_played)
	Session.item_hit.connect(func(item: StringName, velocity: int, from: int, song: float, snap: bool, take: int, zone: StringName):
		probe._item_hits.append([item, velocity, from, song, snap, take, zone]))
	await probe.item_checks._until(0.3)
	await probe.hosting._join(port, "XX99")
	await probe.item_checks._until(1.4)
	probe.check("the wrong code is turned away (%s)" % [probe._notices], probe._notices.has("That is not Ada's code."))
	probe.check("back on my own after it", Session.role == Session.Role.SOLO)
	# Read across a room and typed in a hurry: spaces and case are not the code.
	probe.check("joins", await probe.hosting._join(port, "ab 12"))
	if not probe._noray.is_empty():
		var want := "relayed" if probe._noray == "relay" else "direct"
		probe.check("by its code, %s (%s)" % [want, Session.link_kind], Session.link_kind == want)
	probe.check("as a guest that never opens the DAW", not Session.is_authority())
	probe.room_checks._keep_publishing(Transform3D(Basis.IDENTITY, Vector3(-0.8, 1.5, 0.9)), "")

	await probe.item_checks._until(2.4)
	probe.check("the roster arrived with the host on it", Session.name_of(1) == "Ada")
	probe.check("and me under my name", Session.name_of(Session.local_peer_id) == "Grace")
	probe.check("two in the room", Session.participants.size() == 2)
	probe.check("the snapshot arrived: %d tracks (%d)" % [probe._expect_tracks, DAW.state.tracks.size()],
			DAW.state.tracks.size() == probe._expect_tracks)
	var host = Session.participants.get(1)
	probe.check("the host's head has been heard", host != null and host.head.origin.is_equal_approx(
			Vector3(1.2, 1.62, 0.4)))
	probe.check("and what it is pointing at", host != null and host.pointing_at == "MASTER  VOLUME")
	probe.check("told who I joined", probe._notices.has("Joined Ada's session."))
	probe.check("the host's room came in with me (%s)" % [Session.room], probe._rooms_heard == 1
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
	DAW.set_tempo(SessionProbe.GUEST_TEMPO)
	DAW.set_metronome(true)
	DAW.add_marker(SessionProbe.GUEST_MARK, "GUEST")
	DAW.set_track_monitor(3, DAW.MONITOR_AUTO)
	var send := SessionProbeRoom._first_send(DAW.state)
	probe.check("the snapshot carried a send to turn (%s)" % [send], not send.is_empty())
	if not send.is_empty():
		DAW.set_send_volume(send[0], send[1], SessionProbe.GUEST_SEND)
	probe.room_checks._press_a_bay_pin()
	Session.claim_hold(SessionProbe.KEY)
	Session.claim_hold(SessionProbe.DUCK)
	Session.send_carry(&"duck", SessionProbe.DUCK_AT)
	Session.send_item_use(&"duck", true)
	await probe.item_checks._until(3.2)
	probe.check("my grab is in the table", Session.holder_of(SessionProbe.KEY) == Session.local_peer_id)
	probe.check("my fader move came back from the host (%.4f)" % DAW.state.track(2).volume,
			absf(DAW.state.track(2).volume - 0.123) < 0.002)
	probe.check("and so did my tempo (%.1f)" % DAW.state.tempo, absf(DAW.state.tempo - SessionProbe.GUEST_TEMPO) < 0.05)
	probe.check("and the click I switched on", DAW.state.metronome)
	probe.check("and my input monitoring", DAW.state.track(3).monitor == DAW.MONITOR_AUTO)
	probe.check("and my marker (%s)" % [DAW.state.markers.values()], SessionProbeItems._has_guest_mark(DAW.state))
	probe.check("the host answered all four of my asks, the refused one too (%s)" % [Session.room.get("acks")],
			int((Session.room.get("acks", {}) as Dictionary).get(Session.local_peer_id, 0)) == 4)
	probe.check("the stand I asked for is in the host's room now", probe._rooms_heard >= 2
			and Session.room.get("tablets", {}).has(&"tablet_2") and Session.room.get("venue") == &"grid")
	probe.check("and my send level", not send.is_empty()
			and absf(DAW.state.send(send[0], send[1]).volume - SessionProbe.GUEST_SEND) < 0.002)
	if probe._bay != null:
		probe._bay._process(0.0)
		var pin := probe._bay.pin_for(probe._bay_pin[0], probe._bay_pin[1]) if probe._bay_pin.size() == 2 else null
		probe.check("the pin I pressed on the bay came back seated from the host (%s)" % [probe._bay_pin],
				pin != null and pin.cell().get("on", false) and not pin.cell().get("pending", false))
		probe._bay.queue_free()
		probe._bay = null

	await probe.item_checks._until(4.4)
	probe.check("the host's attempt on my fader did not take it", Session.holder_of(SessionProbe.KEY) == Session.local_peer_id)
	probe.check("the host's squeeze reached me (%s)" % [probe._uses], probe._uses == [[&"duck", false, 1]])
	Session.release_hold(SessionProbe.KEY)
	probe.check("the host has the plane", Session.holder_of(SessionProbe.PLANE) == 1)
	Session.take_hold(SessionProbe.PLANE)
	# Thrown -- one launch, reliably, as vectors -- then put down and let go: the host hears
	# where it is before it hears the hand is empty.
	Session.ask_room(&"throw_item", [&"duck", Vector3(0.4, 1.2, 1.5), Vector3(0.0, 2.0, 3.5), Vector3(-6.0, 0.0, 0.0)])
	Session.ask_room(&"put_item", [&"duck", 0.4, 1.9, 0.2])
	Session.release_hold(SessionProbe.DUCK)
	# A plug off my tablet into the desk's MIX send, for my headphones.
	Session.ask_room(&"patch", [1, &"mix"])
	# And a key, as played, for anyone patched into my keys.
	Session.guest_midi.note_on(60, 100)
	Session.guest_midi.note_off(60)
	# And one from my fingertips, which says so.
	Session.guest_midi.note_on(62, 90, 0, 0.0, false, &"fingertips")
	Session.guest_midi.note_off(62, 0, 0.0, false, &"fingertips")
	await probe.item_checks._until(5.2)
	probe.check("my releases left only the plane I took from the host's hand (%s)" % [Session.holds],
			Session.holds == {SessionProbe.PLANE: Session.local_peer_id})
	Session.release_hold(SessionProbe.PLANE)
	probe.check("the host's keys reached me as played (%s)" % [probe._notes],
			probe._notes == [[Session.Note.ON, 67, 80, 1], [Session.Note.OFF, 67, 0, 1]])
	probe.check("and the host's fingertips note, saying it was the fingertips' (%s)" % [probe._sourced],
			probe._sourced == [[Session.Note.ON, 71, 1, &"fingertips"], [Session.Note.OFF, 71, 1, &"fingertips"]])
	probe.check("and the host answered my throw, put-down and patch", int((Session.room.get("acks", {}) as Dictionary)
			.get(Session.local_peer_id, 0)) == 7)

	await probe.item_checks._until(6.8)
	var heard := Session.mix_feed.stats()
	print("audio: ", heard, " clicks ", Session.mix_feed.heard_clicks, " route ", Session.mix_route)
	if not probe._noray.is_empty():
		var by := "relayed" if probe._noray == "relay" else "direct"
		probe.check("the mix came on its own socket, %s through noray (%s)" % [by, Session.mix_route], Session.mix_route == by)
	probe.check("the host's mix is reaching me", heard.get("hearing", false) and int(heard.get("packets", 0)) > 1000)
	probe.check("loud enough to be the music (%.3f)" % Session.mix_feed.heard_peak, Session.mix_feed.heard_peak > 0.15)
	if not probe._built_in:
		var clicks: Array = Session.mix_feed.heard_clicks
		var steady := clicks.size() >= 3
		for i in range(1, clicks.size()):
			steady = steady and absi(int(clicks[i]) - int(clicks[i - 1]) - 48000) < 480
		probe.check("its clicks a second apart, to within 10ms (%s)" % [clicks], steady)
	probe.check("without running dry once it started (%d)" % int(heard.get("underruns", -1)),
			int(heard.get("underruns", 99)) <= 1)
	probe.check("or losing a packet on loopback (%d)" % int(heard.get("lost", -1)), int(heard.get("lost", 99)) == 0)
	# A real mix is captured off the host's master bus a driver block at a time (about 15ms on
	# Pulse), which the test tone, made the moment it is asked for, never pays.
	var bar := 45.0 if probe._built_in else 30.0
	probe.check("and close enough behind to play along to (%.1fms, under %.0f)" % [float(heard.get("latency_ms", 999.0)), bar],
			float(heard.get("latency_ms", 999.0)) < bar)

	if not probe._built_in:
		var ga := Session.guest_audio
		ga.make_source = func() -> MixSource: return SessionProbe.Clapper.new()
		ga.target_track = SessionProbe.AUDIO_TRACK
		ga.record_with_host = true
		await _guest_records()
		print("audio drift found: %.0f ppm" % ga.drift_ppm())
		probe.check("my recording was sent when I heard the recording stop (%s)" % [ga.last_take],
				not ga.is_recording() and float(ga.last_take.get("seconds", 0.0)) > 3.0)
		probe.check("the host told me where my recording went",
				probe._notices.any(func(t): return t.begins_with("Your recording is on")))
		var mine: Array = DAW.state.track(SessionProbe.AUDIO_TRACK).items.filter(func(it): return it.source != "")
		probe.check("and it came back to me with its waveform",
				mine.size() == 1 and mine[0].peaks.size() > 100)
		ga.record_with_host = false
		# After the host has undone the takes (by 14.9 s, or 35.6 s on Reaper): an undo then
		# would take these off.
		await probe.item_checks._until(36.4 if probe._reaper_host else 15.2)
		await probe.host_render._send_files()
	else:
		await probe.item_checks._until(13.8)
		probe.check("the host's newly opened project reached me whole (%d tracks, '%s')"
				% [DAW.state.tracks.size(), DAW.state.track(1).name],
				DAW.state.tracks.size() == 7 and DAW.state.track(1).name == "Opened")
		Session.mix_feed.heard_peak = 0.0
		# Save, pressed here: the host's file, saved where the host keeps it, and the whole
		# room told.
		DAW.save_project()
		await probe.item_checks._until(14.3)
		probe.check("and I know what its second track records from (%s)" % DAW.state.input_name(DAW.state.input_of(2)),
				DAW.state.input_of(2) == "audio:" and DAW.state.input_name("audio:") == "the default microphone")
		probe.check("and I hear it play from its own files (%.3f)" % Session.mix_feed.heard_peak,
				Session.mix_feed.heard_peak > 0.15)
		probe.check("I saved the host's project, and was told (%s)" % [probe._notices],
				probe._notices.has("Grace saved the project as dawlings_probe_%d.dawproject." % probe._port))
		probe.check("and I know its name and file, not where it is (%s, %s)" % [DAW.project_title(), DAW.project_file_name()],
				not DAW.project_title().is_empty() and DAW.project_file_name() == "dawlings_probe_%d.dawproject" % probe._port)

	await probe.item_checks._until(40.0)
	probe.room_checks._make_room()
	await probe.item_checks._until(44.0)
	probe._room.played.connect(func(item: InstrumentItem, velocity: int, _struck: bool, at: float, zone: StringName) -> void:
		Session.send_item_hit(item.id, velocity, at, false, -1, zone))
	# My cowbell, on its shelf, into track 3: asked as the studio asks (Jacks).
	await probe.item_checks._until(44.5)
	Session.ask_room(&"plug", [&"cowbell", &"track_3"])

	# The host's room says where my jack goes.
	await probe.item_checks._until(47.5)
	var jacks := Jacks.new()
	probe.add_child(jacks)
	jacks.set_patch(Session.room.get("jacks", {}))
	probe.check("my plug is in the host's room (%s)" % [Session.room.get("jacks")],
			jacks.sink_of(&"cowbell") == &"track_3" and jacks.patch.size() == 1)
	jacks.free()

	# Cables (docs/spatial_loop.md slice 6): my cowbell in my hand into the host's keys; my jacks follow the host's room, as the studio's do.
	probe.item_checks._wear_jacks()
	probe._jacks.set_patch(Session.room.get("jacks", {}))
	Session.room_changed.connect(func() -> void: probe._jacks.set_patch(Session.room.get("jacks", {})))
	await probe.item_checks._until(48.0)
	var cowbell := probe._room.items.get(&"cowbell") as InstrumentItem
	Session.claim_hold(cowbell.network_key())
	await probe.item_checks._until(48.3)
	Session.ask_room(&"plug", [&"cowbell", Jack.player_sink(1)])
	# Four hits, as the studio sends them (Jacks.hit), each with the song position it was played to.
	await probe.item_checks._until(48.8)
	probe.check("the host's room has my cowbell into the host (%s)" % [probe._jacks.patch],
			probe._jacks.sink_of(&"cowbell") == Jack.player_sink(1))
	for i in 4:
		probe._jacks.hit(cowbell, 90, probe.item_checks._ring_song() + 1.0 + i * 0.1)
	# The fifths wheel's SET, as the wheel sends a guest's (docs/spatial_loop.md slice 9): a room
	# ask carrying the bar I chose.
	await probe.item_checks._until(53.7)
	Session.ask_room(FifthsWheel.VERB, [SessionProbe.WHEEL_BAR, SessionProbe.WHEEL_INSIDE])
	# And to the wheel, in a headset: the host sees my ghost there by 55.
	await probe.item_checks._until(53.8)
	await probe.room_checks._travel_to_the_wheel()

	# While the session is still on: once the host leaves, my own project is back.
	await probe.item_checks._until(54.5)
	if probe._reaper_host:
		probe.check("I know the host's Reaper project by its name and file (%s, %s)" % [DAW.project_title(), DAW.project_file_name()],
				DAW.project_title() == "rig" and DAW.project_file_name() == "rig.RPP")
	# One undo step per gesture (slice 12): pan and volume dragged at once inside an edit, as a
	# control that edits as one sends them, frame by frame. The host moves a fader of its own
	# meanwhile, at 54.7.
	var steps_before: int = DAW.state.undo_depth
	await probe.item_checks._until(54.55)
	DAW.open_edit(SessionProbe.EDIT_NAME)
	var from_pan: float = DAW.state.track(SessionProbe.EDIT_TRACK).pan
	var from_volume: float = DAW.state.track(SessionProbe.EDIT_TRACK).volume
	for i in 30:
		var f := (i + 1) / 30.0
		DAW.set_track_pan(SessionProbe.EDIT_TRACK, lerpf(from_pan, SessionProbe.EDIT_PAN, f))
		DAW.set_track_volume(SessionProbe.EDIT_TRACK, lerpf(from_volume, SessionProbe.EDIT_VOLUME, f))
		await probe.get_tree().create_timer(0.01).timeout
	DAW.close_edit()
	await probe.item_checks._until(55.0)
	probe.room_checks._check_wheel("the host's")
	await probe.item_checks._until(55.1)
	if not probe._reaper_host:
		probe.check("my drag is one step in the host's history, its own fader another (%d after %d: %s)" % [
				DAW.state.undo_depth, steps_before, DAW.state.undo_names.slice(steps_before)],
				DAW.state.undo_depth == steps_before + 2 and DAW.state.undo_names.slice(steps_before).count(SessionProbe.EDIT_NAME) == 1)
	# Controls beside the keys (slice 13): the host's keys played here, as a plug in them would;
	# a controller the host must refuse; and the host's bend, heard while its note is down and
	# rested at its note-off.
	var their := TheirKeys.new()
	their.name = "TheirKeys"
	probe.add_child(their)
	their.set_players([1])
	Session.note_played.connect(their.play)
	Session.control_played.connect(their.control)
	await probe.item_checks._until(55.27)
	Session.send_control(7, 100)
	await probe.item_checks._until(55.37)
	var synth: MonitorSynth = their.synths[1]
	var down: KeysDown = their._down.get(1)
	probe.check("the host's bend during its held note is heard on my TheirKeys (%s)" % [synth.controls],
			int(synth.controls.get(DawKitClip.PITCH_BEND, 0)) == SessionProbe.BEND_VALUE and down != null
			and down.is_down(SessionProbe.BEND_PITCH))
	await probe.item_checks._until(55.55)
	probe.check("and rests at its note-off (%s)" % [synth.controls], int(synth.controls.get(DawKitClip.PITCH_BEND, -1)) == 0
			and down != null and down.is_empty())
	Session.note_played.disconnect(their.play)
	Session.control_played.disconnect(their.control)
	their.queue_free()
	await _bend_into_a_take()
	await _snap_into_a_take()
	await _place_on_the_stage()
	await _clap_to_mute()
	await _tie_a_rope()
	await _write_a_lane()
	await probe.item_checks._pull_a_cassette()
	await probe.item_checks._paste_a_cassette()
	await probe.room_checks._hear_a_cassette()
	await probe.room_checks._sample_a_squeeze()
	await probe.room_checks._spin_the_platter()
	await probe.room_checks._crank_the_history()
	await probe.room_checks._rearrange_the_sections()
	await probe.item_checks._drive_their_chord_hand()
	await probe.item_checks._point_and_note()
	await probe.item_checks._hear_the_spectra()
	await probe.item_checks._carve_the_clash()
	await probe.item_checks._strike_the_drum()
	await probe.item_checks._press_the_weather()
	await probe.item_checks._loop_a_layer()
	await probe.item_checks._tap_the_lyrics()
	await probe.item_checks._until(64.88)
	print("notices: ", probe._notices)
	probe.check("the host's goodbye arrived", probe._notices.any(func(t): return t.contains("ended the session")))
	probe.check("and I am back on my own", Session.role == Session.Role.SOLO)
	probe.check("and no longer listening", not Session.mix_feed.listening)
	probe.check("with a mix of my own again", DAW.is_live() and DAW.state.tracks.size() > 0)


## Controls in takes (slice 14): a note held from 56.0 to 56.3 and bent at 56.2 by a keyboard's
## pitch wheel (an InputEventMIDI, the door a real one comes in by), recorded onto TAKE_TRACK at
## BENT_SONG to a clock of my own, and sent to the host when that clock stops recording. Where the
## bend was taken down is written for the host to look for.
func _bend_into_a_take() -> void:
	var gm := Session.guest_midi
	await probe.item_checks._until(55.9)
	for pitch in gm.held.keys():
		gm.note_off(pitch)
	gm.target_track = SessionProbe.TAKE_TRACK
	gm.heard_source = probe.item_checks._given_clock(SessionProbe.BENT_SONG, true)
	await probe.item_checks._until(56.0)
	var key := InputEventMIDI.new()
	key.message = MIDI_MESSAGE_NOTE_ON
	key.pitch = SessionProbe.BENT_PITCH
	key.velocity = 100
	gm._input(key)
	probe.check("my held note is in a take of my own", gm.is_recording() and gm.held.has(SessionProbe.BENT_PITCH))
	await probe.item_checks._until(56.2)
	var wheel := InputEventMIDI.new()
	wheel.message = MIDI_MESSAGE_PITCH_BEND
	wheel.pitch = 8192 + SessionProbe.BEND_VALUE
	var at := gm.stamp()
	gm._input(wheel)
	probe.check("my keyboard's wheel bends my keys (%s)" % [gm.controls], int(gm.controls.get(DawKitClip.PITCH_BEND, 0)) == SessionProbe.BEND_VALUE)
	var file := FileAccess.open("/tmp/r3d_probe_bend_%d.json" % probe._port, FileAccess.WRITE)
	file.store_string(JSON.stringify({"at": at, "value": SessionProbe.BEND_VALUE}))
	file.close()
	await probe.item_checks._until(56.3)
	key.message = MIDI_MESSAGE_NOTE_OFF
	key.velocity = 0
	gm._input(key)
	await probe.item_checks._until(56.4)
	gm.heard_source = probe.item_checks._given_clock(SessionProbe.BENT_SONG + 0.6, false)
	await probe.item_checks._until(56.5)
	probe.check("and the take went to the host with the bend and its rest (%s)" % [gm.last_take],
			not gm.is_recording() and gm.last_take.get("controls", 0) == 2)
	gm.heard_source = Callable()
	gm.target_track = 0


## The stage table (slice 18): a table of my own over the host's mix, and STAGE_TRACK's voice on it
## taken by a hand at 57.7 and placed at STAGE_PAN and STAGE_DB in fifteen moves, as a drag sends
## them: pan and volume inside one edit, intents the host carries out.
func _place_on_the_stage() -> void:
	await probe.item_checks._until(57.7)
	var table := StageTable.new()
	table.name = "StageTable"
	StageLink.wire(table)
	probe.add_child(table)
	table._process(0.0)
	var voice: StageVoice = table.voices.get(SessionProbe.STAGE_TRACK)
	probe.check("my stage table stands the host's track %d as a voice (%s)" % [SessionProbe.STAGE_TRACK, table.voices.keys()], voice != null)
	if voice == null:
		table.queue_free()
		return
	var hand := Node.new()
	probe.add_child(hand)
	var from := voice.position
	var to := StageTable.spot_of(SessionProbe.STAGE_PAN, SessionProbe.STAGE_DB)
	voice.grab_begin(hand, table.to_global(from))
	for i in 15:
		voice.grab_move(hand, table.to_global(from.lerp(to, (i + 1) / 15.0)))
		await probe.get_tree().create_timer(0.01).timeout
	voice.grab_end(hand)
	probe.check("and my hand put it where I meant (%s)" % voice.readout(), voice.position.is_equal_approx(to))
	hand.queue_free()
	table.queue_free()


## Clap to mute (slice 19): a clap at 58.2, my palms meeting fast and parting at once, while
## pointing at CLAP_TRACK: a latch, which asks the host to toggle its mute.
func _clap_to_mute() -> void:
	await probe.item_checks._until(58.2)
	var clap := Clap.new()
	clap.target = func() -> int: return SessionProbe.CLAP_TRACK
	var was := DAW.state.track(SessionProbe.CLAP_TRACK).mute
	var dt := 1.0 / 60.0
	for gap in [0.2, 0.17, 0.14, 0.11, 0.08, 0.05, 0.03]:
		clap.step(gap <= HandPose.PALMS_TOUCH, gap, dt)
	probe.check("my palms met fast at track %d" % SessionProbe.CLAP_TRACK, clap.pressed and clap.track == SessionProbe.CLAP_TRACK)
	for i in 4:
		clap.step(true, 0.02, dt)
	clap.step(false, 0.15, dt)
	probe.check("and parted at once: a latch", not clap.pressed and clap.latches(5 * dt))
	await probe.item_checks._until(58.35)
	probe.check("which the host's mix gives back to me (%s, was %s)" % [DAW.state.track(SessionProbe.CLAP_TRACK).mute, was],
			DAW.state.track(SessionProbe.CLAP_TRACK).mute != was)


## Sidechain as a rope (slice 20): a table of my own over the host's mix at 58.5, and a rope dragged
## from ROPE_FROM's knot to ROPE_TO's voice, as a hand drags it: the compressor (if the track has
## none) and the key send, one edit of intents the host carries out. By 58.6 the host's mix gives
## the key send back to me.
func _tie_a_rope() -> void:
	await probe.item_checks._until(58.5)
	var table := StageTable.new()
	table.name = "RopeTable"
	StageLink.wire(table)
	probe.add_child(table)
	table._process(0.0)
	var from: StageVoice = table.voices.get(SessionProbe.ROPE_FROM)
	probe.check("my stage table stands the host's tracks %d and %d (%s)" % [SessionProbe.ROPE_FROM, SessionProbe.ROPE_TO, table.voices.keys()],
			from != null and table.voices.has(SessionProbe.ROPE_TO))
	if from == null or not table.voices.has(SessionProbe.ROPE_TO):
		table.queue_free()
		return
	var hand := Node.new()
	probe.add_child(hand)
	var a := table.knot_point(SessionProbe.ROPE_FROM)
	var b := table.knot_point(SessionProbe.ROPE_TO)
	from.knot.grab_begin(hand, table.to_global(a))
	for i in 10:
		from.knot.grab_move(hand, table.to_global(a.lerp(Vector3(b.x, a.y, b.z), (i + 1) / 10.0)))
	probe.check("my rope is over track %d's voice as I let go" % SessionProbe.ROPE_TO, table.drop_target(SessionProbe.ROPE_FROM, Vector2(b.x, b.z)) == SessionProbe.ROPE_TO)
	from.knot.grab_end(hand)
	probe.check("and asks for the rope's row", table.ropes.has(Sidechain.rope_key(SessionProbe.ROPE_FROM, SessionProbe.ROPE_TO)))
	await probe.item_checks._until(58.6)
	probe.check("which the host's mix gives back to me as a key send (%d)" % Sidechain.key_send(SessionProbe.ROPE_FROM, SessionProbe.ROPE_TO),
			Sidechain.key_send(SessionProbe.ROPE_FROM, SessionProbe.ROPE_TO) > 0)
	hand.queue_free()
	table.queue_free()


## Automation by gesture (slice 22): at 58.74 a write bead of my own over a fader of BEAD_TRACK on the
## host's mix, pulled as a hand pulls it and raised 0.3 m over BEAD_SECONDS of a clock of my own from
## BEAD_SONG, the song not looping: the hold, an edit of sets, the pass as the whole lane and the
## let-go, intents the host carries out. By 58.81 the host's mix gives the lane back to me.
func _write_a_lane() -> void:
	await probe.item_checks._until(58.74)
	var fader := Fader.new()
	fader.track_index = SessionProbe.BEAD_TRACK
	fader.automates = func() -> Array: return [SessionProbe.BEAD_TRACK, "volume"]
	probe.add_child(fader)
	var now := {"seconds": SessionProbe.BEAD_SONG, "playing": true, "valid": true}
	var bead := WriteBead.new()
	probe.add_child(bead)
	bead.control = fader
	bead.heard_source = func() -> Dictionary: return now
	var hand := Node.new()
	probe.add_child(hand)
	probe.check("my bead pass is not looped (the host's song is not looping)", not DAW.state.looping)
	bead.grab_begin(hand, Vector3(0, 1.0, 0))
	var ticks := roundi(SessionProbe.BEAD_SECONDS * 60.0)
	for i in ticks:
		now["seconds"] = SessionProbe.BEAD_SONG + (i + 1) / 60.0
		bead.grab_move(hand, Vector3(0, 1.0 + 0.3 * float(i + 1) / ticks, 0))
		bead.follow(now)
	bead.grab_end(hand)
	probe.check("and wrote one pass", bead.passes_written == 1)
	await probe.item_checks._until(58.81)
	var lane := WriteBead.lane_now(SessionProbe.BEAD_TRACK, "volume")
	var inside := lane.filter(func(pt): return absf(float(pt[0]) - SessionProbe.BEAD_SONG - SessionProbe.BEAD_SECONDS * 0.5) <= SessionProbe.BEAD_SECONDS * 0.5 + 0.0001)
	probe.check("which the host's mix gives back to me as the lane (%d points)" % inside.size(),
			inside.size() == roundi(SessionProbe.BEAD_SECONDS / WriteBead.POINT_SECONDS) + 1)
	hand.queue_free()
	bead.queue_free()
	fader.queue_free()


## Snapped gently (slice 17): two cowbell hits taken down at 57.42 by a HitRecorder of my own onto
## TAKE_TRACK at SNAP_SONG, to a clock of my own, as the studio's takes them (`hit`'s `snap`, the
## player's flag): one SNAP_EARLY before a sixteenth with snap on, one SNAP_EARLY before the next
## with it off. Each goes to the room too, with its flag and its Foley take, as the studio sends a
## hit. Sent to the host when the clock stops recording; where each was played, and where the
## snapped one is to land, is written for the host to look for.
func _snap_into_a_take() -> void:
	await probe.item_checks._until(57.42)
	var rec := HitRecorder.new()
	rec.name = "SnapRecorder"
	probe.add_child(rec)
	rec.heard_source = probe.item_checks._given_clock(SessionProbe.SNAP_SONG, true)
	var cowbell := probe._room.items.get(&"cowbell") as InstrumentItem
	var first := HitRecorder.nearest_sixteenth(SessionProbe.SNAP_SONG + 0.2, DAW.state) - SessionProbe.SNAP_EARLY
	var second := HitRecorder.nearest_sixteenth(first + 0.3, DAW.state) - SessionProbe.SNAP_EARLY
	rec.hit(cowbell, 90, first, SessionProbe.TAKE_TRACK, 1)
	rec.hit(cowbell, 90, second, SessionProbe.TAKE_TRACK, 0)
	Session.send_item_hit(cowbell.id, 90, first, true, 5)
	Session.send_item_hit(cowbell.id, 90, second, false, 6)
	var file := FileAccess.open("/tmp/r3d_probe_snap_%d.json" % probe._port, FileAccess.WRITE)
	file.store_string(JSON.stringify({"first": first, "second": second,
			"snapped": HitRecorder.snapped_at(first, DAW.state)}))
	file.close()
	probe.check("my snapped hit is half way to its sixteenth in my take, my other where I played it",
			is_equal_approx(HitRecorder.snapped_at(first, DAW.state), first + SessionProbe.SNAP_EARLY * HitRecorder.SNAP_PULL)
			and rec.jacked_tracks() == [SessionProbe.TAKE_TRACK])
	await probe.item_checks._until(57.46)
	rec.heard_source = probe.item_checks._given_clock(SessionProbe.SNAP_SONG + 1.0, false)
	await probe.item_checks._until(57.5)
	probe.check("and the take went to the host (%s)" % [rec.last_take],
			int(rec.last_take.get("notes", 0)) == 2 and int(rec.last_take.get("track", 0)) == SessionProbe.TAKE_TRACK)
	rec.queue_free()


## Plays a take into track TAKE_TRACK while the host records, through the same door a MIDI
## keyboard uses (InputEventMIDI), timed against the clicks of the host's test tone: it clicks
## on every whole second of the song, so a click heard at frame n says song second S was at the
## "speaker" at the moment the drain took frame n. A note played t seconds after that click was
## played at S + t, and that is where it has to land.
func _guest_records() -> void:
	var gm := Session.guest_midi
	gm.target_track = SessionProbe.TAKE_TRACK
	var changed_usec := [0]
	gm.changed.connect(func(): changed_usec[0] = Time.get_ticks_usec())
	var expected: Array = []
	var ons := {}
	var seen := Session.mix_feed.clicks_heard().size()
	var clicks_used := 0
	var settled := 0
	var ref_usec := 0
	var ref_second := 0.0
	var timeout_at := probe._start + int((12.6 + probe._shift) * 1000.0)
	var pending_72 := 0
	while Time.get_ticks_msec() < timeout_at and clicks_used < 3 or pending_72 > 0:
		await probe.get_tree().process_frame
		if Time.get_ticks_msec() > timeout_at + 500:
			break
		var clicks: Array = Session.mix_feed.clicks_heard()
		var now := Time.get_ticks_usec()
		if pending_72 == 1 and now - ref_usec >= 250000 and clicks_used >= 1:
			pending_72 = 2
			var t := await probe.room_checks._play(true, 72, 70, changed_usec)
			ons[72] = ref_second + (t - ref_usec) / 1000000.0
		elif pending_72 == 2 and now - ref_usec >= 500000:
			pending_72 = 0
			var t := await probe.room_checks._play(false, 72, 0, changed_usec)
			expected.append([72, ons[72], ref_second + (t - ref_usec) / 1000000.0])
		if clicks.size() <= seen:
			continue
		seen = clicks.size()
		if not gm.is_recording() or clicks_used >= 3:
			continue
		print("take: click at %.2fs (settled %d, used %d)" % [(Time.get_ticks_msec() - probe._start) / 1000.0 - probe._shift, settled, clicks_used])
		if settled < SessionProbe.SETTLE_CLICKS:
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
				ons[60] = at.call(await probe.room_checks._play(true, 60, 100, changed_usec))
				pending_72 = 1
			2:
				var t := await probe.room_checks._play(false, 60, 0, changed_usec)
				expected.append([60, ons[60], at.call(t)])
				ons[64] = at.call(await probe.room_checks._play(true, 64, 90, changed_usec))
			3:
				ons[67] = at.call(await probe.room_checks._play(true, 67, 110, changed_usec))
				var t := await probe.room_checks._play(false, 64, 0, changed_usec)
				expected.append([64, ons[64], at.call(t)])
				expected.append([67, ons[67], null])
	probe.check("the take ran while the host recorded, with notes played on three clicks (%d)" % clicks_used,
			clicks_used == 3 and gm.is_recording())
	var file := FileAccess.open("/tmp/r3d_probe_take_%d.json" % probe._port, FileAccess.WRITE)
	file.store_string(JSON.stringify({"notes": expected, "hanging": 67}))
	file.close()
	await probe.item_checks._until(13.8)
	probe.check("the take was sent when I heard the recording stop", not gm.is_recording()
			and gm.last_take.get("notes", 0) == 4)
	probe.check("the host told me where it went (%s)" % [probe._notices],
			probe._notices.any(func(t): return t.begins_with("Your take is on")))
	var back: Array = DAW.state.track(SessionProbe.TAKE_TRACK).items.filter(func(it): return it.name == "Grace take 1")
	probe.check("and it came back to me, notes and all",
			back.size() == 1 and MidiTake.unpack_relative(back[0].notes, back[0].start).size() == 4)
