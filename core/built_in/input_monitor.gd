class_name InputMonitor
extends Node

## Input monitoring in the built-in engine: a track's input heard through the track, live, as a
## DAW monitors an armed track. What it hears goes into the track's own bus, so its chain, fader,
## pan, mute and meters all take it, and the LEVELS wall shows it; and into each of its sends and
## cues at their levels (GodotBackend's `monitor_outlets`), as the track's own items play into them.
##
## A track is heard when its monitor (DAW.set_track_monitor) is on, or on auto while it is armed
## and the song is stopped or recording, as in Reaper; and only when it names an audio input
## ("audio:<device>", "#1" or "#2" for that side alone). A track with no input chosen is not
## monitored: that would be the panel's microphone opening on a track nobody pointed at it.
##
## Each device is read by a capture stream of its own (MixSource.Piped, parec), one for every
## track that names it, so monitoring never takes frames from the recorder, which reads Godot's
## one input.
##
## Fed from a thread of its own, not once a frame (2026-10-30: "input lag through the audio
## interface into my game is just a LITTLE too much. i cant really play in time"). Fed a frame at a
## time, each player had to hold a whole frame's sound and then some, and what a slow frame let
## pile up in it was never given back: a hitch made the monitor later for the rest of the session,
## up to the player's whole 85 ms. Now the thread reads every device and tops every player up to
## QUEUE_FRAMES every half millisecond, the keys' own way (MonitorSynth), and what would queue past
## that is dropped, the oldest first, so what is heard is what is played now. Left are parec's 3 ms,
## the queue's 16, Godot's mix step and the way out: a voice is still best heard through the
## interface's own direct monitoring.

## How much sound a track's player is kept holding, in frames: enough to ride over Godot's 512-frame
## mix step and the thread's wake-ups, no more. Its latency, at most.
const QUEUE_FRAMES := 768
## The player's own room, in seconds: well over the queue, so a burst from the pipe is trimmed here
## rather than refused by the player.
const BUFFER := 0.1
const RATE := 48000
## How often the thread tops the players up.
const FEED_USEC := 500

## A capture stream for a device ("" the default), as a MixSource: the suite gives its own.
var make_source: Callable = func(device: String) -> MixSource:
	return MixSource.Piped.new(device, "monitoring " + (device if device != "" else "the default input"),
			"monitor " + (device.get_slice(".", 1) if device.contains(".") else (device if device != "" else "default")))
## {device: MixSource}
var _sources := {}
## {track index: {bus: AudioStreamPlayer}}
var _players := {}
## Devices whose stream would not start: tried once, not every frame.
var _failed := {}
## Whether the players are fed from the thread (the default), or by `feed` called from outside: the
## suite's, which feeds when it means to.
var threaded := true
## What the thread feeds, rebuilt by `drive` under `_lock`: [source, side, [playback, ...]] a heard
## track each.
var _routes: Array = []
var _lock := Mutex.new()
var _thread: Thread
var _running := false


## Whether a track's input is heard now.
static func heard(state: MixState, index: int) -> bool:
	var t: MixState.TrackState = state.track(index, false)
	if t == null or not t.input.begins_with("audio:") or t.input_off:
		return false
	match t.monitor:
		DAW.MONITOR_ON:
			return true
		DAW.MONITOR_AUTO:
			return t.rec_arm and (not state.playing or state.recording)
	return false


## Every track heard now, {index: input}.
static func plan(state: MixState) -> Dictionary:
	var out := {}
	if state == null:
		return out
	for index in state.track_indices():
		if heard(state, index):
			out[index] = state.input_of(index)
	return out


## The frames as a track takes them: both sides, or one side ("#1", "#2") on both.
static func side(frames: PackedVector2Array, channel: int) -> PackedVector2Array:
	if channel == 0:
		return frames
	var out := PackedVector2Array()
	out.resize(frames.size())
	for i in frames.size():
		var s: float = frames[i].x if channel == 1 else frames[i].y
		out[i] = Vector2(s, s)
	return out


