class_name MonitorSynth
extends Node

## A small electric piano, so a guest hears their own keys the instant they press them.
##
## The round trip is not an option for this. A note sent to the host, played by its Reaper, and
## streamed back arrives about 90ms after the key went down -- long past the 10-20ms at which a
## player stops feeling the instrument as theirs. So the guest monitors locally, and what the
## host records is the guest's stamped notes, not the sound of them.
##
## The tone is the classic two-operator tine: a sine carrier phase-modulated by a sine at the
## same frequency, its index falling from bright to mellow over a quarter second, plus a short
## high partial for the strike. Soft at low velocity and barking a little when hit hard, which
## is what makes it pleasant to play rather than merely audible. Sixteen voices; the oldest is
## taken when they run out.
##
## Where it can, it does not play through Godot at all: NativeKeys runs the same synth as a
## PipeWire node of its own, in the graph's realtime callback, with MIDI read straight from the
## sequencer -- about 4.5ms key to sink against 30-50ms through Godot's mixer. `native` is that
## helper while it runs. Where it cannot, this renders on its own thread, half a millisecond at a
## time, into a generator kept as short as Godot's mixer allows -- the same reasoning, and the
## same numbers, as MixFeed's playback.

const RATE := 48000.0
const VOICES := 16
## Godot's mixer takes this many frames at once; the queue must hold one gulp and a little more.
const MIX_STEP := 512
const QUEUE_FRAMES := 768
const TABLE := 4096
enum { OFF, ON, SUSTAIN }

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
			_player.volume_db = v
		if native != null:
			native.volume(v)
## The helper this plays through, while it runs; null when playing through Godot.
var native: NativeKeys = null
## Off: always through Godot. For the suite, and R3D_GODOT_KEYS=1 to compare.
var allow_native := OS.get_environment("R3D_GODOT_KEYS") != "1"

var _player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _capacity := 0
var _thread: Thread = null
var _running := false
var _mutex := Mutex.new()
## Note events from the main thread, applied by the render thread: [on?, pitch, velocity].
var _events: Array = []
var _sustain := false
## Per voice: whether its key is still down. A key let go under the pedal rings until it lifts.
var _held := PackedByteArray()
var _sine := PackedFloat32Array()

# Voices, as parallel arrays: the render loop is the hot path of this whole feature.
var _pitch := PackedInt32Array()
var _phase := PackedFloat32Array()
var _tine := PackedFloat32Array()
var _inc := PackedFloat32Array()
var _amp := PackedFloat32Array()
var _index := PackedFloat32Array()
var _decay := PackedFloat32Array()
var _release := PackedFloat32Array()
var _attack := PackedFloat32Array()
var _pan := PackedFloat32Array()
var _strike := PackedFloat32Array()
var _born := PackedInt64Array()
var _clock := 0


func _ready() -> void:
	_sine.resize(TABLE)
	for i in TABLE:
		_sine[i] = sin(TAU * i / TABLE)
	# One by one: packed arrays are values, and resizing the loop variable resizes a copy.
	_pitch.resize(VOICES)
	_phase.resize(VOICES)
	_tine.resize(VOICES)
	_inc.resize(VOICES)
	_amp.resize(VOICES)
	_index.resize(VOICES)
	_decay.resize(VOICES)
	_release.resize(VOICES)
	_attack.resize(VOICES)
	_pan.resize(VOICES)
	_strike.resize(VOICES)
	_born.resize(VOICES)
	_held.resize(VOICES)
	_pitch.fill(-1)
	_amp.fill(0.0)


func _exit_tree() -> void:
	stop()


## Whether this machine can make sound at all. A headless run has the Dummy driver and nothing
## would ever take the frames.
static func available() -> bool:
	return AudioServer.get_driver_name() != "Dummy"


func start() -> void:
	if _running or not available():
		return
	if allow_native and not AudioPorts.direct and NativeKeys.available():
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
	_player = AudioStreamPlayer.new()
	_player.name = "MonitorSynth"
	_player.bus = AudioPorts.bus(AudioPorts.MONITOR)
	_player.stream = stream
	_player.volume_db = volume_db
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()
	_capacity = _playback.get_frames_available()
	_running = true
	_thread = Thread.new()
	_thread.start(_render_loop)


