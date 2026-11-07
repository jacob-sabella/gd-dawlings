class_name SessionProbeTakes
extends RefCounted

## The host's checks on a guest's takes (bent, snapped, placed), the host recording itself and the measurements of
## onsets, ramps and the render.
## Moved out of `tools/probe/session_probe.gd` without change of behaviour; the state stays on the probe node, which keeps a one-line delegate for each name another file or a string reaches.

var probe: SessionProbe


func _init(of: SessionProbe) -> void:
	probe = of


## The guest's latched clap (slice 19), as my DAW has it: CLAP_TRACK's mute toggled from what it
## was, and left so once its hands parted. Put back.
func _check_clap_mute() -> void:
	var t := DAW.state.track(SessionProbe.CLAP_TRACK)
	probe.check("the guest's latched clap toggled my track %d's mute (%s, was %s)" % [SessionProbe.CLAP_TRACK, t.mute, probe._clap_was],
			t.mute != probe._clap_was)
	DAW.set_track_mute(SessionProbe.CLAP_TRACK, probe._clap_was)


## The guest's placing on its stage table (slice 18), as my DAW has it: the stage track's pan and
## level where the guest put its voice, the last step in my history named for it as a placing,
## which one undo takes back whole. On Reaper its OSC writes stay Reaper's own undo points, so
## the track is put back by hand.
func _check_stage_placing() -> void:
	var t := DAW.state.track(SessionProbe.STAGE_TRACK)
	var db := DAW.taper_to_db(t.volume)
	probe.check("the guest's placing on its stage table moved my track %d's pan and level at once (%s, %.2f dB)"
			% [SessionProbe.STAGE_TRACK, StageTable.pan_words(t.pan), db], absf(t.pan - SessionProbe.STAGE_PAN) < 0.002 and absf(db - SessionProbe.STAGE_DB) < 0.05)
	if probe._reaper_resource == "":
		var last: String = str(DAW.state.undo_names[DAW.state.undo_depth - 1]) if DAW.state.undo_depth > 0 else ""
		probe.check("as one step, called a placing (%s)" % last, last == "%s: place" % t.display_name())
		DAW.undo()
		probe.check("which one undo takes back whole (%.3f %.3f)" % [t.pan, t.volume],
				absf(t.pan - float(probe._stage_was[0])) < 0.0001 and absf(t.volume - float(probe._stage_was[1])) < 0.0001)
	else:
		DAW.set_track_pan(SessionProbe.STAGE_TRACK, float(probe._stage_was[0]))
		DAW.set_track_volume(SessionProbe.STAGE_TRACK, float(probe._stage_was[1]))


## The guest's bent take (slice 14), as my DAW has it: its note, and its keyboard's bend as a
## control at the song the guest moved the wheel at, then back at rest at the note-off.
func _check_bent_take() -> void:
	var expected_path := "/tmp/r3d_probe_bend_%d.json" % probe._port
	var expected = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	DirAccess.remove_absolute(expected_path)
	probe.check("the guest wrote down where it bent", expected is Dictionary)
	if not expected is Dictionary:
		return
	var takes: Array = DAW.state.track(SessionProbe.TAKE_TRACK).items.filter(func(it: MixState.ItemState) -> bool:
			return it.start > SessionProbe.BENT_SONG - 0.1 and it.start < SessionProbe.BENT_SONG + 1.0)
	probe.check("the guest's bent take is an item on track %d (%d)" % [SessionProbe.TAKE_TRACK, takes.size()], takes.size() == 1)
	if takes.size() != 1:
		return
	var item: MixState.ItemState = takes[0]
	var notes := MidiTake.unpack_relative(item.notes, item.start)
	var bends: Array = []
	for o in range(0, item.controls.size() - DawKitClip.CONTROL_WIDTH + 1, DawKitClip.CONTROL_WIDTH):
		if int(item.controls[o + 1]) == DawKitClip.PITCH_BEND:
			bends.append([item.start + item.controls[o], int(item.controls[o + 2])])
	var bent: Array = bends.filter(func(b: Array) -> bool: return b[1] == SessionProbe.BEND_VALUE)
	var off := float(notes[0][1]) if notes.size() == 1 else NAN
	print("bend: placed ", bends, " expected ", expected)
	probe.check("with its held note (%s)" % [notes], notes.size() == 1 and int(notes[0][2]) == SessionProbe.BENT_PITCH)
	probe.check("and the guest's bend at 56.2 is a control in it at that song, during the note, worst %.2fms (%s)" % [
			absf(float(bent[0][0]) - float(expected["at"])) * 1000.0 if bent.size() == 1 else -1.0, bends],
			bent.size() == 1 and notes.size() == 1 and absf(float(bent[0][0]) - float(expected["at"])) < SessionProbe.TAKE_TOLERANCE
			and float(bent[0][0]) > float(notes[0][0]) and float(bent[0][0]) < off)
	probe.check("then back at rest at the note-off", bends.size() == 2 and bends[1][1] == 0
			and absf(float(bends[1][0]) - off) <= MidiTake.CONTROL_GAP + 0.0001)


