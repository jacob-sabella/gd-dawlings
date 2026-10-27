class_name EarCue
extends Node

## A cassette held to the ear (docs/spatial_loop.md part two, slice 25, idea #13): its clip, played
## to this player alone, from its start, looping, at its own gain, until it is taken away. Browsing
## sounds is picking them up and listening.
##
## The studio says each frame which cassette is at an ear here (`hold`, from Interactor.cassette_at_ear:
## a headset hand within XRInteractor.HEAD_REACH of the head, or L held at a desk). It plays on the
## keys' bus (AudioPorts.MONITOR) as a cue, never the Mix bus, and Ears.cue takes the room
## Ears.CUE_DUCK_DB down meanwhile, for this player. Nothing goes to the DAW, and nobody else hears it.
##
## What it plays is made here from what the cassette carries (MixWire.pack_item), whatever the backend:
##   MIDI     the notes through the built-in instrument (GodotBackend.render_midi_frames: DawKitTine,
##            and ItemVoices for channels 9 and 10), exactly the clip long, the tail rung round into
##            its start, made into its stream on a worker (RENDERING meanwhile);
##   a demo   the part it was cut from, as the song plays it there (DemoSong.render_window through the
##   part     song's tempo map and meter), from the clip's start to its end, on a worker too;
##   audio    its file, from its offset, through its loop, reversed if it is: where this machine has
##            it. That is the host's media folder; on a guest, the copy FileSend fetched from the host,
##            asked for once (FETCHING meanwhile). Where it cannot be had, MISSING: the tag says
##            `not on this machine`.
## A clip with none of them (a Reaper item's own audio, whose sound stays in Reaper) is EMPTY.
## A render goes on though the cassette is taken from the ear, and is kept when done: held up again
## it is picked up where it got to, and another cassette meanwhile never waits for it. The main
## thread waits for one only as the cue leaves the tree.
##
## What it is doing is lettered on the cassette's tag (CassetteItem.hearing) and said once, as a
## notice, as it starts.

enum Hearing { NONE, PLAYING, RENDERING, FETCHING, MISSING, EMPTY }

## The cassette's tag for each, where it says anything.
const TAGS := {
	Hearing.PLAYING: "AT YOUR EAR",
	Hearing.RENDERING: "RENDERING",
	Hearing.FETCHING: "FETCHING",
	Hearing.MISSING: "not on this machine",
	Hearing.EMPTY: "nothing to hear",
}
## The bus it plays on: the keys', which is what a personal mix calls this player's own.
const BUS := AudioPorts.MONITOR
## Streams kept for cassettes heard lately, so the next time at the ear is at once.
const KEPT := 6

## The cassette at the ear, or null.
var cassette: CassetteItem = null
var hearing := Hearing.NONE
## The one player, made with the cue.
var player: AudioStreamPlayer
## Where a guest fetches from: Session.files unless the suite gives another.
var files: FileSend = null
## Whether a desk is what holds it up (L), for what the notice says to stop it.
var desk := true

## {key: [stream, seconds into it the clip starts, seconds before going back there (0: the stream
## loops by itself)]}, the newest last.
var _streams := {}
## Renders under way, {key: [task id, result ([the finished stream, or null])]}: the one for the
## cassette at the ear, and any it was taken away from before theirs were done.
var _tasks := {}
## The render the cassette at the ear waits for, "" for none.
var _waiting := ""
## For a clip that goes round by being started again (an audio clip through its own loop): how
## long it has played since its start.
var _played := 0.0
var _from := 0.0
var _every := 0.0


func _ready() -> void:
	AudioPorts.ensure_buses()
	player = AudioStreamPlayer.new()
	player.name = "EarCuePlayer"
	player.bus = BUS
	add_child(player)


## `c` is the cassette at an ear here now, or null for none: started, stopped, or left as it is.
func hold(c: CassetteItem) -> void:
	if c != null and (not is_instance_valid(c) or c.clip.is_empty()):
		c = null
	if c == cassette:
		return
	_stop()
	cassette = c
	if cassette != null:
		_start()


## The tag's words for what it is doing now, "" for nothing.
func tag() -> String:
	return TAGS.get(hearing, "")


