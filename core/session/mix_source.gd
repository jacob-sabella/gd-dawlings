class_name MixSource
extends RefCounted

## Where the host's programme audio comes from. Read from the feed's own thread, so `read` must
## be safe to call off the main thread and must never block.
##
## The base class is silence, which is the honest source for a host with nothing to share --
## the offline stand-in has meters and no sound.

func start() -> bool:
	return true


func stop() -> void:
	pass


## Every frame that has arrived since the last call. Possibly none.
func read() -> PackedVector2Array:
	return PackedVector2Array()


## A sentence for the session panel: where the sound guests hear comes from.
func describe() -> String:
	return "No mix audio to share."


## How long a frame sits in this source before `read` can return it, in msec. Part of the
## latency figure a guest is shown.
func latency_ms() -> float:
	return 0.0


## How long before `read` returned it the newest frame was the song's "now", in msec: what the
## host takes off its song clock when it stamps a packet. See MixFeed and docs/architecture.md,
## "Recording a guest". Zero for a source that makes its sound on the spot.
func song_offset_ms() -> float:
	return 0.0


## An input to read `device` (a source's name; empty for the default) through: a named stream
## of its own where this process's sound goes out through AudioPorts, so it can be routed like
## them, and Godot's one audio input where not.
static func input(device: String, what: String, port: String) -> MixSource:
	if AudioPorts.active and AudioPorts.supported("parec"):
		return Piped.new(device, what, port)
	return Captured.new(device, what)


## Whatever this machine's audio input is set to: on a host, the tap MixTap built over the
## DAW's outputs. Read with AudioServer's direct capture, not an AudioStreamMicrophone, so the
## mix is never played back out of the host's own speakers on top of itself.
class Captured extends MixSource:
	var device := ""
	var label := ""

	func _init(input_device: String, what: String) -> void:
		device = input_device
		label = what

	func start() -> bool:
		# Small capture fragments. Godot asks PulseAudio for none in particular, which on
		# PipeWire comes back as 1024 frames -- 21ms of every guest's delay spent waiting for a
		# buffer to fill. libpulse reads this when a stream CONNECTS, so set now it shapes the
		# capture stream and not the output stream, which opened at startup. Left set rather
		# than restored: choosing the input device below reopens the capture stream on the
		# audio thread a moment later, and a value already put back is the one it would read.
		OS.set_environment("PULSE_LATENCY_MSEC", "3")
		var ok := AudioServer.set_input_device_active(true) == OK
		if ok and not device.is_empty():
			AudioServer.input_device = device
		return ok

	func stop() -> void:
		AudioServer.set_input_device_active(false)

	func read() -> PackedVector2Array:
		var n := AudioServer.get_input_frames_available()
		if n <= 0:
			return PackedVector2Array()
		return AudioServer.get_input_frames(n)

	func describe() -> String:
		return label

	func latency_ms() -> float:
		return 256.0 * 1000.0 / AudioServer.get_input_mix_rate()

	## The capture fragment, by default: Reaper reports the position it is PLAYING (its own
	## output latency already allowed for), the tap hears those frames as the sink does, and
	## they then wait up to a fragment before this process can read them. Not measured against
	## a real Reaper yet -- R3D_CAPTURE_OFFSET_MS overrides it for a host that has been.
	func song_offset_ms() -> float:
		var told := OS.get_environment("R3D_CAPTURE_OFFSET_MS")
		return float(told) if told.is_valid_float() else latency_ms()