## The guest's snapped cowbell take (slice 17), as my DAW has it: its snapped hit half way to the
## sixteenth it was played 20 ms before, by the guest's grid and by mine; its unsnapped one where it
## was played; and both hits as they reached me, each with its snap flag and its Foley take.
func _check_snapped_take() -> void:
	var expected_path := "/tmp/r3d_probe_snap_%d.json" % probe._port
	var expected = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	DirAccess.remove_absolute(expected_path)
	probe.check("the guest wrote down where it played", expected is Dictionary)
	if not expected is Dictionary:
		return
	var first := float(expected["first"])
	var second := float(expected["second"])
	var takes: Array = DAW.state.track(SessionProbe.TAKE_TRACK).items.filter(func(it: MixState.ItemState) -> bool:
			return it.start > SessionProbe.SNAP_SONG - 0.1 and it.start < SessionProbe.SNAP_SONG + 1.0)
	probe.check("the guest's cowbell take is an item on track %d (%d)" % [SessionProbe.TAKE_TRACK, takes.size()], takes.size() == 1)
	if takes.size() != 1:
		return
	var item: MixState.ItemState = takes[0]
	var notes := MidiTake.unpack_relative(item.notes, item.start)
	notes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	print("snap: placed ", notes, " expected ", expected)
	probe.check("with both its hits, as the cowbell (%s)" % [notes], notes.size() == 2
			and notes.all(func(n: Array) -> bool: return int(n[2]) == 56 and int(n[4]) == HitRecorder.CHANNEL))
	if notes.size() != 2:
		return
	var mine := HitRecorder.snapped_at(first, DAW.state)
	probe.check("its snapped hit, played 20 ms early, landed 10 ms early by its grid and mine (%.4f for %.4f, %.4f)" % [
			float(notes[0][0]), float(expected["snapped"]), mine],
			absf(float(notes[0][0]) - float(expected["snapped"])) < 0.0005 and absf(mine - float(expected["snapped"])) < 0.0005
			and absf(float(notes[0][0]) - first - SessionProbe.SNAP_EARLY * HitRecorder.SNAP_PULL) < 0.0005)
	probe.check("and its unsnapped one where it was played (%.4f for %.4f)" % [float(notes[1][0]), second],
			absf(float(notes[1][0]) - second) < 0.0005)
	var rung := probe._item_hits.filter(func(h: Array) -> bool: return h[0] == &"cowbell" and h.size() == 7)
	var on := rung.filter(func(h: Array) -> bool: return absf(float(h[3]) - first) < 0.0001)
	var off := rung.filter(func(h: Array) -> bool: return absf(float(h[3]) - second) < 0.0001)
	probe.check("both hits reached me with their snap and their take, at the song they were played to (%s)" % [rung],
			on.size() == 1 and bool(on[0][4]) and int(on[0][5]) == 5
			and off.size() == 1 and not bool(off[0][4]) and int(off[0][5]) == 6)


