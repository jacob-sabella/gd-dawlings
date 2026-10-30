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
## one input. The cost is parec's 3ms plus about a frame here: a voice is still best heard
## through the interface's own direct monitoring.

## How much sound may wait in a track's player, in seconds: its latency, at most. What does not
## fit is dropped rather than queued, so the monitor never drifts behind the hand.
const BUFFER := 0.06
const RATE := 48000

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


## Whether a track's input is heard now.
static func heard(state: MixState, index: int) -> bool:
	var t: MixState.TrackState = state.track(index, false)
	if t == null or not t.input.begins_with("audio:"):
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


## Once a frame: open what the plan needs, close what it no longer does, and feed each heard
## track what its device gave since the last frame. `outlets_of` gives a track's buses, [bus, gain
## dB] each, its own first.
func drive(state: MixState, outlets_of: Callable) -> void:
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
	var read := {}
	for device in _sources:
		read[device] = (_sources[device] as MixSource).read()
	for index in now:
		var device := GuestAudio.device_of(now[index])
		if not read.has(device):
			continue
		var frames := side(read[device], GuestAudio.channel_of(now[index]))
		var outlets: Array = outlets_of.call(index)
		var mine: Dictionary = _players.get(index, {})
		var wanted := {}
		for outlet in outlets:
			wanted[StringName(outlet[0])] = true
		for bus in mine.keys():
			if not wanted.has(bus):
				_free(mine[bus])
				mine.erase(bus)
		for outlet in outlets:
			var player := _player_for(index, StringName(outlet[0]), float(outlet[1]))
			if player != null:
				_feed(player, frames)


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


func _feed(player: AudioStreamPlayer, frames: PackedVector2Array) -> void:
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var room := playback.get_frames_available()
	if frames.size() > room:
		# The newest, so what is heard is what is played now.
		frames = frames.slice(frames.size() - room)
	if not frames.is_empty():
		playback.push_buffer(frames)


## The devices open now.
func open_devices() -> Array:
	return _sources.keys()


func stop_all() -> void:
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
