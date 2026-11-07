class_name SessionProbeHost
extends RefCounted

## The host's half of the probe: the join code and epoch, and the whole timeline the host walks through, with the first
## checks on the rope and the written lane.
## Moved out of `tools/probe/session_probe.gd` without change of behaviour; the state stays on the probe node, which keeps a one-line delegate for each name another file or a string reaches.

var probe: SessionProbe


func _init(of: SessionProbe) -> void:
	probe = of


## Where the host writes its join code, for a guest by code (PROBE_NORAY).
func _code_path() -> String:
	return "user://session_probe_%d.code" % probe._port


## Guest: the host's join code, once it has written one this run.
func _hosts_code() -> String:
	var mine := Time.get_unix_time_from_system()
	while Time.get_unix_time_from_system() - mine < 5.0:
		if FileAccess.file_exists(_code_path()) \
				and FileAccess.get_modified_time(_code_path()) >= int(mine) - 10:
			var text := FileAccess.get_file_as_string(_code_path()).strip_edges()
			if not text.is_empty():
				return text
		await probe.get_tree().process_frame
	return ""


## Guest: in, by the code or by the address, and connected (or turned away) before going on.
func _join(port: int, door: String) -> bool:
	if probe._noray.is_empty():
		return Session.join("127.0.0.1", port, door)
	var code := await _hosts_code()
	if not Session.join_by_code(NorayLink.spoken(code).to_lower(), door):
		return false
	while not Session.link_phase.is_empty():
		await probe.get_tree().process_frame
	return Session.role == Session.Role.GUEST or probe._notices.any(func(n: String): return n.contains("code"))


## Where the host writes when its timeline began, for the guest's to begin with it.
func _epoch_path() -> String:
	return "user://session_probe_%d.epoch" % probe._port


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
			probe._start = Time.get_ticks_msec() - int((Time.get_unix_time_from_system() - float(text)) * 1000.0)
			return
		await probe.get_tree().process_frame
	print("the host's epoch never came: my timeline is my own")