func _process(delta: float) -> void:
	if cassette != null and not is_instance_valid(cassette):
		cassette = null
		_stop()
	_collect()
	match hearing:
		Hearing.FETCHING:
			var f := _files()
			var source := str(cassette.clip.get("source", ""))
			if f != null and f.fetch_state(source) == FileSend.REFUSED:
				_mark(Hearing.MISSING)
				Session.notice.emit("%s is not on this machine, and the host could not send it: %s." % [source.get_file(),
						f.fetch_refusal(source)])
			elif f != null and not f.fetched_path(source).is_empty():
				_play_file()
		Hearing.PLAYING:
			if _every > 0.0 and player.playing:
				_played += delta
				if _played >= _every:
					_played = fmod(_played, _every)
					player.play(_from + _played)


# --- starting and stopping ---------------------------------------------------------------

func _start() -> void:
	var item := MixWire.unpack_item(cassette.clip)
	if item == null:
		_begin(Hearing.EMPTY)
		return
	if not item.notes.is_empty():
		var key := "midi|%d|%d|%s" % [hash(item.notes), hash(item.controls), item.length]
		if not _play_kept(key):
			var notes := PackedFloat64Array(Array(item.notes))
			var controls := item.controls.duplicate()
			var seconds := item.length
			var rate := int(AudioServer.get_mix_rate())
			_render(key, func() -> AudioStreamWAV: return midi_stream(notes, seconds, rate, controls))
		return
	if not item.source.is_empty():
		_play_file()
		return
	if not item.part.is_empty():
		var map := DAW.state.tempo_map().to_array() if DAW.state != null else [[0.0, 120.0]]
		var meter := DAW.state.meter().to_array() if DAW.state != null else []
		var key := "demo|%s|%s|%s|%s%s" % [item.part, item.start, item.length, map, meter]
		if not _play_kept(key):
			var part := item.part
			var start := item.start
			var seconds := item.length
			_render(key, func() -> AudioStreamWAV: return demo_stream(part, start, seconds, map, meter))
		return
	_begin(Hearing.EMPTY)


func _stop() -> void:
	if player != null:
		player.stop()
	Ears.cue(false)
	if cassette != null and is_instance_valid(cassette):
		# Why it could not be heard stays on its tag, to read once it is down from the ear.
		if hearing not in [Hearing.MISSING, Hearing.EMPTY]:
			cassette.hearing = ""
	hearing = Hearing.NONE
	_every = 0.0
	# Its render, if one is under way, goes on, to be kept for next time (`_collect`).
	_waiting = ""


## Started in state `h`, and said once.
func _begin(h: Hearing) -> void:
	_mark(h)
	var what := "the %s cassette" % cassette.clip_name()
	var stop := "let go of L to stop" if desk else "take it from your ear to stop"
	match h:
		Hearing.RENDERING, Hearing.PLAYING:
			var duck := "the room %d dB down" % int(absf(Ears.CUE_DUCK_DB)) \
					if Ears.reaches_mix(Session.role == Session.Role.GUEST, DAW.backend is ReaperBackend) \
					else "the room's sounds %d dB down (Reaper's own is not the game's to quiet)" % int(absf(Ears.CUE_DUCK_DB))
			Session.notice.emit("Listening to %s: in your ears alone, %s; %s." % [what, duck, stop])
		Hearing.FETCHING:
			Session.notice.emit("Fetching %s from %s, to hear %s..." % [str(cassette.clip.get("source", "")).get_file(),
					Session.name_of(1), what])
		Hearing.MISSING:
			Session.notice.emit("%s is not on this machine, so %s cannot be heard here." % [
					str(cassette.clip.get("source", "")).get_file(), what])
		Hearing.EMPTY:
			Session.notice.emit("%s holds no notes and no sound recorded here to hear: the sound of an item Reaper made itself stays in Reaper." % what.capitalize())


## In state `h`: said, if it is the first since it came to the ear.
func _now(h: Hearing) -> void:
	if hearing == Hearing.NONE:
		_begin(h)
	else:
		_mark(h)


func _mark(h: Hearing) -> void:
	hearing = h
	if cassette != null and is_instance_valid(cassette):
		cassette.hearing = tag()
	Ears.cue(h == Hearing.PLAYING)