## A capture stream of its own, named "reaper-3d · <port>", read from `parec`'s output: the
## input side of AudioPorts. It starts on `device` (the default source when empty) and can be
## moved to any other source, or have anything linked into it, from a patchbay. Raw stereo
## float at 48kHz; `read` takes whatever the pipe holds without waiting, and keeps a partial
## frame back for the next call.
class Piped extends MixSource:
	## Asked of the server: how much it gathers before handing it over. The same 3ms as
	## Captured asks of Godot's input.
	const LATENCY_MS := 3
	const RATE := 48000
	var device := ""
	var label := ""
	var title := ""
	## The program, and anything in front of its arguments: a stand-in in the suite.
	var tool := "parec"
	var prefix: PackedStringArray = []
	var _pid := -1
	var _pipe: FileAccess
	var _spare := PackedByteArray()

	func _init(input_device: String, what: String, port: String) -> void:
		device = "" if input_device == "Default" else input_device
		label = what
		title = "reaper-3d · " + port

	func arguments() -> PackedStringArray:
		var args := PackedStringArray(["--record", "--raw", "--format=float32le", "--rate=%d" % RATE,
				"--channels=2", "--latency-msec=%d" % LATENCY_MS, "--client-name=" + title,
				"--stream-name=" + title, "--property=node.name=reaper3d_" + title.get_slice("· ", 1).replace(" ", "_"),
				"--property=node.description=" + title, "--property=application.name=" + title])
		if not device.is_empty():
			args.append("--device=" + device)
		return args

	func start() -> bool:
		if _pipe != null:
			return true
		var piped := OS.execute_with_pipe(tool, prefix + arguments(), false)
		if piped.is_empty():
			return false
		_pid = piped["pid"]
		_pipe = piped["stdio"]
		return true

	func stop() -> void:
		if _pipe != null:
			_pipe.close()
			_pipe = null
		if _pid > 0 and OS.is_process_running(_pid):
			OS.kill(_pid)
		_pid = -1
		_spare.clear()

	func read() -> PackedVector2Array:
		if _pipe == null:
			return PackedVector2Array()
		var bytes := _spare + _pipe.get_buffer(1 << 16)
		var whole := bytes.size() / 8 * 8
		_spare = bytes.slice(whole)
		var samples := bytes.slice(0, whole).to_float32_array()
		var out := PackedVector2Array()
		out.resize(samples.size() / 2)
		for i in out.size():
			out[i] = Vector2(samples[i * 2], samples[i * 2 + 1])
		return out

	func rate() -> float:
		return RATE

	func describe() -> String:
		return label

	func latency_ms() -> float:
		return LATENCY_MS + 1.0

	func song_offset_ms() -> float:
		var told := OS.get_environment("R3D_CAPTURE_OFFSET_MS")
		return float(told) if told.is_valid_float() else latency_ms()


## A tone with a click on every second: something to hear, and something to time. Used where
## there is no DAW making sound -- the probe, and a host on the offline stand-in.
##
## Given the host's song clock, the clicks fall on every whole second OF THE SONG while it
## rolls, instead of every second of the wall clock (which they go back to while it is stopped): a click track locked to the song, which is
## what lets the probe check a guest's take against the beat it actually heard.
class Tone extends MixSource:
	var rate := 48000.0
	var hz := 440.0
	var clock: SongClock = null
	var _start_usec := 0
	var _made := 0
	var _last_song_second := -1

	func start() -> bool:
		_start_usec = Time.get_ticks_usec()
		_made = 0
		return true

	func read() -> PackedVector2Array:
		var due := int((Time.get_ticks_usec() - _start_usec) * rate / 1000000.0)
		var count := mini(due - _made, 4800)
		var out := PackedVector2Array()
		if count <= 0:
			return out
		out.resize(count)
		var song := {}
		if clock != null:
			song = clock.at(_start_usec + int((_made) * 1000000.0 / rate))
		var click_left := 0
		for i in count:
			var n := _made + i
			var t := n / rate
			var s := sin(TAU * hz * t) * 0.2
			if song.get("playing", false):
				var second := int(floor(float(song["seconds"]) + i / rate))
				if _last_song_second >= 0 and second != _last_song_second:
					click_left = int(rate / 1000.0)
				_last_song_second = second
			else:
				_last_song_second = -1
				# The click: one millisecond of full scale at the top of each second.
				if n % int(rate) < int(rate / 1000.0):
					click_left = 1
			if click_left > 0:
				s = 0.9
				click_left -= 1
			out[i] = Vector2(s, s)
		_made += count
		return out

	func describe() -> String:
		return "A test tone (no DAW audio on this host)."
