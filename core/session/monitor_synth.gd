class_name MonitorSynth
extends Node

## A small electric piano, so a guest hears their own keys the instant they press them.
##
## The round trip is not an option for this. A note sent to the host, played by its Reaper, and
## streamed back arrives about 90ms after the key went down -- long past the 10-20ms at which a
## player stops feeling the instrument as theirs. So the guest monitors locally, and what the
## host records is the guest's stamped notes, not the sound of them.
##
## The tone is dawkit's instrument, the two-operator tine (DawKitTine): the one the built-in
## engine plays MIDI items through, so a player hears their keys as the take will sound.
##
## On a host whose engine is the built-in one, the keys play onto the bus of the track they are
## recorded to (`set_bus`), through its fader and effects, as a DAW monitors a track's
## instrument: through Godot, never the helper below, whose sound does not pass the track.
##
## Where it can, it does not play through Godot at all: NativeKeys runs the same synth as a
## PipeWire node of its own, in the graph's realtime callback, with MIDI read straight from the
## sequencer -- about 4.5ms key to sink against 30-50ms through Godot's mixer. `native` is that
## helper while it runs. Where it cannot, this renders on its own thread, half a millisecond at a
## time, into a generator kept as short as Godot's mixer allows -- the same reasoning, and the
## same numbers, as MixFeed's playback.

const RATE := 48000.0
## Godot's mixer takes this many frames at once; the queue must hold one gulp and a little more.
const MIX_STEP := 512
const QUEUE_FRAMES := 768
enum { OFF, ON, SUSTAIN, CONTROL }

## Whether anything is played. Off for a guest monitoring through their own gear.
var enabled := true:
	set(v):
		enabled = v
		if native != null:
			native.enable(v)
		if not v:
			all_off()
var volume_db := -6.0:
	set(v):
		volume_db = v
		if _player != null:
			_player.set("volume_db", v)
		if native != null:
			native.volume(v)
## The helper this plays through, while it runs; null when playing through Godot.
var native: NativeKeys = null
## Off: always through Godot. For the suite, and R3D_GODOT_KEYS=1 to compare.
var allow_native := OS.get_environment("R3D_GODOT_KEYS") != "1"
## The bus it plays on through Godot: the keys' own (Monitor) unless told otherwise -- another
## player's keys played here have a bus of their own (TheirKeys).
var bus: StringName = &""
## Where in the room it plays from, when it is an instrument somebody else is holding (a keytar):
## out of the air at that spot, on the room's bus, rather than in the ears. Set before `start`.
var speaker: Node3D = null

## An AudioStreamPlayer, or an AudioStreamPlayer3D on `speaker`.
var _player: Node = null
var _playback: AudioStreamGeneratorPlayback = null
var _capacity := 0
var _thread: Thread = null
var _running := false
var _mutex := Mutex.new()
## Note events from the main thread, applied by the render thread: [on?, pitch, velocity].
var _events: Array = []
var _sustain := false
## The controls as they are set now, {kind: value}, as `control` was last told: the pitch wheel
## (DawKitClip.PITCH_BEND) and controllers 1 and 11. Only what has been set is here.
var controls := {}
## The voice itself: dawkit's instrument (DawKitTine), the same one the engine plays MIDI items
## through, so what a player hears of their keys is what the take will sound like.
var _voice := DawKitTine.new(RATE)


func _exit_tree() -> void:
	stop()


## Whether this machine can make sound at all. A headless run has the Dummy driver and nothing
## would ever take the frames.
static func available() -> bool:
	return AudioServer.get_driver_name() != "Dummy"


func start() -> void:
	if _running or not available():
		return
	if allow_native and speaker == null and not AudioPorts.direct and NativeKeys.available():
		var keys := NativeKeys.new()
		if keys.start(AudioPorts.target):
			native = keys
			native.volume(volume_db)
			native.enable(enabled)
			_running = true
			return
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = RATE
	stream.buffer_length = 4096.0 / RATE
	if speaker != null:
		var out := Foley.emitter(stream, volume_db)
		out.name = "MonitorSynth"
		speaker.add_child(out)
		out.play()
		_playback = out.get_stream_playback()
		_player = out
	else:
		var out := AudioStreamPlayer.new()
		out.name = "MonitorSynth"
		out.bus = bus if bus != &"" else AudioPorts.bus(AudioPorts.MONITOR)
		out.stream = stream
		out.volume_db = volume_db
		add_child(out)
		out.play()
		_playback = out.get_stream_playback()
		_player = out
	_capacity = _playback.get_frames_available()
	_running = true
	_thread = Thread.new()
	_thread.start(_render_loop)


