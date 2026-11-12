class_name SingerDemo
extends RefCounted

## The vocal booth's singer shown end to end, for a clip or a shot (`--singer-demo`): in the studio, stood at the
## booth, a key held to breathe it, a hand takes the jaw and then the tongue and shapes a vowel (the head's own grips,
## grabbed as a hand grabs them); then a 4-bar chorus of lyrics is put on a new MIDI track, the singer is told to sing
## that part onto a track of its own, the song records from a bar before the chorus to its end, and plays back from
## the same place. Every
## step is the game's own path (the grips, SingerHost.ask, DAW's transport); the demo only does what a player would.
## It prints `SINGER_DEMO` lines a run can be checked by: the take's place against where recording began.
## SINGER_DEMO_SOLO=1 solos the singer's track from REC on, so a listening guest hears the voice and nothing else.
##
## Its clock is the frames' delta, so under the movie writer it runs in the movie's time. The movie writer runs the
## game at its own pace, though, and the singer's engine (a process of its own) in real time, so a movie of it has
## no singing and no take: SINGER_DEMO_CLIP=<dir> makes the clip in real time instead, the view 15 times a second
## (frames as JPEGs with the times they were taken) and the song's mix as clip.wav from the first frame, for
## ffmpeg to join (tools/singer_clip.sh).
##
## On a guest (`--join ... --singer-demo`) it drives nothing and watches instead: what the host sends of its
## singer (`/singer/live`: the syllables, the head's outlines), whether the guest's own head moves with them, and
## how loud the host's mix arrives (Session.mix_feed) while the singer sings. `SINGER_GUEST` lines say so.

const CHORUS := ["[%s]Light the line and sing it back", "[%s]every word a little higher",
		"[%s]hold the note until it cracks", "[%s]and the room becomes a choir"]
## The chorus, a bar a line: [beat in the bar, MIDI, beats], eight notes a bar, as many as each line's syllables.
const TUNE := [
	[[0, 64, 1], [1, 64, 0.5], [1.5, 67, 0.5], [2, 69, 1], [3, 67, 0.5], [3.5, 64, 0.5]],
	[[0, 62, 0.5], [0.5, 64, 0.5], [1, 67, 0.5], [1.5, 69, 0.5], [2, 72, 0.5], [2.5, 71, 0.5], [3, 69, 1]],
	[[0, 64, 1], [1, 67, 0.5], [1.5, 69, 0.5], [2, 71, 1.5], [3.5, 69, 0.5]],
	[[0, 67, 0.5], [0.5, 69, 0.5], [1, 67, 0.5], [1.5, 64, 0.5], [2, 62, 0.5], [2.5, 64, 1.5]],
]

var shot: Node
var t := 0.0
var _step := 0
var _melody := 0
var _take := 0
var _chorus_at := 0.0
var _bar := 2.0
var _rec_from := -1.0
var _rec_seen := false
var _grip: Node3D
var _grip_from := Vector3.ZERO
var _hand := Node.new()
var _heard := 0.0
var _singer_heard := 0.0
var _snapped := {}
var _seen_syllables := {}
var _live_at := 0
var _live_updates := 0
var _head_moved := 0.0
var _head_was := Vector2.ZERO
var _mix_singing := 0.0
var _mix_quiet := 0.0
var _watch_print := 0.0
var _trace_left := 0.0
var _clip_dir := OS.get_environment("SINGER_DEMO_CLIP")
var _clip_rec: AudioEffectRecord
var _beat_heard := 0.0
var _creature_heard := 0.0
var _stone := -1
var _looked_down := false
var _at_perch := false
## The Monitor bus too: under Reaper the singer plays there (RackVoice's direct player), not on the Mix bus.
var _clip_monitor: AudioEffectRecord
var _clip_bus := 0
var _clip_t0 := 0
var _clip_next := 0
var _clip_times := PackedInt64Array()


func _init(of: Node) -> void:
	shot = of


func _studio() -> Studio:
	return shot.get_tree().current_scene.get_node_or_null("Studio") as Studio


