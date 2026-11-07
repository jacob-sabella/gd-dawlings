class_name SessionProbeRender
extends RefCounted

## The measuring of count-ins, parts and punches, the files sent to the guest and the checks of the same things in a real
## Reaper.
## Moved out of `tools/probe/session_probe.gd` without change of behaviour; the state stays on the probe node, which keeps a one-line delegate for each name another file or a string reaches.

var probe: SessionProbe


func _init(of: SessionProbe) -> void:
	probe = of


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
		await probe.get_tree().process_frame
	var ready_ms := Time.get_ticks_msec() - began
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 8.0
	AudioServer.add_bus_effect(engine._master_bus, capture)
	await probe.get_tree().create_timer(0.1).timeout
	AudioServer.lock()
	capture.clear_buffer()
	DAW.transport_play()
	var first_frame_at := (DAW.backend as GodotBackend).first_frame_at(s.position_seconds)
	engine._drive_meters(0.0)
	AudioServer.unlock()
	began = Time.get_ticks_msec()
	while s.position_seconds < to and Time.get_ticks_msec() - began < 8000:
		await probe.get_tree().process_frame
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
	probe.check("the demo kick follows the tempo's ramp (%d of %d, %.2fms on average, each within %.2fms)" % [
			offs.size(), expected.size(), mean, worst],
			offs.size() == expected.size() and absf(mean) < SessionProbe.PARTS_TOLERANCE_MS and worst < SessionProbe.PARTS_SPREAD_MS)