## Where the keys play from now on, moved while they play: a track's bus, or empty for the keys'
## own (Monitor).
func set_bus(to: StringName) -> void:
	bus = to
	if _player is AudioStreamPlayer:
		(_player as AudioStreamPlayer).bus = to if to != &"" else AudioPorts.bus(AudioPorts.MONITOR)


func stop() -> void:
	_running = false
	if native != null:
		native.stop()
		native = null
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	if _player != null:
		_player.call("stop")
		_player.queue_free()
	_player = null
	_playback = null


func is_running() -> bool:
	return _running


## How long after a key goes down its sound reaches the air, in seconds: the queue ahead of it
## and the card. A guest's note is stamped this much later than the key, because that is when
## the player heard it land against the mix. See GuestMidi.
func latency_seconds() -> float:
	if not _running:
		return 0.0
	if native != null:
		# Before its first note it has not counted: two cycles is what it measures at.
		return native.latency if native.latency > 0.0 else 2.0 * NativeKeys.QUANTUM / RATE
	# The queue ahead of a key, the mix step it then waits for, and the card. Measured by the
	# built-in probe's loopback: without the step, keys sounded 12ms after their stamps.
	return QUEUE_FRAMES / RATE + MIX_STEP / RATE + AudioServer.get_output_latency()


func note_on(pitch: int, velocity: int) -> void:
	if not enabled:
		return
	if native != null:
		native.note_on(pitch, velocity)
		return
	_queue([ON, pitch, velocity])


func note_off(pitch: int) -> void:
	if native != null:
		native.note_off(pitch)
		return
	_queue([OFF, pitch, 0])


## The sustain pedal: keys let go while it is down ring on until it comes up.
func sustain(down: bool) -> void:
	if native != null:
		native.sustain(down)
		return
	_queue([SUSTAIN, int(down), 0])


## A control on the keys: the pitch wheel (DawKitClip.PITCH_BEND, -8192 to 8191, every sounding
## note bent up to DawKitTine.BEND_SEMITONES), expression (11, the voice's level) or the mod wheel
## (1, which this tine has no use for and ignores). Through the event queue like a note, to
## DawKitTine.control on the render thread, or to the helper.
func control(kind: int, value: int) -> void:
	controls[kind] = value
	if native != null:
		native.control(kind, value)
		return
	_queue([CONTROL, kind, value])


## Every control back where it rests (Session.control_rest): at a player's last note-off.
func rest_controls() -> void:
	for kind in Session.CONTROL_KINDS:
		if int(controls.get(kind, Session.control_rest(kind))) != Session.control_rest(kind):
			control(kind, Session.control_rest(kind))


func all_off() -> void:
	if native != null:
		native.panic()
		return
	_queue([SUSTAIN, 0, 0])
	for p in 128:
		_queue([OFF, p, 0])


## The helper's news, read; and if it has gone, playing on through Godot.
func _process(_delta: float) -> void:
	if native == null:
		return
	native.poll()
	if not native.running():
		push_warning("The monitor keys' helper stopped; playing them through the app instead.")
		native = null
		_running = false
		allow_native = false
		start()


func _queue(event: Array) -> void:
	_mutex.lock()
	# Bounded: with no sound card nothing renders, and nothing would ever empty this.
	if _events.size() < 1024:
		_events.append(event)
	_mutex.unlock()


func _render_loop() -> void:
	while _running:
		var queued := _capacity - _playback.get_frames_available()
		if queued + 128 <= QUEUE_FRAMES:
			_playback.push_buffer(render(QUEUE_FRAMES - queued))
		OS.delay_usec(500)


func _apply_events() -> void:
	_mutex.lock()
	var events := _events
	_events = []
	_mutex.unlock()
	for e in events:
		match e[0]:
			ON:
				_voice.note_on(e[1], e[2])
			OFF:
				_voice.note_off(e[1])
			SUSTAIN:
				_voice.sustain(e[1] == 1)
			CONTROL:
				_voice.control(e[1], e[2])


## `count` frames of every sounding voice, mixed. Public so the suite can listen to it.
func render(count: int) -> PackedVector2Array:
	_apply_events()
	return _voice.render(count)


func sounding() -> int:
	return _voice.sounding()
