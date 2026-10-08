class_name HeardClock
extends RefCounted

## Which moment of the host's song is coming out of this guest's speakers right now.
##
## Two facts, joined:
##
##   STAMPS   every packet of the mix carries the host's song position for its first frame
##            (MixFeed). So any frame of the stream -- counted from the host's first packet --
##            has a song position: its packet's stamp plus how far into the packet it is.
##   PLAYHEAD which frame of the stream is at the speaker now: the jitter buffer's read head,
##            less what is queued in the sound card's generator, less the card's own latency.
##            Measured by the feed's thread every half millisecond.
##
## The playhead measurement is a staircase -- Godot's mixer swallows 512 frames at once, so the
## queue drops by 10.7ms in one go and refills smoothly -- and stamping a note off the staircase
## would put up to 10ms of sawtooth into every take. So the measurement corrects a clock that
## runs at the stream's own rate between measurements, slowly enough to average the teeth away.
##
## Pure arithmetic over numbers it is handed, so the suite can drive it with a made-up stream.

const RATE := 48000.0
## Stamps remembered, in packets: 5.5 seconds of stream, far more than any buffer holds.
const RING := 2048
## A measurement further than this from the running estimate is a jump (a reprime, a stream
## that restarted), taken at once rather than eased into.
const SNAP_FRAMES := 4800.0
## Per measurement. At one every half millisecond the time constant is about a quarter second,
## long against the 10.7ms staircase and short against anything a clock does.
const GAIN := 0.002
## A stream with no stamps for this long is not telling us anything any more.
const STALE_USEC := 1000000

var frames_per_packet := 128

var _mutex := Mutex.new()
var _seq := PackedInt64Array()
var _position := PackedFloat64Array()
var _flags := PackedInt32Array()
var _estimate := NAN
var _estimate_usec := 0
var _stamped_usec := 0


func _init() -> void:
	_seq.resize(RING)
	_seq.fill(-1)
	_position.resize(RING)
	_flags.resize(RING)


## One packet's stamp: its sequence number, the song position of its first frame, and its
## MixFeed.FLAG_* bits.
func stamp(seq: int, position: float, flags: int, now_usec: int = -1) -> void:
	_mutex.lock()
	var at := seq % RING
	_seq[at] = seq
	_position[at] = position
	_flags[at] = flags
	_stamped_usec = now_usec if now_usec >= 0 else Time.get_ticks_usec()
	_mutex.unlock()


## The stream frame at the speaker at `now_usec`, as measured.
func observe(speaker_frame: float, now_usec: int) -> void:
	_mutex.lock()
	if is_nan(_estimate):
		_estimate = speaker_frame
	else:
		var predicted := _estimate + (now_usec - _estimate_usec) * RATE / 1000000.0
		var error := speaker_frame - predicted
		_estimate = speaker_frame if absf(error) > SNAP_FRAMES else predicted + error * GAIN
	_estimate_usec = now_usec
	_mutex.unlock()


func reset() -> void:
	_mutex.lock()
	_estimate = NAN
	_seq.fill(-1)
	_mutex.unlock()


## The stream frame at the speaker at `now_usec`, or NAN before anything was measured.
func frame_at(now_usec: int) -> float:
	_mutex.lock()
	var out := _estimate
	if not is_nan(out):
		out += (now_usec - _estimate_usec) * RATE / 1000000.0
	_mutex.unlock()
	return out


## The song position of one stream frame: {seconds, playing, recording, valid}.
func position_of(frame: float) -> Dictionary:
	var none := {"seconds": 0.0, "playing": false, "recording": false, "valid": false}
	if is_nan(frame) or frame < 0.0:
		return none
	_mutex.lock()
	var seq := int(floor(frame / frames_per_packet))
	# The packet itself, or the nearest one before it that arrived: a lost packet's frames are
	# still a known distance from the last stamp heard.
	var found := -1
	for back in 64:
		var s := seq - back
		if s < 0:
			break
		if _seq[s % RING] == s:
			found = s
			break
	if found < 0:
		_mutex.unlock()
		return none
	var at := found % RING
	var flags := _flags[at]
	var playing := (flags & MixFeed.FLAG_PLAYING) != 0
	var seconds := _position[at]
	if playing:
		seconds += (frame - found * frames_per_packet) / RATE
	_mutex.unlock()
	return {"seconds": seconds, "playing": playing,
			"recording": playing and (flags & MixFeed.FLAG_RECORDING) != 0,
			"valid": (flags & MixFeed.FLAG_VALID) != 0}


## What the speakers are playing at `now_usec`.
func at(now_usec: int) -> Dictionary:
	var out := position_of(frame_at(now_usec))
	_mutex.lock()
	var stale := now_usec - _stamped_usec > STALE_USEC
	_mutex.unlock()
	if stale:
		out["valid"] = false
	return out