## A recording punched in and out: begun before the loop range and stopped after it, my take is
## the range and nothing either side.
func _punch_and_measure() -> void:
	var s := DAW.state
	var ha := Session.host_audio
	var map := s.tempo_map()
	var a := map.seconds_at(ceilf(map.beat_at(s.position_seconds)) + 4.0)
	var b := a + SessionProbe.PUNCH_SECONDS
	DAW.set_looping(false)
	DAW.set_loop_range(a, b)
	DAW.set_punch(true)
	# Two armed tracks, each recording one side of the same input: one recording, both placed.
	var was_armed: Array = s.track_indices().filter(func(i): return s.track(i).rec_arm)
	for i in was_armed:
		DAW.set_track_rec_arm(i, false)
	DAW.set_track_input(SessionProbe.HOST_TAKE_TRACK, "audio:#1")
	DAW.set_track_input(SessionProbe.HOST_SIDE_TRACK, "audio:#2")
	DAW.set_track_rec_arm(SessionProbe.HOST_TAKE_TRACK, true)
	DAW.set_track_rec_arm(SessionProbe.HOST_SIDE_TRACK, true)
	ha.target_track = 0
	ha.record_with_host = true
	probe._audio_placed = {}
	probe._placed_all.clear()
	DAW.seek(a - 0.8)
	DAW.transport_record()
	var took := false
	while s.position_seconds < b + 0.4:
		took = took or s.taking()
		await probe.get_tree().process_frame
	DAW.transport_stop()
	var began := Time.get_ticks_msec()
	while probe._placed_all.size() < 2 and Time.get_ticks_msec() - began < 1500:
		await probe.get_tree().process_frame
	ha.record_with_host = false
	DAW.set_punch(false)
	DAW.set_loop_range(0.0, 0.0)
	DAW.set_track_rec_arm(SessionProbe.HOST_TAKE_TRACK, false)
	DAW.set_track_rec_arm(SessionProbe.HOST_SIDE_TRACK, false)
	DAW.set_track_input(SessionProbe.HOST_TAKE_TRACK, "")
	DAW.set_track_input(SessionProbe.HOST_SIDE_TRACK, "")
	for i in was_armed:
		DAW.set_track_rec_arm(i, true)
	var onto: Array = probe._placed_all.map(func(info): return int(info["track"]))
	var levels: Array = probe._placed_all.map(func(info): return _loudest(info["path"]))
	print("two inputs: onto %s, starts %s, peaks %s" % [onto, probe._placed_all.map(func(info): return snappedf(info["start"], 0.00001)),
			levels.map(func(v): return snappedf(v, 0.001))])
	probe.check("one recording went onto both armed tracks, each its own side (%s)" % [onto],
			probe._placed_all.size() == 2 and onto.has(SessionProbe.HOST_TAKE_TRACK) and onto.has(SessionProbe.HOST_SIDE_TRACK))
	if probe._placed_all.size() == 2:
		probe.check("from the same moment", absf(float(probe._placed_all[0]["start"]) - float(probe._placed_all[1]["start"])) < 0.000001)
		# The null sink's monitor carries the click on both sides alike.
		probe.check("each side as loud as the other, as the sink sends them (%.3f, %.3f)" % [levels[0], levels[1]],
				levels.min() > 0.05 and absf(linear_to_db(levels[0]) - linear_to_db(levels[1])) < 0.5)
		probe._audio_placed = probe._placed_all[0] if int(probe._placed_all[0]["track"]) == SessionProbe.HOST_TAKE_TRACK else probe._placed_all[1]
	var start: float = probe._audio_placed.get("start", NAN)
	var seconds: float = probe._audio_placed.get("seconds", NAN)
	print("punch: range %.3f-%.3f, take %.4f for %.4fs (in %+.1f ms, out %+.1f ms)" % [a, b, start, seconds,
			(start - a) * 1000.0, (start + seconds - b) * 1000.0])
	probe.check("recording punched in at the range's start (%+.1f ms)" % ((start - a) * 1000.0),
			took and absf(start - a) < SessionProbe.PUNCH_TOLERANCE)
	probe.check("and out at its end (%+.1f ms)" % ((start + seconds - b) * 1000.0),
			absf(start + seconds - b) < SessionProbe.PUNCH_TOLERANCE)
	for info in probe._placed_all:
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
	var wav := OS.get_temp_dir().path_join("Probe Tone %d.wav" % probe._port)
	DawKitAudioFile.write_wav(wav, tone, 2, 48000)
	var flac := ProjectSettings.globalize_path("res://vendor/dawkit/tests/fixtures/audio/flac/s16_mono_0.flac")
	var why := Session.files.send(PackedStringArray([wav, flac]), SessionProbe.SENT_TRACK, SessionProbe.SENT_AT)
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 2500 and not probe._notices.any(func(t): return t.begins_with("Grace brought in")):
		await probe.get_tree().process_frame
	var took := Time.get_ticks_msec() - began
	DirAccess.remove_absolute(wav)
	# The items come by the mix's own channel, the notice by the room's: a moment apart.
	began = Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 500 and DAW.state.track(SessionProbe.SENT_TRACK).items.all(func(it): return absf(it.start - SessionProbe.SENT_AT) > 0.001):
		await probe.get_tree().process_frame
	var told: Array = probe._notices.filter(func(t): return t.begins_with("Grace brought in"))
	print("sent files: %s in %d ms, told %s" % [why, took, told])
	probe.check("I sent two files from my machine, and the room was told they came in (%s)" % [told],
			why.is_empty() and told.size() == 1 and told[0].contains("Probe Tone") and told[0].contains("s16_mono_0"))
	var mine: Array = DAW.state.track(SessionProbe.SENT_TRACK).items.filter(func(it): return absf(it.start - SessionProbe.SENT_AT) < 0.001)
	probe.check("and I see the first where I let it go (%d)" % mine.size(), mine.size() == 1)


## Host: the guest's files, brought in onto the track it chose, one after the other, and nothing
## of them left in the incoming folder.
func _check_sent_files() -> void:
	# The track's own demo items start later: only the stretch the files went into.
	var items: Array = DAW.state.track(SessionProbe.SENT_TRACK).items.filter(func(it): return it.start >= SessionProbe.SENT_AT - 0.001 and it.start < SessionProbe.SENT_AT + 1.5)
	items.sort_custom(func(a, b): return a.start < b.start)
	var starts: Array = items.map(func(it): return snappedf(it.start, 0.0001))
	var lengths: Array = items.map(func(it): return snappedf(it.length, 0.0001))
	print("sent files: items at %s, lengths %s" % [starts, lengths])
	probe.check("the guest's two files were brought in where it let them go (%s)" % [starts],
			items.size() == 2 and absf(items[0].start - SessionProbe.SENT_AT) < 0.001
			and absf(items[1].start - (SessionProbe.SENT_AT + 1.0)) < 0.001)
	if items.size() == 2:
		probe.check("each as long as its sound (%s)" % [lengths], absf(items[0].length - 1.0) < 0.001
				and absf(items[1].length - 5000.0 / 22050.0) < 0.001)
		for it in items:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioTake.DIR.path_join(it.source)))
	var left := DirAccess.get_files_at(FileSend.INCOMING) if DirAccess.dir_exists_absolute(FileSend.INCOMING) else PackedStringArray()
	probe.check("and nothing of them is left in the incoming folder (%s)" % [left], left.is_empty())