## Once a frame: open what the plan needs, close what it no longer does, and tell the thread what
## to feed where (`_routes`). `outlets_of` gives a track's buses, [bus, gain dB] each, its own first.
func drive(state: MixState, outlets_of: Callable) -> void:
	# The thread let go of everything first: a stream may be closed and a player freed below.
	_lock.lock()
	_routes = []
	_lock.unlock()
	var now := plan(state)
	var devices := {}
	for index in now:
		devices[GuestAudio.device_of(now[index])] = true
	for device in _sources.keys():
		if not devices.has(device):
			(_sources[device] as MixSource).stop()
			_sources.erase(device)
	for index in _players.keys():
		if not now.has(index):
			_drop_player(index)
	for device in devices:
		if _sources.has(device) or _failed.has(device):
			continue
		var source: MixSource = make_source.call(device)
		if source.start():
			_sources[device] = source
		else:
			_failed[device] = true
			push_warning("InputMonitor: could not open %s to monitor it." % (device if device != "" else "the default input"))
	var routes: Array = []
	for index in now:
		var device := GuestAudio.device_of(now[index])
		if not _sources.has(device):
			continue
		var outlets: Array = outlets_of.call(index)
		var mine: Dictionary = _players.get(index, {})
		var wanted := {}
		for outlet in outlets:
			wanted[StringName(outlet[0])] = true
		for bus in mine.keys():
			if not wanted.has(bus):
				_free(mine[bus])
				mine.erase(bus)
		var playbacks: Array = []
		for outlet in outlets:
			var player := _player_for(index, StringName(outlet[0]), float(outlet[1]))
			var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback if player != null else null
			if playback != null:
				playbacks.append(playback)
		routes.append([_sources[device], GuestAudio.channel_of(now[index]), playbacks])
	_lock.lock()
	_routes = routes
	_lock.unlock()
	if threaded and not routes.is_empty() and not _running:
		_running = true
		_thread = Thread.new()
		_thread.start(_feed_loop)
	elif routes.is_empty():
		_stop_thread()


## Read every device once and top every heard track's players up from it. The thread's, every
## FEED_USEC; the suite's, when it is not threaded.
func feed() -> void:
	_lock.lock()
	var read := {}
	for route in _routes:
		var source: MixSource = route[0]
		if not read.has(source):
			read[source] = source.read()
		var frames := side(read[source], route[1])
		for playback in route[2]:
			_feed(playback, frames)
	_lock.unlock()


func _feed_loop() -> void:
	while _running:
		feed()
		OS.delay_usec(FEED_USEC)


func _stop_thread() -> void:
	if _thread == null:
		return
	_running = false
	_thread.wait_to_finish()
	_thread = null


## The tracks heard now, by index: for the strip and the suite.
func monitoring() -> Array:
	var out: Array = _players.keys()
	out.sort()
	return out


## The buses a heard track's input plays into now.
func buses_of(index: int) -> Array:
	var out: Array = (_players.get(index, {}) as Dictionary).keys()
	out.sort()
	return out


## Up to QUEUE_FRAMES held, the newest of what came kept and the rest dropped. Past it already (the
## mixer stalled), nothing is added until it has drained back: the monitor never falls behind.
static func _feed(playback: AudioStreamGeneratorPlayback, frames: PackedVector2Array) -> void:
	if frames.is_empty():
		return
	var room := playback.get_frames_available()
	var queued := _capacity_of(playback) - room
	var take := mini(frames.size(), mini(room, QUEUE_FRAMES - queued))
	if take <= 0:
		return
	playback.push_buffer(frames if take == frames.size() else frames.slice(frames.size() - take))


## What a player holds when empty: its buffer, as Godot rounded it. Read once, on the first push.
static var _capacities := {}
static func _capacity_of(playback: AudioStreamGeneratorPlayback) -> int:
	var id := playback.get_instance_id()
	if not _capacities.has(id):
		_capacities[id] = playback.get_frames_available()
	return _capacities[id]


## The devices open now.
func open_devices() -> Array:
	return _sources.keys()


func stop_all() -> void:
	_stop_thread()
	_lock.lock()
	_routes = []
	_lock.unlock()
	for source in _sources.values():
		(source as MixSource).stop()
	_sources.clear()
	for index in _players.keys():
		_drop_player(index)
	_failed.clear()


func _exit_tree() -> void:
	stop_all()


func _player_for(index: int, bus: StringName, gain_db: float) -> AudioStreamPlayer:
	if bus == &"":
		return null
	if not _players.has(index):
		_players[index] = {}
	var player: AudioStreamPlayer = _players[index].get(bus)
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = "Monitor%d_%d" % [index, _players[index].size()]
		player.bus = bus
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = RATE
		stream.buffer_length = BUFFER
		player.stream = stream
		add_child(player)
		_players[index][bus] = player
	player.volume_db = gain_db
	if not player.playing:
		player.play()
	return player


func _drop_player(index: int) -> void:
	for player in (_players.get(index, {}) as Dictionary).values():
		_free(player)
	_players.erase(index)


func _free(player: AudioStreamPlayer) -> void:
	if player != null and is_instance_valid(player):
		player.stop()
		player.queue_free()