## The guest's take, as the host's DAW has it, against when the guest heard each note played.
func _check_placed_take() -> void:
	var expected_path := "/tmp/r3d_probe_take_%d.json" % probe._port
	var expected = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	DirAccess.remove_absolute(expected_path)
	probe.check("the guest wrote down what it played", expected is Dictionary)
	if not expected is Dictionary:
		return
	var item: MixState.ItemState = null
	for it in DAW.state.track(SessionProbe.TAKE_TRACK).items:
		if it.name == "Grace take 1":
			item = it
	probe.check("the guest's take is an item on track %d" % SessionProbe.TAKE_TRACK, item != null)
	probe.check("and the room was told", probe._notices.any(func(t): return t.begins_with("Grace played 4 notes onto")))
	if item == null:
		return
	var placed := MidiTake.unpack_relative(item.notes, item.start)
	probe.check("with all four of its notes (%d)" % placed.size(), placed.size() == 4)
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
	probe.check("each where the guest heard it played, worst %.2fms" % (worst * 1000.0),
			all_there and worst < SessionProbe.TAKE_TOLERANCE)
	print("take: placed ", placed, " expected ", expected["notes"], " worst_ms %.3f" % (worst * 1000.0))
	var hanging: Array = placed.filter(func(n): return int(n[2]) == int(expected["hanging"]))
	probe.check("a note still down when recording stopped ends with the take",
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
	ha.target_track = SessionProbe.HOST_TAKE_TRACK
	ha.record_with_host = true
	probe._audio_placed = {}
	DAW.set_metronome(true)
	# The tempo changes in the middle of the take: held, then ramped down to three quarters over
	# four beats. The clicks and the notes below follow it, and are measured against it.
	var tempo := DAW.state.tempo
	var turn := ceilf((SessionProbe.HOST_TAKE_AT + 0.6) * tempo / 60.0)
	DAW.set_tempo_map([[0.0, tempo, DawKitTempoMap.HOLD], [turn, tempo, DawKitTempoMap.RAMP_BEATS],
			[turn + 4.0, tempo * 0.75, DawKitTempoMap.HOLD]])
	var map := DAW.state.tempo_map()
	# A MIDI item under the take, a short high note on every off-beat, played by the engine's
	# instrument: between the clicks, so each can be found on its own.
	var notes: Array = []
	var nb := ceilf(map.beat_at(SessionProbe.HOST_TAKE_AT)) + 0.5
	while map.seconds_at(nb) < SessionProbe.HOST_TAKE_AT + 6.0:
		var t := map.seconds_at(nb)
		notes.append([t, t + 0.08, 84, 120, 0])
		nb += 1.0
	DAW.state.track(SessionProbe.HOST_MIDI_TRACK).items.clear()
	DAW.insert_midi_take(SessionProbe.HOST_MIDI_TRACK, SessionProbe.HOST_TAKE_AT, SessionProbe.HOST_TAKE_AT + 6.0, notes, "Off-beats")
	# And their track's fader automated: held, then down 9 dB in a straight line over three seconds,
	# then held there. Each note's level in the take is measured against it.
	DAW.set_automation(SessionProbe.HOST_MIDI_TRACK, "volume", SessionProbe.HOST_RAMP)
	var midi: MixState.ItemState = DAW.state.track(SessionProbe.HOST_MIDI_TRACK).items[0]
	(DAW.backend as GodotBackend).midi_stream(midi, true)
	DAW.seek(SessionProbe.HOST_TAKE_AT)
	await probe.item_checks._until(7.6)
	probe.check("my microphone is open (%s)" % ha.input_device, ha.mic_open())
	var gm := Session.guest_midi
	gm.target_track = SessionProbe.HOST_KEYS_TRACK
	gm.record_with_host = true
	DAW.state.track(SessionProbe.HOST_KEYS_TRACK).items.clear()
	var reseeks_before: int = (DAW.backend as GodotBackend).reseeks
	DAW.transport_record()
	# A key of my own, heard through its track, a quarter of a beat after a click: between the
	# click and the off-beat note, so its sound can be found in the take on its own.
	await probe.item_checks._until(9.0)
	while absf(fposmod(map.beat_at(DAW.state.position_seconds), 1.0) - 0.22) > 0.04:
		await probe.get_tree().process_frame
	gm.note_on(96, 127)
	await probe.get_tree().create_timer(0.1).timeout
	gm.note_off(96)
	await probe.item_checks._until(11.2)
	var reseeks: int = (DAW.backend as GodotBackend).reseeks - reseeks_before
	print("host take reseeks: %d" % reseeks)
	probe.check("nothing put back on the clock while I recorded (%d)" % reseeks, reseeks == 0)
	DAW.transport_stop()
	await probe.item_checks._until(11.6)
	ha.record_with_host = false
	probe.check("my own recording was placed (%s)" % [probe._audio_placed], not probe._audio_placed.is_empty()
			and int(probe._audio_placed.get("track", 0)) == SessionProbe.HOST_TAKE_TRACK)
	if probe._audio_placed.is_empty():
		return
	var wav := FileAccess.get_file_as_bytes(probe._audio_placed["path"])
	var start: float = probe._audio_placed["start"]
	_measure_onsets("clicks", wav, start, map, 0.0)
	_measure_onsets("notes", wav, start, map, 0.5)
	_measure_ramp(wav, start, map)
	DAW.set_automation(SessionProbe.HOST_MIDI_TRACK, "volume", [])
	var at_turn := map.seconds_at(turn + 4.0) - start
	probe.check("and the take runs through the tempo's change (%.2fs in, of %.2fs)" % [at_turn, probe._audio_placed["seconds"]],
			at_turn > 1.0 and at_turn < float(probe._audio_placed["seconds"]) - 0.3)
	# My key: where its sound is in the take against where the keys' take put the note. The same
	# moment, if what the host hears of its own keys is accounted for.
	var keys: Array = DAW.state.track(SessionProbe.HOST_KEYS_TRACK).items.filter(
			func(it: MixState.ItemState) -> bool: return not it.notes.is_empty())
	probe.check("my key was taken down on its track (%d)" % keys.size(), keys.size() == 1)
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
		probe.check("my key's sound is where its note was put (%.2fms)" % ((heard_at - stamped) * 1000.0),
				absf(heard_at - stamped) < SessionProbe.HOST_TAKE_TOLERANCE)


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
	probe.check("%s on every one in my take (%d of %d)" % [what, offs.size(), peaks.size()],
			peaks.size() >= 5 and offs.size() == peaks.size())
	probe.check("%s on time, on average (%.2fms)" % [what, mean * 1000.0], absf(mean) < SessionProbe.HOST_TAKE_TOLERANCE)
	probe.check("%s, each of them (%.2fms from the average)" % [what, spread * 1000.0], spread < SessionProbe.HOST_TAKE_TOLERANCE)


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
		rows.append([b, 10.0 * log(power) / log(10.0), DawKitAutomation.value_in(SessionProbe.HOST_RAMP, middle)])
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
	probe.check("the notes follow their fader's automation (%d of %d down the ramp, worst %.2f dB off)" % [ramped, rows.size(), worst],
			flat.size() >= 2 and ramped >= 3 and rows.any(func(r): return r[2] < -5.0) and worst < SessionProbe.HOST_RAMP_TOLERANCE_DB)


## A passage rendered with its stems, and the stem measured: a track of its own with a note on
## every half second, its fader dropped 12 dB halfway by its automation. Each note's onset in
## the file against where it is in the song, and each note's level against the lane.
func _render_and_measure() -> void:
	var count := DAW.state.track_indices().size()
	DAW.add_track(count + 1, "Render probe")
	var track := count + 1
	var at := SessionProbe.RENDER_FROM + 0.5
	var notes: Array = []
	for i in 6:
		notes.append([at + i * 0.5, at + i * 0.5 + 0.08, 84, 120, 0])
	DAW.insert_midi_take(track, SessionProbe.RENDER_FROM, SessionProbe.RENDER_FROM + 3.5, notes, "Render probe")
	# Sent to the reverb, so its last notes ring on past the range: the render's tail.
	for index in DAW.state.track_indices():
		if DAW.state.track(index).name == "Verb Rtn":
			DAW.create_send(track, index)
	var part := (DAW.backend as GodotBackend).midi_stream(DAW.state.track(track).items[0], true)
	# The instrument's own attack: how far into its first note its sound reaches half its peak,
	# in the item's own rendered sound. That much after the note is on time.
	var first := int((at - SessionProbe.RENDER_FROM) * part.mix_rate)
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
	DAW.set_loop_range(SessionProbe.RENDER_FROM, SessionProbe.RENDER_FROM + 3.5)
	DAW.set_looping(true)
	var done: Array = []
	DAW.render_finished.connect(func(files, problems): done.append([files, problems]), probe.CONNECT_ONE_SHOT)
	var began := Time.get_ticks_msec()
	DAW.render(true)
	while done.is_empty() and Time.get_ticks_msec() - began < 8000:
		await probe.get_tree().process_frame
	var seconds := (Time.get_ticks_msec() - began) / 1000.0
	probe.check("I rendered the loop with its stems (%.2fs, %s)" % [seconds, done], not done.is_empty()
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
	probe.check("the stem is the loop and a tail (%.3fs and %.3fs)" % [range_frames / float(rate), tail_frames / float(rate)],
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
	probe.check("the reverb rings on after the range, falling away to silence (%.2fs, %d rises, ends at %.1f dB)" % [
			tail_frames / float(rate), rises, windows[-1] if not windows.is_empty() else 0.0],
			tail_frames > rate / 2 and windows.size() >= 3 and rises == 0 and windows[-1] < -60.0
			and windows[-1] < windows[0] - 40.0)
	var offs: Array = []
	var levels: Array = []
	for n in notes:
		var centre := int((float(n[0]) - SessionProbe.RENDER_FROM) * rate)
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
	probe.check("each note is where it is in the song (%d of %d, worst %.2fms)" % [offs.size(), notes.size(), spread],
			offs.size() == notes.size() and spread < SessionProbe.RENDER_TOLERANCE_MS)
	probe.check("and the fader's drop is in the stem (%.2f dB)" % step, absf(step + 12.0) < 0.5)
	var mix_peak := 0.0
	for v in (mix["samples"] as PackedFloat32Array):
		mix_peak = maxf(mix_peak, absf(v))
	probe.check("the mix has the song in it (peak %.3f)" % mix_peak, mix_peak > 0.05)
	await probe.get_tree().create_timer(0.2).timeout
	probe.check("and the room was told", probe._notices.any(func(t): return t.begins_with("Rendered ")))
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
	await probe.get_tree().process_frame
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
	probe.check("%s counted in from a bar before (%.3fs to %.3fs)" % ["playing" if play else "recording", s.position_seconds, at],
			s.counting_in() and absf(s.position_seconds - (from - engine.count_in_lead)) < 0.001 and absf(s.count_in_to - at) < 0.001)
	var took_at := NAN
	var began := Time.get_ticks_msec()
	while s.position_seconds < at + 0.6 and Time.get_ticks_msec() - began < 5000:
		if is_nan(took_at) and (s.taking() if not play else not s.counting_in()):
			took_at = s.position_seconds
		await probe.get_tree().process_frame
	DAW.transport_stop()
	var frames := capture.get_buffer(capture.get_frames_available())
	for i in range(AudioServer.get_bus_effect_count(engine._master_bus) - 1, -1, -1):
		if AudioServer.get_bus_effect(engine._master_bus, i) == capture:
			AudioServer.remove_bus_effect(engine._master_bus, i)
	DAW.set_count_in(0)
	DAW.set_count_in_play(false)
	DAW.set_pre_roll(false)
	probe.check("and %s from the point it stood at on (%.3fs)" % ["played" if play else "took", took_at],
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
		probe.check("with the song under the count (%.1f dB between its clicks)" % quiet, quiet > -40.0)
		probe.check("and on from the record point (%.1f dB)" % song, song > -30.0)
		return
	probe.check("the count was a click on each of its beats (%d of %d, %.2fms on average, each within %.2fms of it)" % [
			offs.size(), int(roundf(beat - map.beat_at(from))), mean, worst],
			offs.size() == int(roundf(beat - map.beat_at(from))) and absf(mean) < SessionProbe.COUNT_IN_TOLERANCE_MS
			and worst < SessionProbe.COUNT_IN_SPREAD_MS)
	probe.check("with nothing of the song under it (%.1f dB)" % quiet, quiet < -60.0)
	probe.check("which plays from the record point on (%.1f dB)" % song, song > -30.0)


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
	await probe.get_tree().create_timer(0.15).timeout
	AudioServer.lock()
	capture.clear_buffer()
	DAW.transport_play()
	var first_frame_at := (DAW.backend as GodotBackend).first_frame_at(s.position_seconds)
	engine._drive_meters(0.0)
	AudioServer.unlock()
	var began := Time.get_ticks_msec()
	while s.position_seconds < to + 0.1 and Time.get_ticks_msec() - began < 6000:
		await probe.get_tree().process_frame
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
	probe.check("the click counted a bar of %d/%d then one of 6/8 (%d of %d, %.2fms on average, each within %.2fms)" % [
			sig.x, sig.y, offs.size(), expected.size(), mean, worst],
			expected.size() == sig.x + 6 and offs.size() == expected.size()
			and absf(mean) < SessionProbe.COUNT_IN_TOLERANCE_MS and worst < SessionProbe.COUNT_IN_SPREAD_MS)
	probe.check("accented on each bar's first count (%.3f against %.3f)" % [quietest_accent, loudest_other],
			quietest_accent > loudest_other * 1.2)
