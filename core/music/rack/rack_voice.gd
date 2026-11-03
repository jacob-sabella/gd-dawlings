class_name RackVoice
extends Node

## The modular room, sounding: the engine running as a process (RackEngine), the room's patch told to
## it, the player's notes into its KEYS module, the song's clock into its CLOCK and sequencers, and
## its sound played through a track of the song (InputMonitor.feeds), so it goes through that track's
## chain, fader, sends and meters like any monitored input. REC catches what it plays as a take on that
## track at the song position it began (`record_start` / `record_stop`).
##
## Its meters, how loud each module is now, are what the room's lights follow (`meters`, `level`).

signal changed()

const FOLLOW_SECONDS := 0.25

var engine := RackEngine.new()
var source: RackEngine.Source
var patch := RackPatch.empty()
## The track the rack plays through, 0 for none (the sound is then not heard).
var track := 0
## Whether the DAW's transport drives the rack's clock.
var follow_daw := true
## Offered to the suite: {playing, beats, bpm} instead of DAW.state.
var transport_override: Callable = Callable()
var _sent := RackPatch.empty()
var _was_playing := false
var _bpm := 0.0
var _since_sync := 0.0
var _take_from := -1.0
var _take_track := 0
var meters := {}
## A smoothed loudness of the whole rack, 0..1, and a hit pulse (set on a rise), for lights.
var level := 0.0
var hit := 0.0
var _last_peak := 0.0
var _held := {}


func _ready() -> void:
	source = RackEngine.Source.new(engine)


func _exit_tree() -> void:
	shutdown()


func start() -> bool:
	if source == null:
		source = RackEngine.Source.new(engine)
	if not engine.start():
		return false
	_sent = RackPatch.empty()
	_bpm = 0.0
	_sync_patch()
	_publish()
	return true


func shutdown() -> void:
	InputMonitor.feeds.erase(track)
	engine.stop()


func running() -> bool:
	return engine.running()


## The room's patch, sent to the engine as the difference from what it has: modules added or taken out,
## cables and knobs changed, so a sounding tail is not cut by turning a knob.
func set_patch(p: Dictionary) -> void:
	patch = RackPatch.sanitize(p)
	_sync_patch()
	changed.emit()


func _sync_patch() -> void:
	if not engine.running():
		return
	var was: Dictionary = _sent
	var now: Dictionary = patch
	var lines := PackedStringArray()
	var fresh := {}
	for id in was["modules"]:
		if not now["modules"].has(id) or now["modules"][id]["type"] != was["modules"][id]["type"]:
			lines.append("remove %s" % id)
	for id in now["modules"]:
		if not was["modules"].has(id) or now["modules"][id]["type"] != was["modules"][id]["type"]:
			lines.append("add %s %s" % [id, now["modules"][id]["type"]])
			fresh[id] = true
	for c in was["cables"]:
		if not now["cables"].has(c) and now["modules"].has(String(c[1]).get_slice(".", 0)) \
				and was["modules"].has(String(c[1]).get_slice(".", 0)):
			lines.append("uncable %s" % c[1])
	for id in now["modules"]:
		var knobs: Dictionary = now["modules"][id]["knobs"]
		var old: Dictionary = was["modules"][id]["knobs"] if was["modules"].has(id) \
				and was["modules"][id]["type"] == now["modules"][id]["type"] else {}
		for k in knobs:
			if not old.has(k) or not is_equal_approx(float(old[k]), float(knobs[k])):
				lines.append(RackPatch.knob_line(id, k, float(knobs[k])))
	for c in now["cables"]:
		if not was["cables"].has(c) or fresh.has(String(c[0]).get_slice(".", 0)) \
				or fresh.has(String(c[1]).get_slice(".", 0)):
			lines.append("cable %s %s" % [c[0], c[1]])
	# A cable that came out from an input it shared (sums) goes with the engine's uncable of the whole
	# input: put the ones that should still be there back.
	var touched := {}
	for c in was["cables"]:
		if not now["cables"].has(c):
			touched[c[1]] = true
	for c in now["cables"]:
		if touched.has(c[1]) and was["cables"].has(c) and not fresh.has(String(c[0]).get_slice(".", 0)) \
				and not fresh.has(String(c[1]).get_slice(".", 0)):
			lines.append("cable %s %s" % [c[0], c[1]])
	engine.say_all(lines)
	_sent = now.duplicate(true)