func _host(port: int) -> void:
	Session.audio_take_placed.connect(func(info: Dictionary):
		probe._audio_placed = info
		probe._placed_all.append(info))
	Session.local_name = "Ada"
	var restore := NAN
	var tempo_restore := NAN
	var send_restore := NAN
	var monitor_restore := -1
	if probe._reaper_resource != "":
		probe.check("opens the link to Reaper", DAW.use(ReaperBackend.new(), true, {
				"bridge_dir": probe._reaper_resource.path_join("Scripts/dawlings_bridge_data")}))
		await probe.item_checks._until(-0.5)
		restore = DAW.state.track(2).volume
		tempo_restore = DAW.state.tempo
		monitor_restore = DAW.state.track(3).monitor
		var first := SessionProbeRoom._first_send(DAW.state)
		if not first.is_empty():
			send_restore = DAW.state.send(first[0], first[1]).volume
	elif probe._built_in:
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
	if probe._built_in:
		Session.mix_source = func(): return (DAW.backend as GodotBackend).mix_source()
	probe.check("hosts", Session.host(port))
	if not probe._noray.is_empty():
		Session.host_online(port)
		while Session.online.state in [NorayLink.State.REACHING, NorayLink.State.REGISTERING]:
			await probe.get_tree().process_frame
		probe.check("online, with a code (%s %s)" % [Session.online.oid, Session.online.why_not], Session.online.is_online())
		var f := FileAccess.open(_code_path(), FileAccess.WRITE)
		if f != null:
			f.store_string(Session.online.oid)
	for index in DAW.state.track_indices():
		probe._sends_before[index] = DAW.state.track(index).sends.size()
	# The room as the studio would publish it, and answered the way the studio answers.
	Session.publish_room({"venue": &"grid", "tablets": {&"tablet_1": [2, 1, "EQ", 0.4, 0.2, 0.0]}})
	Session.room_motion.connect(func(piece: StringName, x: float, z: float, h: float, from: int):
		probe._motions.append([piece, x, z, h, from]))
	Session.item_carried.connect(func(item: StringName, local: Transform3D, from: int):
		probe._carries.append([item, local, from]))
	Session.item_used.connect(func(item: StringName, down: bool, from: int, take: int):
		probe._uses.append([item, down, from])
		probe._use_takes.append(take))
	Session.item_used.connect(probe.room_checks._sample_a_use)
	Session.note_played.connect(probe.room_checks._on_note_played)
	Session.item_hit.connect(func(item: StringName, velocity: int, from: int, song: float, snap: bool, take: int, zone: StringName):
		probe._item_hits.append([item, velocity, from, song, snap, take, zone]))
	Session.room_asked.connect(func(verb: StringName, args: Array, from: int):
		probe._room_asks.append([verb, args, from])
		if verb == &"put_item":
			probe._duck_holder_at_put = Session.holder_of(SessionProbe.DUCK)
		if verb == &"plug":
			probe.room_checks._answer_plug(args, from)
		if verb == &"make":
			probe.room_checks._answer_make(args, from)
		if verb == &"paste":
			probe.room_checks._answer_paste(args, from)
		if verb == Sampler.VERB:
			probe.room_checks._answer_sampler(args, from)
		if verb == Weather.VERB:
			probe.item_checks._answer_weather(args, from)
		if verb == Looper.VERB:
			probe._answer_looper(args, from)
		if verb == Looper.LAYER_VERB:
			probe.item_checks._answer_looper_layer(args, from)
		if verb == FifthsWheel.VERB:
			# As the studio answers a guest's SET: written at the bar the guest chose.
			FifthsWheel.answer(args[0], args[1])
		if verb == &"open_tablet":
			var room: Dictionary = Session.room.duplicate(true)
			room["tablets"][&"tablet_2"] = [args[0], args[1], args[2], args[3], args[4], 0.0]
			Session.publish_room(room))
	probe.check("and shares its mix's audio", Session.mix_feed.sending)
	probe.room_checks._keep_publishing(Transform3D(Basis(Vector3.UP, 0.6), Vector3(1.2, 1.62, 0.4)), "MASTER  VOLUME")

	# Between the guest's wrong knock (0.3) and its right one (1.4), with room either side: two
	# processes started a moment apart do not share a clock to the millisecond.
	Session.takeable = func(key: String) -> bool: return key == SessionProbe.PLANE
	Session.holds_changed.connect(func() -> void:
		if probe._plane_holders.is_empty() or probe._plane_holders[-1] != Session.holder_of(SessionProbe.PLANE):
			probe._plane_holders.append(Session.holder_of(SessionProbe.PLANE)))
	Session.claim_hold(SessionProbe.PLANE)

	await probe.item_checks._until(0.9)
	probe.check("a knock with the wrong code is not let in", Session.participants.size() == 1)
	probe.check("and the host hears about it", probe._notices.has("Someone tried to join without the right code."))

	await probe.item_checks._until(3.6)
	var guest_id := probe.room_checks._other_id()
	probe.check("the guest is on the roster", guest_id != 0)
	probe.check("under the name it gave", Session.name_of(guest_id) == "Grace")
	if guest_id != 0:
		probe.check("in a colour of its own", Session.participants[guest_id].colour_index
				!= Session.participants[1].colour_index)
		probe.check("and its head has been heard", Session.participants[guest_id].head.origin.is_equal_approx(
				Vector3(-0.8, 1.5, 0.9)))
	probe.check("the guest's fader move reached the mix (%.4f)" % DAW.state.track(2).volume,
			absf(DAW.state.track(2).volume - 0.123) < 0.002)
	probe.check("the guest's tempo reached the mix (%.1f)" % DAW.state.tempo,
			absf(DAW.state.tempo - SessionProbe.GUEST_TEMPO) < 0.05)
	var sent := SessionProbeRoom._first_send(DAW.state)
	probe.check("the guest's send level reached the mix (%s)" % [sent], not sent.is_empty()
			and absf(DAW.state.send(sent[0], sent[1]).volume - SessionProbe.GUEST_SEND) < 0.002)
	probe._pinned = probe.room_checks._send_the_guests_pin_made()
	probe.check("the guest's bay pin is a send on the mix (%s)" % [probe._pinned], not probe._pinned.is_empty())
	probe.check("the guest switched the click on", DAW.state.metronome)
	probe.check("the guest's input monitoring reached the mix (%d)" % DAW.state.track(3).monitor,
			DAW.state.track(3).monitor == DAW.MONITOR_AUTO)
	probe.check("the guest's marker is on the host's timeline (%s)" % [DAW.state.markers.values()],
			SessionProbeItems._has_guest_mark(DAW.state))
	probe.check("the guest's grab is in the host's table", Session.holder_of(SessionProbe.KEY) == guest_id and guest_id != 0)
	probe.check("the guest's ask for a stand reached the host (%s)" % [probe._room_asks], probe._room_asks.size() == 3
			and probe._room_asks[0][0] == &"open_tablet" and probe._room_asks[0][2] == guest_id)
	probe.check("the guest's push reached the host while it moved (%s)" % [probe._motions], probe._motions.size() == 1
			and probe._motions[0][0] == &"rack" and is_equal_approx(probe._motions[0][1], -0.9) and probe._motions[0][4] == guest_id)
	probe.check("and its rolling the rack", probe._room_asks.size() == 3 and probe._room_asks[1][0] == &"move_piece"
			and probe._room_asks[1][1][0] == &"rack")
	probe.check("and its putting the desk down", probe._room_asks.size() == 3 and probe._room_asks[2][0] == &"place_surface"
			and (probe._room_asks[2][1][1] as Transform3D).origin.is_equal_approx(Vector3(0.1, 0, 0.2)))
	probe.check("and the guest is listening to the mix", Session.mix_feed.listener_count() == 1)
	probe.check("the guest's pick-up of the duck is in the host's table", Session.holder_of(SessionProbe.DUCK) == guest_id
			and guest_id != 0)
	probe.check("and where it carries it came with it (%s)" % [probe._carries], not probe._carries.is_empty()
			and probe._carries[-1][0] == &"duck" and (probe._carries[-1][1] as Transform3D).is_equal_approx(SessionProbe.DUCK_AT)
			and probe._carries[-1][2] == guest_id)
	probe.check("and its squeeze (%s)" % [probe._uses], probe._uses == [[&"duck", true, guest_id]])
	Session.send_item_use(&"duck", false)

	# Reach for the fader the guest is holding: the host's own hand is refused too.
	Session.claim_hold(SessionProbe.KEY)
	# A key on the host's keys, as played, for whoever is patched into them.
	Session.guest_midi.note_on(67, 80)
	Session.guest_midi.note_off(67)
	# And one from an instrument of the host's: it says so (GuestMidi.instruments).
	Session.guest_midi.note_on(71, 70, 0, 0.0, false, &"fingertips")
	Session.guest_midi.note_off(71, 0, 0.0, false, &"fingertips")
	await probe.item_checks._until(4.0)
	probe.check("the host is refused a control the guest holds",
			probe._refused.size() == 1 and probe._refused[0][0] == SessionProbe.KEY and probe._refused[0][1] == guest_id)
	probe.check("and the hold stays the guest's", Session.holder_of(SessionProbe.KEY) == guest_id)

	await probe.item_checks._until(6.0)
	probe.check("the guest's release cleared the table", Session.holds.is_empty())
	probe.check("the plane went from the host's hand to the guest's, and was let go (%s)" % [probe._plane_holders],
			probe._plane_holders == [1, probe.room_checks._other_id(), 0])
	probe.check("its throw of the duck arrived whole: the launch, as vectors (%s)" % [probe._room_asks[3] if probe._room_asks.size() > 3 else null],
			probe._room_asks.size() == 6 and probe._room_asks[3][0] == &"throw_item"
			and probe._room_asks[3][1] == [&"duck", Vector3(0.4, 1.2, 1.5), Vector3(0.0, 2.0, 3.5), Vector3(-6.0, 0.0, 0.0)])
	probe.check("its put-down of the duck arrived while it still had it (%d)" % probe._duck_holder_at_put,
			probe._room_asks.size() == 6 and probe._room_asks[4][0] == &"put_item" and probe._duck_holder_at_put == probe.room_checks._other_id())
	probe.check("the guest's keys as it played them, a note on and its note off (%s)" % [probe._notes],
			probe._notes == [[Session.Note.ON, 60, 100, guest_id], [Session.Note.OFF, 60, 0, guest_id]])
	probe.check("and its fingertips' note, saying where it came from (%s)" % [probe._sourced],
			probe._sourced == [[Session.Note.ON, 62, guest_id, &"fingertips"], [Session.Note.OFF, 62, guest_id, &"fingertips"]])
	probe.check("and its plug in the MIX send, for its own headphones (%s)" % [probe._room_asks[5] if probe._room_asks.size() > 5 else null],
			probe._room_asks.size() == 6 and probe._room_asks[5][0] == &"patch" and probe._room_asks[5][1] == [1, &"mix"]
			and probe._room_asks[5][2] == guest_id)
	Session.claim_hold(SessionProbe.KEY)
	probe.check("so the host can take it now", Session.holder_of(SessionProbe.KEY) == 1)
	Session.release_hold(SessionProbe.KEY)

	# The guest records a take against what it hears: see _guest_records. On the built-in engine
	# the host records itself instead: see _host_records_itself.
	await probe.item_checks._until(7.0)
	if not probe._built_in:
		DAW.transport_record()
	else:
		await probe.host_takes._host_records_itself()
	await probe.item_checks._until(12.8)
	if not probe._built_in:
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
		var file := OS.get_temp_dir().path_join("dawlings_probe_%d.dawproject" % probe._port)
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
		probe.check("I opened another project mid-session, through a file (%s %s %s)" % [refused, saved, opened],
				refused.is_empty() and saved.is_empty() and opened.is_empty())
		probe.check("with its second track's input kept (%s)" % DAW.state.input_of(2), DAW.state.input_of(2) == "audio:")
	if probe._built_in:
		await probe.item_checks._until(14.3)
		var file := OS.get_temp_dir().path_join("dawlings_probe_%d.dawproject" % probe._port)
		probe.check("the guest's save saved my file, and I was told (%s)" % [probe._notices],
				FileAccess.file_exists(file) and probe._notices.has("Grace saved the project as %s." % file.get_file()))
		DirAccess.remove_absolute(file)
		await probe.host_takes._render_and_measure()
		await probe.host_takes._count_in_and_measure()
		await probe.host_takes._count_in_and_measure(true)
		await probe.host_takes._count_in_and_measure(false, true)
		await probe.host_render._punch_and_measure()
		await probe.host_takes._meter_and_measure()
		await probe.host_render._parts_and_measure()
	await probe.item_checks._until(14.0)
	if not probe._built_in:
		probe.host_takes._check_placed_take()
		probe.host_render._check_audio_take()
		await probe.host_render._edit_the_take()
		if probe._reaper_resource != "":
			await probe.host_render._tracks_in_reaper()
		await probe.guesting._undo_takes()
		if probe._reaper_resource != "":
			# After the takes' undos: these are Reaper undo points of their own.
			await probe.host_render._count_in_in_reaper()
		await probe.item_checks._until(39.0 if probe._reaper_resource != "" else 17.5)
		probe.host_render._check_sent_files()

	# The song put in D minor from the playhead's bar, for the cables' chord tones.
	await probe.item_checks._until(40.0)
	var bar := floorf(DAW.state.bar_at(DAW.state.position_seconds) + Harmony.BAR_SLACK)
	DAW.add_marker(DAW.state.bar_to_seconds(bar + 1.0), SessionProbe.KEY_MARKER)
	probe.room_checks._make_room()

	await probe.item_checks._until(46.0)

	# Jacks (docs/spatial_loop.md slice 5): the guest plugged the cowbell on its shelf into track
	# 3 at 44.5, and the host's rule let it.
	var plugs := probe._room_asks.filter(func(a: Array) -> bool: return a[0] == &"plug")
	probe.check("the guest's plug reached me, from the guest (%s)" % [plugs], plugs.size() == 1
			and plugs[0][1] == [&"cowbell", &"track_3"] and plugs[0][2] == probe.room_checks._other_id())
	probe.check("and is in my room's state (%s)" % [Session.room.get("jacks")],
			Session.room.get("jacks", {}) == {"cowbell": "track_3"})
	var rows: Dictionary = Session.room.get("jacks", {}).duplicate(true)

	# Cables (docs/spatial_loop.md slice 6): jacks of my own, playing what comes into my keys, and
	# my word on every event down one, as the studio's (Session.jack_check).
	probe.item_checks._wear_jacks()
	probe._jacks.set_patch(rows)
	probe._room.played.connect(func(item: InstrumentItem, velocity: int, _struck: bool, at: float, zone: StringName) -> void:
		probe._jacks.hit(item, velocity, at, zone))
	Session.jack_check = func(to: int, source: StringName, from: int) -> String:
		var item: Item = probe._room.items.get(source)
		var holder := Session.holder_of(item.network_key()) if item != null else 0
		return Jacks.send_refusal(Session.room.get("jacks", {}), source, to, from, holder)
	# The guest's cowbell, in its hand and plugged into me at 48.3, hit four times at 48.8.
	await probe.item_checks._until(49.6)
	var hits := probe._jacked.filter(func(j: Array) -> bool: return j[0] == &"cowbell")
	probe.check("the guest's four cowbell hits reached me down its jack, from the guest (%s)" % [hits], hits.size() == 4
			and hits.all(func(j: Array) -> bool: return j[1] == Jack.Kind.TRIGGER and j[3] == probe.room_checks._other_id()))
	var tones := probe._cabled.filter(func(c: Array) -> bool: return c[0] == Session.Note.ON).map(func(c: Array) -> int: return c[1])
	probe.check("and played D minor's tones up the chord on my keys, at their songs (%s)" % [tones], tones == SessionProbe.CABLE_TONES
			and probe._cabled.filter(func(c: Array) -> bool: return c[0] == Session.Note.ON).map(func(c: Array) -> float: return c[2])
			== hits.map(func(j: Array) -> float: return j[4]))
	probe.check("each let go (%d)" % probe._cabled.filter(func(c: Array) -> bool: return c[0] == Session.Note.OFF).size(),
			probe._cabled.filter(func(c: Array) -> bool: return c[0] == Session.Note.OFF).size() == 4)

	# Slice 12: where history is before the guest's two-value drag, and my own fader in the middle
	# of it, as another player's write between the edit's.
	await probe.item_checks._until(54.4)
	probe._edit_depth = DAW.state.undo_depth
	probe._edit_was = [DAW.state.track(SessionProbe.EDIT_TRACK).pan, DAW.state.track(SessionProbe.EDIT_TRACK).volume,
			DAW.state.track(SessionProbe.EDIT_HOST_TRACK).volume]
	await probe.item_checks._until(54.7)
	DAW.set_track_volume(SessionProbe.EDIT_HOST_TRACK, 0.42)

	# The fifths wheel (docs/spatial_loop.md slice 9): the guest's SET at 53.7, asked with its bar.
	await probe.item_checks._until(55.0)
	var sets := probe._room_asks.filter(func(a: Array) -> bool: return a[0] == FifthsWheel.VERB)
	probe.check("the guest's SET reached me as an ask with its bar (%s)" % [sets], sets.size() == 1
			and sets[0][1] == [SessionProbe.WHEEL_BAR, SessionProbe.WHEEL_INSIDE] and sets[0][2] == probe.room_checks._other_id())
	probe.room_checks._check_wheel("my")
	# The guest travelled to the wheel at 53.8, in a headset (slice 11): its head, which its ghost
	# stands at, is at the wheel's seat in my room's venue.
	var seat: Variant = probe.room_checks._wheel_seat()
	var guest_head: Transform3D = Session.participants[probe.room_checks._other_id()].head if Session.participants.has(probe.room_checks._other_id()) \
			else Transform3D.IDENTITY
	var wanted: Vector3 = (seat as Transform3D) * SessionProbe.TRAVEL_OFFSET if seat != null else Vector3.INF
	probe.check("the guest's travel put its ghost at the wheel's seat (%.3f m off)" % guest_head.origin.distance_to(wanted),
			guest_head.origin.distance_to(wanted) < 0.05)

	# One undo step per gesture (slice 12): the guest's two-value drag, 54.55 to about 54.9,
	# inside an edit; my own fader in the middle of it is a step of my own. After 55.1, when the
	# guest has read the same.
	await probe.item_checks._until(55.25)
	var depth: int = DAW.state.undo_depth
	var names: Array = DAW.state.undo_names.slice(probe._edit_depth, depth)
	probe.check("the guest's drag moved both its pan and its volume (%.3f, %.3f)" % [DAW.state.track(SessionProbe.EDIT_TRACK).pan,
			DAW.state.track(SessionProbe.EDIT_TRACK).volume], absf(DAW.state.track(SessionProbe.EDIT_TRACK).pan - SessionProbe.EDIT_PAN) < 0.002
			and absf(DAW.state.track(SessionProbe.EDIT_TRACK).volume - SessionProbe.EDIT_VOLUME) < 0.002)
	if probe._reaper_resource == "":
		probe.check("and is one step in my history, beside my own (%s)" % [names], depth == probe._edit_depth + 2
				and names.count(SessionProbe.EDIT_NAME) == 1 and names.any(func(n) -> bool: return str(n).ends_with(": volume")))
		DAW.undo()
		DAW.undo()
		probe.check("two undos take back my fader, and the guest's whole drag (%.3f %.3f %.3f)" % [
				DAW.state.track(SessionProbe.EDIT_TRACK).pan, DAW.state.track(SessionProbe.EDIT_TRACK).volume, DAW.state.track(SessionProbe.EDIT_HOST_TRACK).volume],
				absf(DAW.state.track(SessionProbe.EDIT_TRACK).pan - float(probe._edit_was[0])) < 0.0001
				and absf(DAW.state.track(SessionProbe.EDIT_TRACK).volume - float(probe._edit_was[1])) < 0.0001
				and absf(DAW.state.track(SessionProbe.EDIT_HOST_TRACK).volume - float(probe._edit_was[2])) < 0.0001
				and DAW.state.undo_depth == probe._edit_depth)
	else:
		# Reaper's OSC writes stay its own undo points (docs/spatial_loop.md): put back by hand.
		DAW.set_track_pan(SessionProbe.EDIT_TRACK, float(probe._edit_was[0]))
		DAW.set_track_volume(SessionProbe.EDIT_TRACK, float(probe._edit_was[1]))
		DAW.set_track_volume(SessionProbe.EDIT_HOST_TRACK, float(probe._edit_was[2]))

	# Controls beside the keys (slice 13): my bend during a held note, which the guest hears on its
	# TheirKeys, and which rests there at my note-off. The guest's CC 7 at 55.27 is refused here.
	var gm := Session.guest_midi
	await probe.item_checks._until(55.29)
	gm.note_on(SessionProbe.BEND_PITCH, 100)
	probe.check("my bend during a held note is taken", gm.control(DawKitClip.PITCH_BEND, SessionProbe.BEND_VALUE))
	await probe.item_checks._until(55.45)
	gm.note_off(SessionProbe.BEND_PITCH)
	probe.check("and rests at my note-off", int(gm.controls.get(DawKitClip.PITCH_BEND, -1)) == 0)
	probe.check("the guest's volume controller was refused, as no controller but the bend, 1 and 11 is passed (%d)"
			% Session.controls_refused, Session.controls_refused == 1)

	# Controls in takes (slice 14): the guest's keyboard wheel at 56.2, during a held note, is a
	# control in the take it sends me, at the song it was moved at, and back at rest at its note-off.
	await probe.item_checks._until(56.7)
	probe.host_takes._check_bent_take()

	# Snapped gently (slice 17): the guest's cowbell hit 20 ms before a sixteenth, snapped, is half
	# way there in the take it sends me; its unsnapped one is where it was played.
	await probe.item_checks._until(57.65)
	probe.host_takes._check_snapped_take()

	# The stage table (slice 18): the guest's placing, from 57.7, is its pan and its level at once,
	# and one step in my history: one undo takes both back.
	probe._stage_was = [DAW.state.track(SessionProbe.STAGE_TRACK).pan, DAW.state.track(SessionProbe.STAGE_TRACK).volume]
	await probe.item_checks._until(58.1)
	probe.host_takes._check_stage_placing()

	# Clap to mute (slice 19): the guest's clap at 58.2, a latch, toggles my track's mute.
	probe._clap_was = DAW.state.track(SessionProbe.CLAP_TRACK).mute
	await probe.item_checks._until(58.4)
	probe.host_takes._check_clap_mute()

	# Sidechain as a rope (slice 20): the guest's rope, tied at 58.5, is my key send.
	probe._rope_plugins_were = DAW.state.track(SessionProbe.ROPE_TO).plugins().size()
	await probe.item_checks._until(58.67)
	_check_rope()

	# Automation by gesture (slice 22): the guest's write bead, pulled at 58.74 to a clock of its
	# own, is my lane at its song positions.
	probe._bead_was = WriteBead.lane_now(SessionProbe.BEAD_TRACK, "volume")
	probe._bead_volume_was = DAW.state.track(SessionProbe.BEAD_TRACK).volume
	await probe.item_checks._until(58.85)
	_check_written_lane()

	# Clips as cassettes (slice 23): the guest's pull at 58.86 is a cassette I mint and put in its
	# glove (`_answer_make`); at 58.9 I hand it one of my own, as the studio's give does.
	await probe.item_checks._until(58.9)
	probe.room_checks._give_a_cassette()
	await probe.item_checks._until(58.97)
	probe.room_checks._check_cassettes_given()

	# A cassette onto a track (slice 24): the guest's paste at 58.99 of the cassette I gave it is my
	# own row's clip on PASTE_TRACK at PASTE_BAR (`_answer_paste`), one step I take back at 59.1.
	await probe.item_checks._until(59.08)
	probe.room_checks._check_pasted()
	await probe.item_checks._until(59.1)
	probe.room_checks._take_back_the_paste()

	# A cassette at the ear (slice 25): an audio cassette of a file only I have, minted at 59.12; the
	# guest's ear on it at 59.2 asks me for the file, and by 59.34 I have sent it, once.
	await probe.item_checks._until(59.12)
	probe.room_checks._mint_an_ear_cassette()
	await probe.item_checks._until(59.34)
	probe.room_checks._check_ear_file_sent()

	# Anything can be a sample (slice 26): the guest's REC at 59.36 arms my sampler for it
	# (`_answer_sampler`); its squeeze at 59.48 is caught here with its take (`_sample_a_use`).
	await probe.item_checks._until(59.52)
	probe.room_checks._check_sampled()
	await probe.item_checks._until(59.62)
	probe.room_checks._take_back_the_sample()

	# A DJ platter (slice 27): the guest's turns of its platter, 59.6 to 59.68, are seeks of mine.
	await probe.item_checks._until(59.74)
	probe.room_checks._check_platter_seek()
	# And my playhead back in D minor, where the chord hand (slice 33) is held at 60.66:
	# the platter left it at bar 7, in the intro's A minor, whose IV is Dm and not Gm.
	DAW.seek(probe.item_checks._ring_song())

	# A tape reel for undo history (slice 28): the guest's crank, settled about 60.05, is one
	# undo_to of my history, CRANK_NOTCHES back from where it is at 59.76; put back at 60.14.
	await probe.item_checks._until(59.76)
	var crank_from: int = DAW.state.undo_depth
	await probe.item_checks._until(60.12)
	probe.room_checks._check_cranked(crank_from)
	await probe.item_checks._until(60.14)
	if crank_from >= 0:
		DAW.undo_to(crank_from)
	else:
		for _i in SessionProbe.CRANK_NOTCHES:
			DAW.redo()

	# Sections rearranged (slice 29): three regions of mine past the song, laid out at 60.16; the
	# guest's order at 60.24 is one step of mine by 60.34, taken back with them at 60.36.
	await probe.item_checks._until(60.16)
	probe.room_checks._lay_out_sections()
	await probe.item_checks._until(60.34)
	probe.room_checks._check_rearranged()
	await probe.item_checks._until(60.36)
	probe.room_checks._take_back_the_sections()

	# A chord hand down a jack (part two, slice 33): a chord hand of mine to take the guest's chord,
	# its chord:G plugged into me at 60.62, IV held at 60.66; taken by 60.7, and
	# let go once the guest unplugs it at 60.74.
	await probe.item_checks._until(60.6)
	var chords := ChordHand.new()
	probe.add_child(chords)
	await probe.item_checks._until(60.7)
	probe.item_checks._check_chord_into_me(chords)
	await probe.item_checks._until(60.8)
	probe.check("unplugged, the guest's chord is let go", not chords.plays_theirs())
	chords.queue_free()

	# Point, mark and listen together (slice 35): the guest's ruler point and its sticky note, by
	# 60.9; the note taken back at 60.92.
	await probe.item_checks._until(60.9)
	probe.item_checks._check_point_and_note()
	await probe.item_checks._until(60.92)
	probe.item_checks._take_back_the_note()

	# The EQ wall's spectra (slice 36): sent from 60.92 to 61.12, as the studio's Spectra sends them.
	var spectra := Spectra.new()
	spectra.measure = SessionProbeItems._probe_spectrum
	probe.add_child(spectra)
	await probe.item_checks._until(61.12)
	probe.check("my spectra went out: measured, a guest here to send them to", not spectra.latest().is_empty()
			and Session.role == Session.Role.HOST)
	spectra.queue_free()

	# Carving the clash (slice 37): the guest's push on the bass's side, from 61.14, is my bass's EQ by
	# 61.26, taken back at once.
	var carve_chain := DAW.state.track(SessionProbe.SPECTRA_BASS).plugins().size()
	var carve_depth := maxi(DAW.state.undo_depth, 0)
	await probe.item_checks._until(61.26)
	probe.item_checks._check_carve(carve_chain, carve_depth)

	# Instruments that stand still (slice 38): the guest's strike on the test drum, at 61.3, is mine
	# by 61.46 with its zone and song, and my drum plays it where it stands.
	await probe.item_checks._until(61.28)
	probe._room.spawn(&"testdrum", &"testdrum", SessionProbe.DRUM_HOME)
	probe._room.stand(&"djembe", SessionProbe.DJEMBE_HOME)
	probe._room.stand(KitItem.KIND, SessionProbe.KIT_HOME)
	probe.item_checks._stand_the_railing()
	probe.item_checks._publish_the_weather()
	await probe.item_checks._until(61.46)
	probe.item_checks._check_drum_strike()
	probe.item_checks._check_djembe_slap()
	probe.item_checks._check_pad_hit()
	probe.item_checks._check_railing_strike()
	await probe.item_checks._until(61.56)
	probe.item_checks._check_weather_asked()
	await probe.item_checks._until(61.76)
	probe.item_checks._check_looper_layer()
	await probe.item_checks._until(61.92)
	probe.item_checks._check_ring_pulled()
	await probe.item_checks._until(61.98)
	probe.item_checks._take_back_the_looper()
	# How much of the time before the end the work took: the end has moved twelve times as it grew.
	if DAW.backend is GodotBackend:
		print("engine: %s" % ("native lanes" if (DAW.backend as GodotBackend).lanes != null else "players"))
	# The lyrics in the booth (slice 56): the guest's two lines from 64.52 and its TAP at 64.6.
	await probe.item_checks._until(64.7)
	probe.item_checks._check_the_guests_tap()

	print("host work done at %.2fs of 64.76" % ((Time.get_ticks_msec() - probe._start) / 1000.0 - probe._shift))
	await probe.item_checks._until(64.76)
	Session.leave()
	probe.check("ending the session leaves the host solo", Session.role == Session.Role.SOLO)
	probe.check("with its own mix still open", DAW.is_live() and DAW.state.track(2).volume > 0.12)
	if not is_nan(restore):
		DAW.set_track_volume(2, restore)
	if not is_nan(tempo_restore):
		DAW.set_tempo(tempo_restore)
	DAW.set_metronome(false)
	if monitor_restore >= 0:
		DAW.set_track_monitor(3, monitor_restore)
	if not is_nan(send_restore):
		var first := SessionProbeRoom._first_send(DAW.state)
		DAW.set_send_volume(first[0], first[1], send_restore)
	if not probe._pinned.is_empty():
		DAW.remove_send(probe._pinned[0], probe._pinned[1])
	DAW.set_lyrics("")
	await probe.item_checks._until(64.83)