func step(delta: float) -> void:
	t += delta
	_clip_frame()
	var studio := _studio()
	if studio == null or DAW.state == null:
		return
	if not Session.is_authority():
		_watch(studio, delta)
		return
	if Session.role == Session.Role.HOST:
		_watch_print += delta
		if _watch_print >= 3.0:
			_watch_print = 0.0
			print("SINGER_HOST at %.1f s: guests %d, feed %s" % [t, Session.participants.size() - 1,
					JSON.stringify(Session.mix_feed.stats() if Session.mix_feed != null else {})])
	var host := studio.singer_host
	match _step:
		0:
			if t < 0.5:
				return
			_set_up(studio)
			_step = 1
		1:
			if t < 1.2:
				return
			host.ask("set", ["mode", SingerRow.Mode.VOWEL])
			# the singer's track first (REC makes it when there is none), so the vowel shaped by hand is heard: a key
			# held at the booth breathes it on A3 while the hands move the mouth
			host.ask("track", [])
			host.ask("play", [57, true])
			_take_grip(studio, "jaw")
			_step = 2
		2:
			# the jaw drawn down and forward, slowly, then back up a little: "ah" toward "o"
			var k := clampf((t - 1.2) / 2.0, 0.0, 1.0)
			_move_grip(Vector3(0.0, -0.012 * sin(k * PI * 0.8), 0.0))
			if t >= 2.6 and not _snapped.has("grab"):
				_snap("grab")
			if t >= 3.4:
				_let_grip()
				_take_grip(studio, "tongue")
				_step = 3
		3:
			# the tongue forward and up, toward "ee"
			var k := clampf((t - 3.4) / 2.0, 0.0, 1.0)
			_move_grip(Vector3(0.012 * k, 0.008 * sin(k * PI), 0.0))
			if t >= 5.6:
				_let_grip()
				host.ask("play", [57, false])
				_step = 4
		4:
			host.ask("set", ["mode", SingerRow.Mode.SING])
			host.ask("part", [_melody])
			_rec_from = maxf(_chorus_at - _bar, 0.0)
			DAW.seek(_rec_from)
			_step = 5
		5:
			if t < 6.4:
				return
			# SINGER_DEMO_ARM=1 (a probe): the take's track armed first, to see whether Reaper records without one
			if OS.get_environment("SINGER_DEMO_ARM") == "1":
				host.ask("track", [])
				DAW.set_track_rec_arm(int(studio.singer_row["track"]), true)
			# REC on the desk: it makes the Singer track the take goes on, and records the song
			studio.singer_booth.keys["REC"].down.emit(true)
			_take = int(studio.singer_row["track"])
			# SINGER_DEMO_SOLO=1: the singer's track alone, so what a guest hears of the chorus is the voice
			if OS.get_environment("SINGER_DEMO_SOLO") == "1":
				DAW.set_track_solo(_take, true)
			print("SINGER_DEMO recording from %.3f s, the chorus at %.3f s" % [_rec_from, _chorus_at])
			_step = 6
		6:
			_watch_print += delta
			if _watch_print >= 2.0:
				_watch_print = 0.0
				print("SINGER_DEMO transport: playing %s recording %s at %.2f s, the singer's track %d armed %s" % [
						DAW.state.playing, DAW.state.recording, DAW.state.position_seconds, _take,
						DAW.state.tracks[_take].rec_arm if DAW.state.tracks.has(_take) else "-"])
			# Reaper reports its transport back a little later: until it says it records from where the take
			# began, the play position is still the old one and says nothing about the chorus
			if not _rec_seen:
				_rec_seen = DAW.state.recording and DAW.state.position_seconds < _chorus_at + _bar
				return
			if DAW.state.position_seconds > _chorus_at + 1.6 * _bar and not _snapped.has("sing"):
				_snap("sing")
			if DAW.state.position_seconds < _chorus_at + 4.0 * _bar + 0.3:
				return
			studio.singer_booth.keys["REC"].down.emit(true)
			_step = 7
			t = 0.0
		7:
			if t < 1.0:
				return
			var took := _the_take()
			print("SINGER_DEMO take: ", took)
			# the part off, so what is heard back is the take alone
			host.ask("part", [0])
			DAW.seek(_rec_from)
			_step = 8
		8:
			if t < 1.5:
				return
			DAW.transport_play()
			_step = 9
		9:
			# Played back: the take's track is loud through the chorus, the singer silent (its part is off).
			var p := DAW.state.position_seconds
			var tr: MixState.TrackState = DAW.state.tracks.get(_take)
			if tr != null and p > _chorus_at + 0.2 and p < _chorus_at + 4.0 * _bar:
				_heard = maxf(_heard, maxf(tr.vu_l, tr.vu_r))
				_singer_heard = maxf(_singer_heard, studio.singer.level if studio.singer != null else 0.0)
				if p > _chorus_at + 1.5 * _bar and not _snapped.has("playback"):
					_snap("playback")
			if p >= _chorus_at + 4.0 * _bar:
				print("SINGER_DEMO played back: the take's track peaked at %.3f, the singer's own voice at %.3f" % [_heard, _singer_heard])
				DAW.transport_stop()
				_step = 10
				t = 0.0
		10:
			# The beatbox: BEAT mode, its 16 steps (the row's default beat) played by SEQ, locked to the song.
			if t < 0.5:
				return
			host.ask("set", ["mode", SingerRow.Mode.BEAT])
			host.ask("set", ["seq", true])
			DAW.seek(0.0)
			DAW.transport_play()
			_beat_heard = 0.0
			_step = 11
			t = 0.0
		11:
			_beat_heard = maxf(_beat_heard, studio.singer.level if studio.singer != null else 0.0)
			if t >= 1.5 and not _looked_down:
				# a look down at the desk: its pads and the 16 steps of the pattern
				_looked_down = true
				studio.walker.pitch = -0.62
				studio.walker._place_camera()
			if t >= 2.5 and not _snapped.has("beat"):
				_snap("beat")
			if t < 4.0:
				return
			print("SINGER_DEMO beatbox: %s, SEQ on with the song, the voice peaked at %.3f" % [
					String(studio.singer_row["beat"]), _beat_heard])
			DAW.transport_stop()
			host.ask("set", ["seq", false])
			_step = 12
			t = 0.0
		12:
			# The venue's creature on its perch: its stones struck up the song's scale, one every 0.4 s.
			if host.perch == null:
				_step = 13
				return
			if not _at_perch:
				# across the booth to the perch, standing in front of it as a player would to strike it (the booth put
				# on BEAST too, the creature's own mode: on a guest it marks where its trace is)
				_at_perch = true
				host.ask("set", ["mode", SingerRow.Mode.BEAST])
				var pb := host.perch.global_transform
				var pf := Vector3(pb.basis.z.x, 0, pb.basis.z.z).normalized()
				var at := pb.origin + pf * 0.95
				studio.walker.global_position = Vector3(at.x, studio.walker.global_position.y, at.z)
				studio.walker.yaw = atan2(pf.x, pf.z)
				studio.walker.pitch = -0.3
				studio.walker._place_camera()
			var n := int(t / 0.4)
			if n < Bestiary.STONES and n != _stone:
				_stone = n
				host.ask("strike", [n])
			if host.creature != null:
				_creature_heard = maxf(_creature_heard, host.creature.level)
			if t >= 1.8 and not _snapped.has("beast"):
				_snap("beast")
			if t < 3.6:
				return
			print("SINGER_DEMO creature: the %s on its perch, %d stones struck, its voice peaked at %.3f" % [
					String(host.perch.spec.get("title", "?")), Bestiary.STONES, _creature_heard])
			_clip_end()
			_step = 13
			t = 0.0
		13:
			# a clip run ends here rather than at the screenshot tool's last tick (whose time depends on the frame rate)
			if _clip_dir != "" and t >= 1.0:
				shot.get_tree().quit()