## One knob, at once (a hand turning it): the patch and the engine, with no diff.
func knob(id: String, k: String, v01: float) -> void:
	if RackPatch.set_knob(patch, id, k, v01):
		_sent = patch.duplicate(true)
		engine.say(RackPatch.knob_line(id, k, v01))


func note_on(pitch: int, velocity := 100) -> void:
	_held[pitch] = true
	engine.say("note_on %d %d" % [pitch, velocity])


func note_off(pitch: int) -> void:
	_held.erase(pitch)
	engine.say("note_off %d" % pitch)


func all_off() -> void:
	for pitch in _held.keys():
		engine.say("note_off %d" % pitch)
	_held.clear()


func bend(v: float) -> void:
	engine.say("bend %f" % v)


func cc(k: int, v: int) -> void:
	engine.say("cc %d %d" % [k, v])


## Play through `t` (a track index), or nothing at 0.
func set_track(t: int) -> void:
	if t != track:
		InputMonitor.feeds.erase(track)
	track = t
	_publish()
	changed.emit()


func _publish() -> void:
	if track > 0 and engine.running() and source != null:
		InputMonitor.feeds[track] = source
	else:
		InputMonitor.feeds.erase(track)


func _transport() -> Dictionary:
	if transport_override.is_valid():
		return transport_override.call()
	var st: MixState = DAW.state if DAW != null else null
	if st == null:
		return {"playing": false, "beats": 0.0, "bpm": 120.0}
	return {"playing": st.playing, "beats": st.position_seconds * st.tempo / 60.0, "bpm": st.tempo}


func _process(delta: float) -> void:
	if not engine.running():
		return
	engine.poll()
	meters = engine.meters
	var peak := 0.0
	for id in patch["modules"]:
		if patch["modules"][id]["type"] == "out":
			peak = float(meters.get(id, 0.0))
	level = lerpf(level, clampf(peak, 0.0, 1.0), clampf(delta * 8.0, 0.0, 1.0))
	hit = maxf(hit - delta * 3.0, 0.0)
	if peak > _last_peak + 0.12:
		hit = 1.0
	_last_peak = peak
	if follow_daw:
		_since_sync += delta
		var tp := _transport()
		var playing: bool = tp["playing"]
		if not is_equal_approx(_bpm, float(tp["bpm"])):
			_bpm = float(tp["bpm"])
			engine.say("bpm %f" % _bpm)
		if playing and not _was_playing:
			engine.say("play %f" % float(tp["beats"]))
			_since_sync = 0.0
		elif not playing and _was_playing:
			engine.say("stop")
		elif playing and _since_sync > FOLLOW_SECONDS:
			# The song moved under the rack (a seek, a loop): follow it.
			_since_sync = 0.0
			if absf(float(tp["beats"]) - engine.running_beat) > 0.5:
				engine.say("play %f" % float(tp["beats"]))
		_was_playing = playing


## Begin catching what the rack plays, to put on the rack's track at `song_seconds` when it ends.
func record_start(song_seconds: float) -> bool:
	if track <= 0 or not engine.running() or source == null:
		return false
	_take_from = song_seconds
	_take_track = track
	source.tape(true)
	return true


func recording() -> bool:
	return source != null and source.taking()


## End the take: written as a WAV and put on the track as audio at the song position it began. The
## frames, or an empty array if there was nothing; the host only places it (DAW.import_audio).
func record_stop() -> Dictionary:
	if source == null or not source.taking():
		return {"error": "not recording"}
	var frames := source.take_tape()
	source.tape(false)
	if frames.size() < RackEngine.RATE / 20:
		return {"error": "nothing was played"}
	var dir := OS.get_user_data_dir().path_join("rack")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("rack_take_%d.wav" % Time.get_ticks_msec())
	if not RackEngine.write_wav(path, frames):
		return {"error": "could not write the take"}
	var made := DAW.import_audio(path, _take_track, _take_from)
	DirAccess.remove_absolute(path)
	made["frames"] = frames.size()
	return made