## Plays `stream` from `from` seconds, going back there every `every` (0: the stream loops itself).
func _play(stream: AudioStream, from: float, every: float) -> void:
	player.stream = stream
	player.volume_db = clampf(float(cassette.clip.get("gain_db", 0.0)), -60.0, 12.0)
	player.play(from)
	_from = from
	_every = every
	_played = 0.0
	_now(Hearing.PLAYING)


func _play_kept(key: String) -> bool:
	if not _streams.has(key):
		return false
	var kept: Array = _streams[key]
	_streams.erase(key)
	_streams[key] = kept
	_play(kept[0], kept[1], kept[2])
	return true


func _keep(key: String, kept: Array) -> void:
	_streams.erase(key)
	_streams[key] = kept
	while _streams.size() > KEPT:
		_streams.erase(_streams.keys()[0])


# --- rendering: MIDI and demo parts --------------------------------------------------------

## Waits for the render of `key`, `work` (a stream, safe off the main thread): the one already
## under way for it, if the cassette was held up before and taken away, or a new one.
func _render(key: String, work: Callable) -> void:
	if not _tasks.has(key):
		var result := [null]
		var task := WorkerThreadPool.add_task(func() -> void: result[0] = work.call(), false, "render a cassette for the ear")
		_tasks[key] = [task, result]
	_waiting = key
	_begin(Hearing.RENDERING)


## Renders done kept, whatever is at the ear now; the one it waits for, played.
func _collect() -> void:
	for key: String in _tasks.keys():
		var running: Array = _tasks[key]
		if not WorkerThreadPool.is_task_completed(running[0]):
			continue
		WorkerThreadPool.wait_for_task_completion(running[0])
		_tasks.erase(key)
		var stream: AudioStreamWAV = running[1][0]
		var made := stream != null and not stream.data.is_empty()
		if made:
			_keep(key, [stream, 0.0, 0.0])
		if key != _waiting or hearing != Hearing.RENDERING:
			continue
		_waiting = ""
		if made:
			_play(stream, 0.0, 0.0)
		else:
			_mark(Hearing.EMPTY)


func _exit_tree() -> void:
	for running: Array in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(running[0])
	_tasks.clear()
	_waiting = ""
	Ears.cue(false)


## A rendered clip's stream, looping all of itself.
static func _looped(stream: AudioStreamWAV) -> AudioStreamWAV:
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / (4 if stream.stereo else 2)
	return stream


## `midi_frames` as the ear plays it: a stereo stream at `rate`, looping. Safe off the main thread.
static func midi_stream(notes: PackedFloat64Array, seconds: float, rate: int,
		controls := PackedFloat64Array()) -> AudioStreamWAV:
	return _looped(GodotBackend.wav_of(midi_frames(notes, seconds, rate, controls), rate))


## `demo_samples` as the ear plays it: a mono stream at DemoSong.RATE, looping. Safe off the main
## thread.
static func demo_stream(part: String, start: float, seconds: float, map_points: Array,
		meter_points: Array) -> AudioStreamWAV:
	return _looped(DemoSong.stream_of(DemoSong.encode(demo_samples(part, start, seconds, map_points, meter_points))))


## A MIDI clip's `notes` and `controls` (seconds from its start) through the built-in instrument, as
## exactly `seconds` of stereo frames at `rate`: what rings past the end is added onto the start, as
## a loop of the clip going round hears it. Safe off the main thread.
static func midi_frames(notes: PackedFloat64Array, seconds: float, rate: int,
		controls := PackedFloat64Array()) -> PackedVector2Array:
	var frames := GodotBackend.render_midi_frames(notes, seconds, rate, controls)
	var n := int(round(seconds * rate))
	if n <= 0:
		return PackedVector2Array()
	for i in range(n, frames.size()):
		frames[(i - n) % n] += frames[i]
	frames.resize(n)
	return frames