## The guest's side: what arrives of the host's singer, what the guest's head does with it, what it hears.
func _watch(studio: Studio, delta: float) -> void:
	var live: Dictionary = DAW.state.singer_live
	var sung := String(live.get("sung", ""))
	if int(live.get("at", 0)) != _live_at:
		_live_at = int(live.get("at", 0))
		_live_updates += 1
	if sung != "":
		_seen_syllables[sung] = true
	# the head's outlines as the guest was sent them (its SingerHead draws these): how far they travel
	var booth := studio.singer_booth
	if booth != null and booth.head != null:
		var probe := Vector2.ZERO
		var frame: Dictionary = live.get("frame", {})
		var got: Variant = frame.get("lines", [])
		var outlines: Array = (got as Dictionary).values() if got is Dictionary else got
		for l in outlines:
			var pl: PackedVector2Array = l
			if pl.size() > 0:
				probe += pl[pl.size() / 2]
		if _head_was != Vector2.ZERO:
			_head_moved += probe.distance_to(_head_was)
		_head_was = probe
	var feed: MixFeed = Session.mix_feed
	var level := float(feed.stats().get("level", 0.0)) if feed != null else 0.0
	if sung != "" and SingerLive.fresh(live).size() > 0:
		_mix_singing = maxf(_mix_singing, level)
	else:
		_mix_quiet = maxf(_mix_quiet, level)
	_trace_left -= delta
	if _trace_left <= 0.0:
		_trace_left = 0.25
		print("SINGER_TRACE %.2f %.4f %s %s %s" % [t, level, "live" if not SingerLive.fresh(live).is_empty() else "-",
				sung if sung != "" else "-", SingerRow.MODES[int(studio.singer_row.get("mode", 0))]])
	if sung != "" and _seen_syllables.size() >= 6 and not _snapped.has("guest"):
		_snap("guest")
	_watch_print += delta
	if _watch_print >= 2.0:
		_watch_print = 0.0
		print("SINGER_GUEST at %.1f s: %d live updates, %d syllables heard named (%s), the head's outlines moved %.1f cm, the host's mix at %.3f while singing (%.3f otherwise), feed %s" % [
				t, _live_updates, _seen_syllables.size(), " ".join(PackedStringArray(_seen_syllables.keys().slice(0, 8))),
				_head_moved, _mix_singing, _mix_quiet, JSON.stringify(feed.stats() if feed != null else {})])


