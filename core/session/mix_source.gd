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
