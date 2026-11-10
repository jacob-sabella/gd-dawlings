class_name RackVoice
extends Node

## The modular room, sounding: the engine running as a process (RackEngine), the room's patch told to
## it, the player's notes into its KEYS module, the song's clock into its CLOCK and sequencers, and
## its sound played through a track of the song (InputMonitor.feeds), so it goes through that track's
## chain, fader, sends and meters like any monitored input. REC catches what it plays as a take on that
## track at the song position it began (`record_start` / `record_stop`).
##
## Its meters, how loud each module is now, are what the room's lights follow (`meters`, `level`).

## The patch or the track it sounds on was replaced.
signal changed()

## How often the song's position is told to the engine, which slews its own clock to it (a seek is jumped).
const FOLLOW_SECONDS := 0.05

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
## Composite plate id -> the engine module whose meter stands for it (RackExpansion.meter_map).
var _meter_map := {}
var _was_playing := false
var _bpm := 0.0
var _since_sync := 0.0
var _take_from := -1.0
var _take_track := 0
var meters := {}
## What the SCOPE modules saw (RackEngine.scopes).
var scopes := {}
## The step each STEP-wise module is on (RackEngine.steps).
var steps := {}
## A smoothed loudness of the whole rack, 0..1, and a hit pulse (set on a rise), for lights.
var level := 0.0
var hit := 0.0
var _last_peak := 0.0
var _held := {}
## Where the rack plays when no track can carry it (see `_direct`): a player of its own on the monitor
## bus, fed from the engine's stream a frame at a time.
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
## What the reader thread has taken from the engine and the main thread has not yet pushed, and the rule
## for when it is (RackCushion: nothing plays until 60 ms are in hand).
var cushion := RackCushion.new()
var _reader: Thread
var _reading := false
## The generator's room when empty (a little over buffer_length, rounded up by Godot).
var _capacity := 0


func _ready() -> void:
	source = RackEngine.Source.new(engine)


func _exit_tree() -> void:
	shutdown()


## Start the engine process and send it the current patch; false if the engine will not start.
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


## Stop the engine and the direct feed to the track.
func shutdown() -> void:
	InputMonitor.feeds.erase(track)
	_stop_direct()
	engine.stop()


func running() -> bool:
	return engine.running()


## The room's patch, sent to the engine as the difference from what it has: modules added or taken out,
## cables and knobs changed, so a sounding tail is not cut by turning a knob.
func set_patch(p: Dictionary) -> void:
	patch = RackPatch.playable(RackPatch.sanitize(p))
	_meter_map = RackExpansion.meter_map(patch)
	_sync_patch()
	changed.emit()


func _sync_patch() -> void:
	if not engine.running():
		return
	var was: Dictionary = _sent
	var now: Dictionary = RackExpansion.expand(patch)
	var lines := PackedStringArray()
	var fresh := {}
	for id in was["modules"]:
		if not now["modules"].has(id) or now["modules"][id]["type"] != was["modules"][id]["type"]:
			lines.append("remove %s" % id)
	for id in now["modules"]:
		if not was["modules"].has(id) or now["modules"][id]["type"] != was["modules"][id]["type"]:
			lines.append("add %s %s" % [id, RackCatalogue.engine_type(now["modules"][id]["type"])])
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


## One knob, at once (a hand turning it): the patch and the engine, with no diff. A composite's knob is
## an inner module's, so it goes as the difference of the expanded patch.
func knob(id: String, k: String, v01: float) -> void:
	if not RackPatch.set_knob(patch, id, k, v01):
		return
	if _meter_map.has(id):
		_sync_patch()
		return
	if not RackPatch.set_knob(_sent, id, k, v01):
		_sent = RackExpansion.expand(patch).duplicate(true)
	engine.say(RackPatch.knob_line(id, k, v01))


## Sound `pitch` (MIDI) at `velocity` on the engine and remember it as held.
func note_on(pitch: int, velocity := 100) -> void:
	_held[pitch] = true
	engine.say("note_on %d %d" % [pitch, velocity])


## Release `pitch` on the engine.
func note_off(pitch: int) -> void:
	_held.erase(pitch)
	engine.say("note_off %d" % pitch)


## Release every pitch this voice still holds.
func all_off() -> void:
	for pitch in _held.keys():
		engine.say("note_off %d" % pitch)
	_held.clear()


func bend(v: float) -> void:
	engine.say("bend %f" % v)


func cc(k: int, v: int) -> void:
	engine.say("cc %d %d" % [k, v])


