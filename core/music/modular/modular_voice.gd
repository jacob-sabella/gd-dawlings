class_name ModularVoice
extends Node

## This player's keys played through the modular wall's patch, live (docs/spatial_loop.md part two,
## slice 51), while they stand at the keyboard stand under it (`engaged`).
##
## Two roads, as every sound here has (part two's "Every sound has a path and a budget"). Where the
## keys' helper runs (NativeKeys, the keys' MonitorSynth's `native`), it is played there: the helper
## is told the patch and each knob as it turns by `mod` lines and plays the keys through it
## (`mod on 1`) in its realtime callback, the sequencer's notes as well as the app's, a few
## milliseconds after the key. Where it does not, it is played here, through Godot on MONITOR, by a
## Modular of its own on a thread a block at a time, the keys' MonitorSynth handing it their notes
## instead of playing its tine (MonitorSynth.modular). `path` says which and `latency` its figure, for
## the wall's tag.
##
## The patch is the room's (`set_patch`, from the room's row) and a knob's turn is everyone's
## (`knob`, from the knob events streamed: this player's own as they send them, not the knob under
## the hand, and a bandmate's as they arrive), so the sound follows the wall whoever moves it, and
## what this player hears of their own turn is what a take of it renders (ModularTake).
##
## A BANDMATE'S (docs/spatial_loop.md part two, slice 52). With a `speaker`, a voice plays a
## bandmate's keys: the notes and wheel they send as the modular's (Presence.modular_heard), through
## the room's patch, on a Modular of its own through Godot, out of the air at the speaker (the wall)
## on the room's bus. The studio keeps one for each bandmate playing it. It rests (`engaged` off,
## its thread and its emitter gone) once they have held no note for `rest_after`, so a bandmate who
## played the wall a while ago costs nothing, and their next note wakes it on the patch as it stands.
##
## THE WORLD (slice 53). Every voice hears the world's sockets as they change (`world`, `trig`, from
## ModularWorld), so the rain on the filter is in every copy of the patch alike. With `world_only`
## (and a `speaker`) it is the room's own voice at the wall: no keys at all, never resting while
## the studio keeps it engaged, so a drip into an ENV's gate sounds with nobody playing. The studio
## rests it while any other voice here plays the patch, which hears the world already.

enum Path { NONE, HELPER, GODOT }

## Godot's mixer takes this many frames at once; the queue holds a gulp and a block more, as
## MonitorSynth's does.
const MIX_STEP := 512
const QUEUE_FRAMES := 768

## The keys this plays: the player's MonitorSynth (GuestMidi.synth). Set before `engaged`.
var keys: MonitorSynth = null
## Where a bandmate's voice plays from (the wall), or null for this player's own. Set before
## `engaged`: with one, it plays the notes it is handed through Godot, never the keys.
var speaker: Node3D = null
## How loud it plays through Godot (dB): a bandmate's own level; this player's is their keys'.
var volume_db := -6.0
## A bandmate's voice: how long after their last note-off it rests (s), past any release and tail.
var rest_after := 5.0
## The world's voice at the wall (slice 53): played by the world's sockets alone, and not rested.
var world_only := false
## The patch it plays (Modular's {cables, knobs}): the room's.
var patch := Modular.default_patch()
## Whether the keys play the patch now: true while this player stands at the stand.
var engaged := false:
	set(v):
		if engaged == v:
			return
		engaged = v
		_quiet_since = Time.get_ticks_msec()
		_reroute()

## The road it is playing on now.
var path := Path.NONE
var _native: NativeKeys = null
var _modular := Modular.new()
## An AudioStreamPlayer, or an AudioStreamPlayer3D on `speaker`.
var _player: Node = null
var _playback: AudioStreamGeneratorPlayback = null
var _capacity := 0
var _thread: Thread = null
var _running := false
var _mutex := Mutex.new()
## Events from the main thread for the render thread: [Modular.Event, a, b].
var _events: Array = []
## A bandmate's voice: the notes it holds ({pitch: true}), and when the last let go (msec).
var _held := {}
var _quiet_since := 0
## Each world socket's level as last told ({socket: level}), so a voice woken, or moved onto another
## road, starts from where the world stands.
var _world := {}


func _exit_tree() -> void:
	engaged = false
	_stop_thread()


## The room's patch, played from now on, on whichever road.
func set_patch(to: Dictionary) -> void:
	patch = Modular.clean(to)
	if _native != null:
		_native.modular_patch(patch)
	_queue([-1, patch.duplicate(true), null])


## Knob `id` at `v` now: a turn here or a bandmate's, heard as it turns. The patch keeps it, so a
## re-route plays it too.
func knob(id: StringName, v: float) -> void:
	if not Modular.KNOBS.has(id):
		return
	(patch["knobs"] as Dictionary)[id] = clampf(v, 0.0, 1.0)
	if _native != null:
		_native.modular_knob(id, v)
	_queue([Modular.Event.KNOB, id, v])


## World socket `socket`'s level now (ModularWorld): on whichever road.
func world(socket: StringName, level: float) -> void:
	if not Modular.is_world(socket) or not is_finite(level):
		return
	_world[socket] = level
	if _native != null:
		_native.modular_world(socket, level)
	_queue([Modular.Event.WORLD, socket, level])


## World socket `socket`'s gate opened now.
func trig(socket: StringName) -> void:
	if not Modular.is_world(socket):
		return
	if _native != null:
		_native.modular_trig(socket)
	_queue([Modular.Event.TRIG, socket, 0])


## The world's levels as this voice was last told them.
func world_levels() -> Dictionary:
	return _world.duplicate()