## Demo part `part` from `start` for `seconds` of the song, as the song plays it there: mono samples
## at DemoSong.RATE, from the windows (DemoSong.render_window) of the song's tempo map `map_points`
## and meter `meter_points` that hold it, each window's from its loop's first bar to the next's.
## Safe off the main thread.
static func demo_samples(part: String, start: float, seconds: float, map_points: Array,
		meter_points: Array) -> PackedFloat32Array:
	var map := DawKitTempoMap.from_array(map_points)
	var meter := DawKitMeter.from_array(meter_points)
	var want := int(round(seconds * DemoSong.RATE))
	var out := PackedFloat32Array()
	out.resize(maxi(want, 0))
	var at := maxf(start, 0.0)
	var filled := 0
	var windows := 0
	while filled < want and windows < 64:
		windows += 1
		var loop := floori(meter.bar_at(map.beat_at(at)) / DemoSong.BARS)
		var made := DemoSong.render_window(part, map_points, loop, meter_points)
		var samples: PackedFloat32Array = made[0]
		var first := float(made[1])
		var next := map.seconds_at(meter.beat_of_bar((loop + 1) * DemoSong.BARS))
		var count := mini(int(round((next - at) * DemoSong.RATE)), want - filled)
		var from := int(round((at - first) * DemoSong.RATE))
		for i in maxi(count, 0):
			var j := from + i
			if j >= 0 and j < samples.size():
				out[filled + i] = samples[j]
		filled += maxi(count, 1)
		at = next
	return out


# --- audio: the clip's file, where this machine has it --------------------------------------

func _files() -> FileSend:
	return files if files != null else Session.files


## Where this machine has file `source`: the host's media folder (DAWBackend.media_path), or on a
## guest the copy FileSend fetched; "" where it has none.
func local_file(source: String) -> String:
	if source.is_empty():
		return ""
	if Session.role == Session.Role.GUEST:
		var f := _files()
		return f.fetched_path(source) if f != null else ""
	var path := DAW.backend.media_path(source) if DAW.backend != null else ""
	return path if not path.is_empty() and FileAccess.file_exists(path) else ""


## The audio clip played from its file here, or fetched, or said to be missing.
func _play_file() -> void:
	var item := MixWire.unpack_item(cassette.clip)
	var path := local_file(item.source)
	if path.is_empty():
		var f := _files()
		if Session.role == Session.Role.GUEST and f != null:
			var why := f.fetch(item.source)
			if why.is_empty() and f.fetch_state(item.source) == FileSend.FETCHING:
				_now(Hearing.FETCHING)
				return
		_now(Hearing.MISSING)
		return
	var key := "file|%s|%s|%s|%s|%s|%s" % [path, item.source_offset, item.length, item.loop_start, item.loop_end, item.reversed]
	if _play_kept(key):
		return
	var made := clip_stream(item, AudioStreamWAV.load_from_file(path))
	if made.is_empty():
		_now(Hearing.EMPTY)
		return
	_keep(key, made)
	_play(made[0], made[1], made[2])


## Audio clip `item` of the sound `base` (its file), as the ear plays it: [stream, where in it the
## clip starts, how long before it goes back there (0: the stream loops by itself)], or [] where
## there is nothing of it in the file. From its offset, as the engine plays it (GodotBackend's
## players): through its own loop where it has one, going back to its start each clip's length;
## otherwise the stream loops the clip's own stretch of the file, offset to offset plus length,
## seamlessly. Reversed, the file backwards (GodotBackend.reversed_stream) from its offset.
static func clip_stream(item: MixState.ItemState, base: AudioStreamWAV) -> Array:
	if item == null or base == null or base.data.is_empty():
		return []
	var wav := GodotBackend.reversed_stream(base) if item.reversed else base.duplicate() as AudioStreamWAV
	if wav == null:
		return []
	var rate := float(wav.mix_rate)
	var frames := int(wav.get_length() * rate)
	var from := item.source_offset
	if item.is_looped() and not item.reversed:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = clampi(int(item.loop_start * rate), 0, frames)
		wav.loop_end = clampi(int(item.loop_end * rate), 0, frames)
		if wav.loop_end <= wav.loop_begin:
			return []
		return [wav, item.file_time(item.start), item.length]
	var begin := clampi(int(round(from * rate)), 0, frames)
	var end := clampi(int(round((from + item.length) * rate)), 0, frames)
	if end <= begin:
		return []
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = begin
	wav.loop_end = end
	return [wav, begin / rate, 0.0]