func stop() -> void:
	_running = false
	if native != null:
		native.stop()
		native = null
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	if _player != null:
		_player.stop()
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
	return QUEUE_FRAMES / RATE + AudioServer.get_output_latency()


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
				_start_voice(e[1], e[2])
			OFF:
				for v in VOICES:
					if _pitch[v] == e[1] and _held[v] == 1:
						_held[v] = 0
						if not _sustain:
							_damp(v)
			SUSTAIN:
				_sustain = e[1] == 1
				if not _sustain:
					for v in VOICES:
						if _pitch[v] >= 0 and _held[v] == 0:
							_damp(v)


## Damper down: 60dB in about 150ms, quick enough to stop, slow enough not to click.
func _damp(v: int) -> void:
	if _release[v] == 1.0:
		_release[v] = 0.99904


func _start_voice(pitch: int, velocity: int) -> void:
	var v := -1
	var oldest := 0
	for i in VOICES:
		if _amp[i] < 0.0005:
			v = i
			break
		if _born[i] < _born[oldest]:
			oldest = i
	if v < 0:
		v = oldest
	var hz := 440.0 * pow(2.0, (pitch - 69) / 12.0)
	var vel := clampf(velocity / 127.0, 0.0, 1.0)
	_pitch[v] = pitch
	_inc[v] = hz * TABLE / RATE
	_phase[v] = 0.0
	_tine[v] = 0.0
	# Louder and brighter together, on a curve: a light touch should be properly quiet.
	_amp[v] = 0.05 + 0.22 * vel * vel
	_index[v] = 0.6 + 2.2 * vel
	_attack[v] = 0.0
	# Low notes ring on, high ones die quickly: seconds to fall by 60dB, from 6s down to 1.5s.
	var ring := clampf(6.0 * pow(0.5, (pitch - 40) / 24.0), 1.5, 6.0)
	_decay[v] = pow(0.001, 1.0 / (ring * RATE))
	_release[v] = 1.0
	_held[v] = 1
	_pan[v] = clampf((pitch - 64) / 90.0, -0.35, 0.35)
	# The strike partial sits fourteen times up; above the top of hearing it would only alias.
	_strike[v] = _amp[v] * 0.35 if hz * 14.0 < 16000.0 else 0.0
	_clock += 1
	_born[v] = _clock


## `count` frames of every sounding voice, mixed. Public so the suite can listen to it.
func render(count: int) -> PackedVector2Array:
	_apply_events()
	var out := PackedVector2Array()
	out.resize(count)
	var index_fall := pow(0.12, 1.0 / (0.25 * RATE))
	for v in VOICES:
		var amp := _amp[v]
		if amp < 0.0005:
			continue
		var phase := _phase[v]
		var tine := _tine[v]
		var inc := _inc[v]
		var index := _index[v]
		var decay := _decay[v] * _release[v]
		var attack := _attack[v]
		var left := 0.5 - _pan[v]
		var right := 0.5 + _pan[v]
		var tine_amp := _strike[v]
		for i in count:
			var m := _sine[int(phase) & (TABLE - 1)] * index * (TABLE * 0.159)
			var strike := _sine[int(tine) & (TABLE - 1)] * tine_amp
			var s := (_sine[int(phase + m) & (TABLE - 1)] * amp + strike) * attack
			out[i] += Vector2(s * left, s * right) * 2.0
			phase += inc
			if phase >= TABLE:
				phase -= TABLE
			tine += inc * 14.0
			if tine >= TABLE:
				tine -= TABLE * floorf(tine / TABLE)
			amp *= decay
			tine_amp *= 0.9993
			index = index * index_fall + 0.12 * (1.0 - index_fall)
			attack = minf(1.0, attack + 1.0 / 96.0)
		_amp[v] = amp
		_strike[v] = tine_amp
		_phase[v] = phase
		_tine[v] = tine
		_index[v] = index
		_attack[v] = attack
		if amp < 0.0005:
			_pitch[v] = -1
	# Gentle saturation, so a fistful of keys gets fuller rather than clipping.
	for i in count:
		var f := out[i]
		out[i] = Vector2(f.x / (1.0 + absf(f.x)), f.y / (1.0 + absf(f.y)))
	return out


func sounding() -> int:
	var n := 0
	for v in VOICES:
		if _amp[v] >= 0.0005:
			n += 1
	return n