func _set_up(studio: Studio) -> void:
	var st := DAW.state
	_bar = 240.0 / maxf(st.tempo, 1.0)
	_chorus_at = 0.0
	for at in st.markers:
		if String(st.markers[at]).begins_with("Chorus 1"):
			_chorus_at = float(at)
	var count := st.track_indices().size()
	DAW.add_track(count + 1, "Melody")
	_melody = count + 1
	var rows: Array = []
	for b in TUNE.size():
		for n: Array in TUNE[b]:
			var on := _chorus_at + (b + float(n[0]) / 4.0) * _bar
			rows.append([on, on + float(n[2]) / 4.0 * _bar * 0.95, int(n[1]), 96, 0])
	DAW.insert_midi_take(_melody, _chorus_at, _chorus_at + 4.0 * _bar, rows, "Chorus melody")
	var lrc := PackedStringArray()
	for i in CHORUS.size():
		var s := _chorus_at + i * _bar
		lrc.append(CHORUS[i] % ("%02d:%05.2f" % [int(s / 60.0), fmod(s, 60.0)]))
	DAW.set_lyrics("\n".join(lrc))
	print("SINGER_DEMO set up: melody on %d, %d notes, a bar %.3f s" % [_melody, rows.size(), _bar])


func _take_grip(studio: Studio, part: String) -> void:
	var booth := studio.singer_booth
	if booth == null:
		return
	_grip = booth.head.grips.get(part)
	if _grip == null:
		return
	_grip_from = _grip.global_position
	(_grip as ControlAffordance).grab_begin(_hand, _grip_from)


func _move_grip(by: Vector3) -> void:
	if _grip != null:
		(_grip as ControlAffordance).grab_move(_hand, _grip_from + _grip.get_parent_node_3d().global_basis * by)


func _let_grip() -> void:
	if _grip != null:
		(_grip as ControlAffordance).grab_end(_hand)
	_grip = null