## The guest's rope (slice 20), as my DAW has it: a key send from ROPE_FROM into ROPE_TO and a
## compressor on ROPE_TO to hear it, listening to it on the built-in engine, as one step named for
## the rope, which one undo takes back. On Reaper the bridge's Batch is Reaper's own one step; it is
## taken back by hand.
func _check_rope() -> void:
	var n := Sidechain.key_send(SessionProbe.ROPE_FROM, SessionProbe.ROPE_TO)
	var comp := Sidechain.compressor_on(SessionProbe.ROPE_TO)
	probe.check("the guest's rope is my key send from track %d into %d (send %d)" % [SessionProbe.ROPE_FROM, SessionProbe.ROPE_TO, n], n > 0)
	probe.check("with a compressor on %d to hear it (%d)" % [SessionProbe.ROPE_TO, comp], comp >= 0)
	var engine := DAW.backend as GodotBackend
	if engine != null and comp >= 0:
		var effect := AudioServer.get_bus_effect(engine._bus[SessionProbe.ROPE_TO], 1 + comp) as AudioEffectCompressor
		probe.check("which listens to the key (%s)" % (effect.sidechain if effect != null else &"none"),
				effect != null and effect.sidechain == StringName(GodotBackend.send_bus(SessionProbe.ROPE_FROM, SessionProbe.ROPE_TO)))
	if probe._reaper_resource == "":
		var last: String = str(DAW.state.undo_names[DAW.state.undo_depth - 1]) if DAW.state.undo_depth > 0 else ""
		var named := "%s > %s: rope" % [DAW.state.track(SessionProbe.ROPE_FROM).display_name(), DAW.state.track(SessionProbe.ROPE_TO).display_name()]
		probe.check("as one step, called the rope (%s)" % last, last == named)
		DAW.undo()
		probe.check("which one undo takes back whole", Sidechain.key_send(SessionProbe.ROPE_FROM, SessionProbe.ROPE_TO) == 0
				and DAW.state.track(SessionProbe.ROPE_TO).plugins().size() == probe._rope_plugins_were)
	else:
		if comp >= 0 and DAW.state.track(SessionProbe.ROPE_TO).plugins().size() > probe._rope_plugins_were:
			DAW.remove_fx(SessionProbe.ROPE_TO, comp)
		if n > 0:
			DAW.remove_send(SessionProbe.ROPE_FROM, n)