## The keys' MonitorSynth hands its notes here on the Godot road (MonitorSynth.modular). A
## bandmate's resting voice wakes for it.
func note_on(pitch: int, velocity: int) -> void:
	if speaker != null:
		_held[pitch] = true
		engaged = true
	_queue([Modular.Event.ON, pitch, velocity])


func note_off(pitch: int) -> void:
	if speaker != null and _held.erase(pitch) and _held.is_empty():
		_quiet_since = Time.get_ticks_msec()
	_queue([Modular.Event.OFF, pitch, 0])


func bend(value: int) -> void:
	_queue([Modular.Event.BEND, value, 0])


func all_off() -> void:
	if speaker != null and not _held.is_empty():
		_held.clear()
		_quiet_since = Time.get_ticks_msec()
	_queue([-2, 0, 0])


## How long after a key its sound reaches the air on the road it takes (s): the helper's own count,
## or Godot's queue, its mix step and the card's; 0 when it is not playing.
func latency() -> float:
	match path:
		Path.HELPER:
			return _native.latency if _native != null and _native.latency > 0.0 \
					else 2.0 * NativeKeys.QUANTUM / Modular.RATE
		Path.GODOT:
			return QUEUE_FRAMES / float(Modular.RATE) + MIX_STEP / float(Modular.RATE) \
					+ AudioServer.get_output_latency()
	return 0.0


## The wall's tag: which road, and its figure.
func tag() -> String:
	match path:
		Path.HELPER:
			return "HELPER · %.1f ms" % (latency() * 1000.0)
		Path.GODOT:
			return "THROUGH GODOT · %.0f ms" % (latency() * 1000.0)
	return "WALK UP TO THE STAND TO PLAY"


## The road followed: the helper coming up or going away under it moves the keys to the other.
## A bandmate's voice quiet for `rest_after` rests.
func _process(_delta: float) -> void:
	if not engaged:
		return
	if speaker != null:
		if world_only:
			return
		if _held.is_empty() and Time.get_ticks_msec() - _quiet_since >= int(rest_after * 1000.0):
			engaged = false
		return
	var native := keys.native if keys != null else null
	if native != _native or (native == null and path == Path.HELPER):
		_reroute()


func _reroute() -> void:
	if _native != null:
		_native.modular_on(false)
		_native = null
	if keys != null and keys.modular == self:
		keys.modular = null
	_stop_thread()
	path = Path.NONE
	if engaged and speaker != null:
		# A bandmate's: through Godot, at the wall.
		path = Path.GODOT
		_start_thread()
		return
	if not engaged or keys == null:
		return
	if keys.native != null:
		_native = keys.native
		_native.modular_patch(patch)
		for socket: StringName in _world:
			_native.modular_world(socket, float(_world[socket]))
		_native.modular_on(true)
		path = Path.HELPER
		return
	# Through Godot: the keys hand their notes here and play nothing themselves.
	keys.all_off()
	keys.modular = self
	path = Path.GODOT
	_start_thread()


func _start_thread() -> void:
	_mutex.lock()
	_events.clear()
	_mutex.unlock()
	_modular = Modular.new()
	_modular.set_patch(patch)
	for socket: StringName in _world:
		_modular.world(socket, float(_world[socket]))
	if not MonitorSynth.available():
		return
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = Modular.RATE
	stream.buffer_length = 4096.0 / Modular.RATE
	if speaker != null:
		var out := Foley.emitter(stream, volume_db)
		out.name = "ModularVoice"
		speaker.add_child(out)
		out.play()
		_playback = out.get_stream_playback()
		_player = out
	else:
		var out := AudioStreamPlayer.new()
		out.name = "ModularVoice"
		out.bus = AudioPorts.bus(AudioPorts.MONITOR)
		out.stream = stream
		out.volume_db = keys.volume_db if keys != null else volume_db
		add_child(out)
		out.play()
		_playback = out.get_stream_playback()
		_player = out
	_capacity = _playback.get_frames_available()
	_running = true
	_thread = Thread.new()
	_thread.start(_render_loop)


func _stop_thread() -> void:
	_running = false
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	if _player != null and is_instance_valid(_player):
		_player.call("stop")
		_player.queue_free()
	_player = null
	_playback = null


func _queue(event: Array) -> void:
	if path != Path.GODOT:
		return
	_mutex.lock()
	if _events.size() < 1024:
		_events.append(event)
	_mutex.unlock()


func _render_loop() -> void:
	while _running:
		var queued := _capacity - _playback.get_frames_available()
		if queued + Modular.BLOCK <= QUEUE_FRAMES:
			var want := (QUEUE_FRAMES - queued) / Modular.BLOCK * Modular.BLOCK
			_playback.push_buffer(_stereo(render(want)))
		OS.delay_usec(500)


## `frames` of the patch played on this road through Godot, its queued events first. Public so the
## suite can listen to it.
func render(frames: int) -> PackedFloat32Array:
	_mutex.lock()
	var events := _events
	_events = []
	_mutex.unlock()
	for e: Array in events:
		match int(e[0]):
			-1:
				_modular.set_patch(e[1])
			-2:
				_modular.all_off()
			_:
				_modular.apply([0.0, e[0], e[1], e[2]])
	return _modular.run(frames)


static func _stereo(mono: PackedFloat32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(mono.size())
	for i in mono.size():
		out[i] = Vector2(mono[i], mono[i])
	return out


## Whether this player's keys hold a note on the modular now (the Godot road's own count).
func gate() -> bool:
	return _modular.gate()