## What the world played into its sockets (ModularWorld's events: [song, Modular.Event, socket, value]):
## the levels and gates of the engine's WORLD module.
func play_world(events: Array) -> void:
	if not engine.running():
		return
	for e: Array in events:
		var k := Modular.WORLD.find(e[2])
		if k < 0:
			continue
		if int(e[1]) == Modular.Event.WORLD:
			engine.say("world %d %f" % [k, float(e[3])])
		elif int(e[1]) == Modular.Event.TRIG:
			engine.say("trig %d" % k)


## A control on the room's CV bench (0..14: a, b, slider of each box in turn) set by a hand, 0..1.
func set_hand(k: int, v: float) -> void:
	if engine.running() and k >= 0 and k < 15:
		engine.say("hand %d %f" % [k, clampf(v, 0.0, 1.0)])


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


## Whether the rack plays on its own: only the built-in engine's InputMonitor takes a track's feed,
## so on the silent stand-in (a launch from the editor without --built-in) or under Reaper nothing
## would ever read the engine's stream and the rack would be mute. Without a sound card (the Dummy
## driver of a headless run) nothing would take it either, and the suite reads the stream itself.
func _direct() -> bool:
	if AudioServer.get_driver_name() == "Dummy":
		return false
	var backend: Object = DAW.backend if DAW != null else null
	var carried := backend is GodotBackend and (backend as GodotBackend).monitors != null and track > 0
	return not carried


func _stop_direct() -> void:
	_stop_reader()
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	_player = null
	_playback = null


## Takes the engine's stream off its pipe every few milliseconds, on a thread of its own. The pipe
## holds 4 kB (about 10 ms) and a frame is 16 ms, so reading once a frame got under a third of the
## sound (15k of 48k frames a second): a stutter that sounded like crushed audio.
func _start_reader() -> void:
	if _reader != null:
		return
	_reading = true
	_reader = Thread.new()
	_reader.start(_read_loop)


func _read_loop() -> void:
	while _reading:
		var got := source.read()
		if got.is_empty():
			OS.delay_msec(3)
			continue
		cushion.put(got)


func _stop_reader() -> void:
	_reading = false
	if _reader != null:
		_reader.wait_to_finish()
		_reader = null
	cushion.clear()


## The frames the reader has taken so far, at most `most` of them, oldest first.
func take_direct(most: int) -> PackedVector2Array:
	return cushion.take(most)


## How the direct feed is doing: frames in the generator, the times it ran dry (its own count of skips,
## and the cushion's count of refills), frames played fast to shed a surplus, frames lost to the queue's
## limit. For the probe (`tools/rack_pump_probe.gd`) and the tests.
func direct_stats() -> Dictionary:
	var fill := 0
	var skips := 0
	if _playback != null:
		fill = _capacity - _playback.get_frames_available()
		skips = _playback.get_skips()
	return {"fill": fill, "skips": skips, "underruns": cushion.underruns, "hurried": cushion.hurried,
			"dropped": cushion.dropped, "queued": cushion.queued()}


## The engine's sound to the speakers: what the cushion gives the generator, the frames it has room for.
func _pump_direct() -> void:
	_start_reader()
	if _player == null:
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = RackEngine.RATE
		stream.buffer_length = 0.3
		_player = AudioStreamPlayer.new()
		_player.name = "RackDirect"
		_player.bus = AudioPorts.bus(AudioPorts.MONITOR)
		_player.stream = stream
		add_child(_player)
		_player.play()
		_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
		_capacity = _playback.get_frames_available() if _playback != null else 0
	if _playback == null:
		return
	var space := _playback.get_frames_available()
	var frames := cushion.pull(_capacity - space, space)
	if not frames.is_empty():
		_playback.push_buffer(frames)


## The engine's meters, with a lamp for each composite plate: the meter of the inner module that stands
## for it (`meter_from`).
func _fold_meters(raw: Dictionary) -> Dictionary:
	if _meter_map.is_empty():
		return raw
	var out := raw.duplicate()
	for id in _meter_map:
		out[id] = float(raw.get(_meter_map[id], 0.0))
	return out


func _process(delta: float) -> void:
	if not engine.running():
		_stop_direct()
		return
	if source != null and _direct():
		_pump_direct()
	elif _player != null:
		_stop_direct()
	engine.poll()
	meters = _fold_meters(engine.meters)
	scopes = engine.scopes
	steps = engine.steps
	var peak := 0.0
	for id in patch["modules"]:
		if patch["modules"][id]["type"] == RackPatch.OUT_MODULE:
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
			# The song's place, often: the engine takes up a small drift smoothly and jumps a seek or a loop.
			_since_sync = 0.0
			engine.say("sync %f" % float(tp["beats"]))
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