## The guest's write bead pass (slice 22), as my DAW has it: BEAD_TRACK's volume lane, its points
## at the guest's song positions from BEAD_SONG, one each WriteBead.POINT_SECONDS, rising as the
## guest's hand did, and the lane let go again. One step named for the lane, which one undo takes
## back; on Reaper the lane and the level are put back by hand.
func _check_written_lane() -> void:
	var lane := WriteBead.lane_now(SessionProbe.BEAD_TRACK, "volume")
	var inside := lane.filter(func(pt): return absf(float(pt[0]) - SessionProbe.BEAD_SONG - SessionProbe.BEAD_SECONDS * 0.5) <= SessionProbe.BEAD_SECONDS * 0.5 + 0.0001)
	var spaced := true
	for i in inside.size():
		spaced = spaced and absf(float(inside[i][0]) - (SessionProbe.BEAD_SONG + i * WriteBead.POINT_SECONDS)) < 0.002
	var wanted := roundi(SessionProbe.BEAD_SECONDS / WriteBead.POINT_SECONDS) + 1
	probe.check("the guest's bead pass is my track %d's lane at its song positions from %.1f (%d of %d points)"
			% [SessionProbe.BEAD_TRACK, SessionProbe.BEAD_SONG, inside.size(), wanted], inside.size() == wanted and spaced)
	probe.check("rising as its hand did (%s)" % [[inside[0][1], inside[-1][1]] if not inside.is_empty() else []],
			not inside.is_empty() and float(inside[-1][1]) > float(inside[0][1]) + 1.0)
	probe.check("and the lane is followed again", not DAW.backend.lane_held(SessionProbe.BEAD_TRACK, "volume"))
	if probe._reaper_resource == "":
		var last: String = str(DAW.state.undo_names[DAW.state.undo_depth - 1]) if DAW.state.undo_depth > 0 else ""
		probe.check("as one step, named for the lane (%s)" % last, last.ends_with("level automation"))
		DAW.undo()
		probe.check("which one undo takes back", ReaperBackend._same_lane(WriteBead.lane_now(SessionProbe.BEAD_TRACK, "volume"), probe._bead_was))
	else:
		DAW.set_automation(SessionProbe.BEAD_TRACK, "volume", probe._bead_was)
		DAW.set_track_volume(SessionProbe.BEAD_TRACK, probe._bead_volume_was)