func _check_audio_take() -> void:
	probe.check("the guest's recording was placed (%s)" % [probe._audio_placed], not probe._audio_placed.is_empty())
	probe.check("and the room was told", probe._notices.any(func(t): return t.begins_with("Grace recorded")))
	if probe._audio_placed.is_empty():
		return
	var item: MixState.ItemState = null
	for it in DAW.state.track(SessionProbe.AUDIO_TRACK).items:
		if it.name == probe._audio_placed["name"]:
			item = it
	probe.check("as an item on track %d" % SessionProbe.AUDIO_TRACK, item != null)
	if item == null:
		return
	probe.check("where it was placed (%.4f, %.4f)" % [item.start, probe._audio_placed["start"]],
			absf(item.start - float(probe._audio_placed["start"])) < 0.001)
	var wav := FileAccess.get_file_as_bytes(probe._audio_placed["path"])
	probe.check("its file is a WAV of the whole take (%.2fs)" % probe._audio_placed["seconds"],
			wav.size() == AudioTake.HEADER_BYTES + int(round(float(probe._audio_placed["seconds"]) * AudioTake.RATE)) * 2
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
	probe.check("with a clap on every click the guest heard (%d)" % claps.size(), claps.size() >= 3)
	probe.check("each on the song second it was heard on, worst %.2fms" % (worst * 1000.0),
			worst < SessionProbe.TAKE_TOLERANCE)


## Both takes off again: the host's undo, once for each, latest first.
## The guest's audio take trimmed, turned down and faded through the DAW verbs. On a real Reaper
## the lanes are read back from Reaper after the edits land, so what is checked is what the bridge
## did, not the host's own guess.
func _edit_the_take() -> void:
	var taken: String = probe._audio_placed.get("name", "-")
	var index := func() -> int:
		var items: Array = DAW.state.track(SessionProbe.AUDIO_TRACK).items
		for i in items.size():
			if items[i].name == taken:
				return i
		return -1
	if index.call() < 0:
		probe.check("the take is there to edit", false)
		return
	var it: MixState.ItemState = DAW.state.track(SessionProbe.AUDIO_TRACK).items[index.call()]
	var start := it.start + 0.1
	var end := it.end() - 0.1
	var offset := it.source_offset
	DAW.trim_item(SessionProbe.AUDIO_TRACK, index.call(), start, end)
	DAW.set_item_gain(SessionProbe.AUDIO_TRACK, index.call(), -6.0)
	DAW.set_item_fades(SessionProbe.AUDIO_TRACK, index.call(), 0.05, 0.1)
	# And the guest's MIDI take, two semitones up and onto the beat.
	var played := probe.guesting._take_notes()
	var midi_index: int = DAW.state.track(SessionProbe.TAKE_TRACK).items.find_custom(func(m): return m.name == "Grace take 1")
	if midi_index >= 0:
		DAW.transpose_item(SessionProbe.TAKE_TRACK, midi_index, 2)
		DAW.quantize_item(SessionProbe.TAKE_TRACK, midi_index, 1.0)
	var reads := [0]
	var count := func(): reads[0] += 1
	DAW.timeline_changed.connect(count)
	await probe.get_tree().create_timer(0.6).timeout
	DAW.timeline_changed.disconnect(count)
	it = DAW.state.track(SessionProbe.AUDIO_TRACK).items[index.call()] if index.call() >= 0 else null
	probe.check("I trimmed, turned down and faded the take, and the DAW kept it (%s)"
			% [[it.start, it.end(), it.source_offset - offset, it.gain_db, it.fade_in, it.fade_out] if it else null],
			it != null and absf(it.start - start) < 0.001 and absf(it.end() - end) < 0.001
			and absf(it.source_offset - offset - 0.1) < 0.001 and absf(it.gain_db + 6.0) < 0.01
			and absf(it.fade_in - 0.05) < 0.001 and absf(it.fade_out - 0.1) < 0.001)
	var moved := probe.guesting._take_notes()
	var beat := 60.0 / DAW.state.tempo
	var off_beat := moved.map(func(n): return absf(n[0] / beat - roundf(n[0] / beat)) * beat)
	probe.check("and its MIDI take two semitones up and on the beat (%s, %s)" % [moved.map(func(n): return int(n[2])), off_beat],
			midi_index >= 0 and moved.size() == played.size() and not moved.is_empty()
			and range(moved.size()).all(func(i): return int(moved[i][2]) == int(played[i][2]) + 2)
			and off_beat.all(func(d): return d < 0.002))
	if probe._reaper_resource != "":
		probe.check("as Reaper read it back after the edits (%d reads)" % reads[0], reads[0] > 0)
	for i in 5:
		DAW.undo()


## A track added at the end, renamed, coloured and removed, each read back from Reaper; then all
## undone, so the takes' own undo steps are the next ones again.
func _tracks_in_reaper() -> void:
	# Straight after the take's five undos, which go through the bridge in line with this edit.
	var count := DAW.state.project_track_count
	DAW.add_track(count + 1, "Probe track")
	await probe.get_tree().create_timer(0.7).timeout
	var added := DAW.state.track(count + 1, false)
	DAW.rename_track(count + 1, "Probe renamed")
	await probe.get_tree().create_timer(0.5).timeout
	var renamed := DAW.state.track(count + 1, false)
	var name_read: String = renamed.name if renamed else "-"
	# Its colour, read back by the structure poll from Reaper's own (8 bits a channel).
	var want_colour := Color(0.30, 0.68, 0.86)
	DAW.set_track_colour(count + 1, want_colour)
	await probe.get_tree().create_timer(0.4).timeout
	if renamed:
		renamed.colour = Color.BLACK
	(DAW.backend as ReaperBackend)._structure_due = 0.0
	await probe.get_tree().create_timer(0.6).timeout
	# A stock plugin added to it and removed again, each read back from Reaper's chain.
	DAW.add_fx(count + 1, "ReaComp")
	await probe.get_tree().create_timer(0.6).timeout
	var fx_added: Array = DAW.state.track(count + 1).plugins().map(func(f): return DAW.state.fx(count + 1, f).name) \
			if DAW.state.tracks.has(count + 1) else []
	if not fx_added.is_empty():
		DAW.remove_fx(count + 1, DAW.state.track(count + 1).plugins()[0])
	await probe.get_tree().create_timer(0.6).timeout
	var fx_left: int = DAW.state.track(count + 1).plugins().size() if DAW.state.tracks.has(count + 1) else -1
	probe.check("Reaper added a stock plugin to a track and removed it, read back each time (%s, %d)" % [fx_added, fx_left],
			fx_added.size() == 1 and str(fx_added[0]).contains("ReaComp") and fx_left == 0)
	var colour_read: Color = DAW.state.track(count + 1).colour if DAW.state.tracks.has(count + 1) else Color.BLACK
	probe.check("Reaper took the track's colour and read it back (%s)" % colour_read,
			absf(colour_read.r - want_colour.r) < 0.004 and absf(colour_read.g - want_colour.g) < 0.004
			and absf(colour_read.b - want_colour.b) < 0.004)
	DAW.remove_track(count + 1)
	await probe.get_tree().create_timer(0.7).timeout
	probe.check("Reaper added a track, renamed it and removed it (%d, %s, %d)"
			% [count, name_read, DAW.state.project_track_count],
			added != null and name_read == "Probe renamed" and DAW.state.project_track_count == count
			and DAW.state.track(count + 1, false) == null)
	# The tempo's changes: halved from bar 3, ramping back up from bar 5, read back from Reaper's
	# own markers.
	var tempo := DAW.state.tempo
	var want := [[0.0, tempo, DawKitTempoMap.HOLD], [8.0, tempo * 0.5, DawKitTempoMap.RAMP_SECONDS],
			[16.0, tempo, DawKitTempoMap.HOLD]]
	DAW.set_tempo_map(want)
	await probe.get_tree().create_timer(0.7).timeout
	var got := DAW.state.tempo_points
	var close_enough := got.size() == 3
	for i in mini(got.size(), 3):
		close_enough = close_enough and absf(got[i][0] - want[i][0]) < 0.001 \
				and absf(got[i][1] - want[i][1]) < 0.001 and got[i][2] == want[i][2]
	probe.check("Reaper took the tempo map and read it back (%s)" % [got], close_enough)
	# A marker added, moved and renamed, then removed, each read back from Reaper's timeline.
	var marks := DAW.state.markers
	DAW.add_marker(50.0, "Probe mark")
	await probe.get_tree().create_timer(0.4).timeout
	DAW.edit_marker(50.0, 51.0, "Probe moved")
	await probe.get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	DAW.state.markers = {}
	await probe.get_tree().create_timer(0.5).timeout
	var moved: String = str(DAW.state.markers.get(DAWBackend.marker_key(DAW.state.markers, 51.0), "-"))
	var moved_from := not is_nan(DAWBackend.marker_key(DAW.state.markers, 50.0))
	DAW.remove_marker(51.0)
	await probe.get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	DAW.state.markers = {51.0: "stale"}
	await probe.get_tree().create_timer(0.5).timeout
	probe.check("Reaper moved and renamed a marker, then removed it, read back each time (%s, %s)" % [moved, DAW.state.markers.size()],
			moved == "Probe moved" and not moved_from and is_nan(DAWBackend.marker_key(DAW.state.markers, 51.0))
			and DAW.state.markers.size() == marks.size())
	for i in 10:
		DAW.undo()
	await probe.get_tree().create_timer(0.7).timeout
	probe.check("and undone, it is one tempo again (%s)" % [DAW.state.tempo_points], DAW.state.tempo_points.is_empty())
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
	await probe.get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	s.count_in_bars = 0
	await probe.get_tree().create_timer(0.5).timeout
	probe.check("Reaper took a one-bar count-in and read it back (%d)" % s.count_in_bars, s.count_in_bars == 1)
	var at := 30.0
	DAW.seek(at)
	await probe.get_tree().create_timer(0.2).timeout
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
		await probe.get_tree().process_frame
	DAW.transport_stop()
	probe.check("Reaper counted in a bar before recording (from %.2fs to %.2fs, a bar %.2fs)" % [lowest, at, bar],
			counted and lowest < at - bar * 0.7 and lowest > at - bar - 0.2)
	probe.check("and the take began at the record point (%.3fs)" % took_at, absf(took_at - at) < 0.15)
	# Before playback too: projmetroen &8, read back, and Reaper counting in when it plays.
	DAW.set_count_in_play(true)
	await probe.get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	s.count_in_play = false
	await probe.get_tree().create_timer(0.5).timeout
	probe.check("Reaper took a count before playback and read it back", s.count_in_play)
	DAW.seek(at)
	await probe.get_tree().create_timer(0.2).timeout
	DAW.transport_play()
	lowest = INF
	counted = false
	began = Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < int((bar + 0.4) * 1000.0):
		lowest = minf(lowest, s.position_seconds)
		counted = counted or s.counting_in()
		await probe.get_tree().process_frame
	var recorded := s.recording
	DAW.transport_stop()
	probe.check("and counted in a bar before playing, not recording (from %.2fs to %.2fs)" % [lowest, at],
			counted and not recorded and lowest < at - bar * 0.7 and lowest > at - bar - 0.2)
	DAW.set_count_in_play(false)
	# Pre-roll: Reaper's own, in place of its count-in, read back, and the song run up to the take.
	DAW.set_pre_roll(true)
	await probe.get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	s.pre_roll = false
	s.count_in_bars = 0
	await probe.get_tree().create_timer(0.5).timeout
	probe.check("Reaper took a one-bar pre-roll and read it back (%s, %d)" % [s.pre_roll, s.count_in_bars],
			s.pre_roll and s.count_in_bars == 1)
	DAW.seek(at)
	await probe.get_tree().create_timer(0.2).timeout
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
		await probe.get_tree().process_frame
	DAW.transport_stop()
	probe.check("Reaper pre-rolled a bar before recording (from %.2fs to %.2fs), and took from the record point (%.3fs)" % [
			lowest, at, took_at], counted and lowest > at - 2.0 * bar - 0.2 and lowest <= at - bar + 0.2
			and absf(took_at - at) < 0.15)
	DAW.set_pre_roll(false)
	DAW.set_count_in(0)
	# And its record mode: time selection auto-punch, read back.
	DAW.set_punch(true)
	await probe.get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	s.punch = false
	await probe.get_tree().create_timer(0.5).timeout
	probe.check("Reaper took punching in and out and read it back", s.punch)
	# A track's record input: the stereo pair from input 1, read back, and put back.
	var was := s.input_of(3)
	DAW.set_track_input(3, "in:1/2")
	await probe.get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	s.track(3).input = ""
	await probe.get_tree().create_timer(0.5).timeout
	probe.check("Reaper took a track's input and read it back (%s, of %d)" % [s.input_of(3), s.inputs.size()],
			s.input_of(3) == "in:1/2")
	if ReaperBackend.input_code(was) != ReaperBackend.INPUT_UNKNOWN:
		DAW.set_track_input(3, was)
	# A change of time signature, onto Reaper's tempo markers and back, the tempo left as it was.
	var sig := Vector2i(s.beats_per_bar, s.beat_unit)
	var tempo_before: Array = s.tempo_points.duplicate(true)
	DAW.set_time_signature_map([[0.0, sig.x, sig.y], [8.0, 7, 8]])
	await probe.get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	s.time_signature_points = []
	await probe.get_tree().create_timer(0.5).timeout
	probe.check("Reaper took a change to 7/8 at bar 3 and read it back (%s, %s)" % [s.time_signature_points, s.bar_beat(s.seconds_at_beat(8.5))],
			s.time_signature_points == [[0.0, sig.x, sig.y], [8.0, 7, 8]] and s.bar_beat(s.seconds_at_beat(8.5)) == "3.2.00")
	probe.check("with its tempo as it was (%s)" % [s.tempo_points], s.tempo_points == tempo_before)
	DAW.set_time_signature_map([[0.0, sig.x, sig.y]])
	await probe.get_tree().create_timer(0.3).timeout
	(DAW.backend as ReaperBackend)._timeline_due = 0.0
	await probe.get_tree().create_timer(0.5).timeout
	probe.check("and taken away again (%s)" % [s.time_signature_points], s.time_signature_points.is_empty() and s.tempo_points == tempo_before)
	DAW.set_punch(false)
	await probe.get_tree().create_timer(0.2).timeout
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
	var first := SessionProbeRoom._first_send(DAW.state)
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
	await probe.get_tree().create_timer(0.8).timeout
	var back := true
	for target in lanes:
		back = back and ReaperBackend._same_lane(t.automation.get(target, []), lanes[target])
	probe.check("Reaper took the lanes as envelopes and read them back (%s)" % [t.automation], back)
	probe.check("a send's (%s on %d: %s)" % [send_target, first[0], DAW.state.track(first[0]).automation.get(send_target)],
			ReaperBackend._same_lane(DAW.state.track(first[0]).automation.get(send_target, []), send_lane))
	probe.check("and a plugin's (%s on %d: %s)" % [fx_target, fx_track, DAW.state.track(fx_track).automation.get(fx_target)],
			ReaperBackend._same_lane(DAW.state.track(fx_track).automation.get(fx_target, []), fx_lane))
	probe.check("and the master's (%s)" % [DAW.state.master.automation],
			ReaperBackend._same_lane(DAW.state.master.automation.get("volume", []), master_lane))
	# Reaper reads its envelopes while it plays, into the null sink.
	DAW.seek(1.0)
	DAW.transport_play()
	await probe.get_tree().create_timer(0.5).timeout
	probe.check("and its faders follow them as it plays (%.2f dB, pan %.2f, mute %s, master %.2f dB)" % [t.volume_db, t.pan, t.mute, DAW.state.master.volume_db],
			absf(t.volume_db + 6.0) < 0.1 and t.pan < 0.01 and not t.mute and absf(DAW.state.master.volume_db + 3.0) < 0.1)
	DAW.seek(5.0)
	await probe.get_tree().create_timer(0.5).timeout
	probe.check("further on, further down, and muted (%.2f dB, %s)" % [t.volume_db, t.mute],
			absf(t.volume_db + 18.0) < 0.1 and t.mute)
	DAW.transport_stop()
	DAW.set_track_automation_mode(1, DAW.AUTOMATION_LATCH)
	await probe.get_tree().create_timer(0.6).timeout
	probe.check("Reaper's track is in latch, and says so (%d)" % t.automation_mode, t.automation_mode == DAW.AUTOMATION_LATCH)
	DAW.set_track_automation_mode(1, DAW.AUTOMATION_READ)
	# The master's mode, told to Reaper and read back from it: forgotten here, the next report
	# of the arrangement puts it back.
	DAW.set_track_automation_mode(0, DAW.AUTOMATION_LATCH)
	await probe.get_tree().create_timer(0.6).timeout
	DAW.state.master.automation_mode = DAW.AUTOMATION_READ
	DAW.backend.set(&"_timeline_due", 0.0)
	await probe.get_tree().create_timer(1.0).timeout
	probe.check("Reaper's master is in latch, and says so (%d)" % DAW.state.master.automation_mode,
			DAW.state.master.automation_mode == DAW.AUTOMATION_LATCH)
	DAW.set_track_automation_mode(0, DAW.AUTOMATION_READ)
	await probe.get_tree().create_timer(0.6).timeout
	probe.check("and back in read", DAW.state.master.automation_mode == DAW.AUTOMATION_READ)
	for _i in 6:
		DAW.undo()
	DAW.seek(0.0)
	await probe.get_tree().create_timer(0.8).timeout
	probe.check("undone, the envelopes are gone (%s)" % [t.automation], t.automation.is_empty() and t.automation_mode == 0
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
	DAW.set_automation(SessionProbe.RENDER_TRACK, "volume", [[0.0, -6.0, DawKitAutomation.HOLD], [2.0, -18.0, DawKitAutomation.HOLD]])
	DAW.set_loop_range(1.0, 3.0)
	DAW.set_looping(true)
	await probe.get_tree().create_timer(0.6).timeout
	var with_lane := await probe.guesting._reaper_render_levels()
	DAW.undo()
	await probe.get_tree().create_timer(0.6).timeout
	var without := await probe.guesting._reaper_render_levels()
	# Without a lane the fader is the level, and it need not be at 0 dB.
	var fader := s.track(SessionProbe.RENDER_TRACK).volume_db
	DAW.set_loop_range(was[1], was[2])
	DAW.set_looping(was[0])
	probe.check("Reaper rendered the loop, mix and stems, twice (%s, %s)" % [with_lane, without],
			with_lane.size() == 4 and without.size() == 4)
	if with_lane.size() == 4 and without.size() == 4:
		probe.check("its files are the loop and Reaper's tail of %.1fs (%.3fs)" % [DAWBackend.RENDER_TAIL_SECONDS, with_lane[2]],
				absf(float(with_lane[2]) - (2.0 + DAWBackend.RENDER_TAIL_SECONDS)) < 0.01)
		var a: float = with_lane[0] - without[0]
		var b: float = with_lane[1] - without[1]
		probe.check("and track %d's stem is the lane: %.2f dB, then %.2f dB, against its fader at %.2f dB" % [SessionProbe.RENDER_TRACK, a, b, fader],
				absf(a - (-6.0 - fader)) < 0.2 and absf(b - (-18.0 - fader)) < 0.2)
		DirAccess.remove_absolute(with_lane[3])