## The take on the singer's track: where it starts against where recording began, and how long.
func _the_take() -> Dictionary:
	var tr: MixState.TrackState = DAW.state.tracks.get(_take)
	if tr == null or tr.items.is_empty():
		return {"error": "no take on the singer's track"}
	var it: MixState.ItemState = tr.items[-1]
	return {"start": it.start, "length": it.length, "off_ms": (it.start - _rec_from) * 1000.0}



## A frame of the real-time clip when one is due (SINGER_DEMO_CLIP), the song's mix caught from the first.
func _clip_frame() -> void:
	if _clip_dir == "":
		return
	var now := Time.get_ticks_msec()
	if _clip_rec == null:
		# The song's mix is on the Mix bus (AudioPorts): from there it leaves for its own stream and the bus runs
		# on into a muted one, so the master hears none of it. Recorded where it is heard, from the first frame.
		var mix := AudioServer.get_bus_index(AudioPorts.bus(AudioPorts.MIX))
		_clip_bus = mix if mix >= 0 else 0
		DirAccess.make_dir_recursive_absolute(_clip_dir)
		_clip_rec = AudioEffectRecord.new()
		AudioServer.add_bus_effect(_clip_bus, _clip_rec)
		_clip_rec.set_recording_active(true)
		var monitor := AudioServer.get_bus_index(AudioPorts.bus(AudioPorts.MONITOR))
		if monitor >= 0 and monitor != _clip_bus:
			_clip_monitor = AudioEffectRecord.new()
			AudioServer.add_bus_effect(monitor, _clip_monitor)
			_clip_monitor.set_recording_active(true)
		_clip_t0 = now
		_clip_next = now
		# The wall clock at the first frame, for a clip whose sound is caught outside the game (singer_clip.sh
		# --reaper: the song plays in Reaper, so the Mix bus has only the singer).
		var at := FileAccess.open(_clip_dir.path_join("t0"), FileAccess.WRITE)
		at.store_string("%d\n" % int(Time.get_unix_time_from_system() * 1000.0))
		at.close()
	if now < _clip_next or not _clip_rec.is_recording_active():
		return
	_clip_next += 1000 / 15
	var img := shot.get_viewport().get_texture().get_image()
	img.resize(1280, int(1280.0 * img.get_height() / img.get_width()) / 2 * 2, Image.INTERPOLATE_BILINEAR)
	img.save_jpg(_clip_dir.path_join("f%05d.jpg" % _clip_times.size()), 0.88)
	_clip_times.append(now - _clip_t0)


## The clip's sound and its frames' times written out (clip.wav, frames.ffconcat), for ffmpeg.
func _clip_end() -> void:
	if _clip_rec == null or not _clip_rec.is_recording_active():
		return
	_clip_rec.set_recording_active(false)
	var got := _clip_rec.get_recording()
	if got != null:
		got.save_to_wav(_clip_dir.path_join("clip.wav"))
	if _clip_monitor != null:
		_clip_monitor.set_recording_active(false)
		var heard := _clip_monitor.get_recording()
		if heard != null:
			heard.save_to_wav(_clip_dir.path_join("clip_monitor.wav"))
	var lines := PackedStringArray(["ffconcat version 1.0"])
	for i in _clip_times.size():
		lines.append("file f%05d.jpg" % i)
		var next: int = _clip_times[i + 1] if i + 1 < _clip_times.size() else _clip_times[i] + 1000 / 15
		lines.append("duration %.4f" % ((next - _clip_times[i]) / 1000.0))
	lines.append("file f%05d.jpg" % (_clip_times.size() - 1))
	var f := FileAccess.open(_clip_dir.path_join("frames.ffconcat"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("SINGER_DEMO clip: %d frames over %.1f s in %s" % [_clip_times.size(), (_clip_times[-1] if _clip_times.size() > 0 else 0) / 1000.0, _clip_dir])


## The view now, as SINGER_DEMO_SHOTS/<name>.png, when that is set (a run in real time, not the movie).
func _snap(name: String) -> void:
	_snapped[name] = true
	var dir := OS.get_environment("SINGER_DEMO_SHOTS")
	if dir == "":
		return
	var img := shot.get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	print("SINGER_DEMO shot ", dir.path_join(name + ".png"))
