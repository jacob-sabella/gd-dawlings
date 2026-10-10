class_name GuestAudio
extends Node

## A guest's microphone, recorded into the host's project.
##
## The same idea as GuestMidi, for sound: the guest sings or plays along to the mix it hears,
## late, and the take is placed by the song position the guest was hearing, not by when the
## sound reached the host. The microphone is read continuously while armed. A take begins when
## the guest HEARS the host start recording and ends when it hears it stop, and is sent up to
## the host as it is made, a fifth of a second at a time, on its own reliable channel. When the
## take ends there is almost nothing left to send and the host can place it at once. See
## docs/architecture.md, "Recording a guest".
##
## Where a take starts. The newest frame a read returns left the microphone the input's latency
## before the read, at which moment the guest was hearing `heard - latency`. Every read gives one
## such estimate of where the take's first frame was in the song, and a capture that arrives in
## blocks makes each one jittery by up to a block. So the take's start is the mean of every
## estimate over its first second (their median), and is only sent to the host once that second
## is over.
##
## Staying there. The microphone has its own clock and the host's song has another: two sound
## cards a hundred parts per million apart drift 18ms over a three-minute take, enough to hear
## on a snare. So after the first second the same estimate keeps being made, against where the
## take's own frames say they are, and the difference steers the rate the microphone is
## resampled at -- a small PI loop, critically damped, settling in a few seconds. Every frame of
## the take is then where the song was when the guest heard it, from the first second to the
## last. A jump in the song (a loop going round, a seek) ends the take there; the next one
## begins at once.

signal changed()

const RATE := 48000
## How much is gathered before it is sent: small enough that the end of a take is never far
## behind, large enough not to be a packet storm.
const SEND_SECONDS := 0.2
## How long the take's start is refined for before it is sent.
const SETTLE_SECONDS := 1.0
## The rate loop: per second of error, and per second of error per second. Critically damped
## (TRACK_GAIN squared is four times DRIFT_GAIN).
const TRACK_GAIN := 1.0
const DRIFT_GAIN := 0.25
## Far beyond any two sound cards, short of letting a bad reading bend the pitch audibly.
const RATIO_LIMIT := 0.002
## Further than this from where the take's frames say they are is the song jumping, not drift.
const JUMP_SECONDS := 0.25

## The track a take goes onto; 0 for none chosen.
var target_track := 0:
	set(v):
		target_track = v
		changed.emit()
## Record when the host records. Off by default: a microphone is opt-in.
var record_with_host := false:
	set(v):
		record_with_host = v
		changed.emit()
## Which input to record, by AudioServer's name for it; empty for the system's default.
var input_device := "":
	set(v):
		input_device = v
		if _source != null:
			_close_mic()
		changed.emit()
## Latency the input has beyond what it reports, in msec, from calibration. A take lands this
## much earlier.
var offset_ms := 0.0
## How loud the microphone is now, 0-1, for the panel's meter. Moves while armed, recording or
## not, so the level can be set before the take.
var level := 0.0
## What the last take did, for the panel: {seconds, track, start} or empty.
var last_take := {}
var takes_sent := 0
## Makes the microphone. The default is this machine's audio input; the probe gives its own.
var make_source: Callable = func() -> MixSource:
	return MixSource.input(input_device, "Your microphone", "mic")
## Where the song position being heard comes from. GuestMidi's account is the one used for
## notes, so a voice and a keyboard played together land together.
var heard: Callable = func() -> Dictionary:
	return Session.guest_midi.heard()
## Where the take goes: Session, which sends it to the host. The suite gives its own.
var sink: Object = null
## The host's own recorder rather than a guest's (Session.host_audio): armed on a host or alone,
## and only while the DAW does not record its own inputs.
var for_host := false

var _source: MixSource = null
var _resampler := Resampler.new()
var _take_open := false
## The track the take in progress was begun on.
var _take_into := 0
var _take_id := 0
## The start estimates so far, while settling; and the settled start once sent.
var _estimates: Array[float] = []
var _start := 0.0
## Where the first frame the host got sits in the song: _start, less what was trimmed off.
var _sent_start := 0.0
var _begun := false
var _frames := 0
var _unsent := PackedVector2Array()
## Output frames per input frame, and the loop's state.
var _ratio := 1.0
var _error := 0.0
var _drift := 0.0


func armed() -> bool:
	if for_host:
		return Session.is_authority() and take_track() > 0 and record_with_host \
				and DAW.backend != null and not DAW.can(DAWBackend.Capability.RECORDS_OWN_INPUTS)
	return Session.role == Session.Role.GUEST and target_track > 0 and record_with_host


## The track a take goes onto: the one chosen; on the host with none chosen, the armed one.
func take_track() -> int:
	if target_track > 0 or not for_host:
		return target_track
	return HitRecorder.armed_track()


func is_recording() -> bool:
	return _take_open


func take_seconds() -> float:
	return float(_frames) / RATE


## How far the microphone's clock is from the song's, as the loop has found it, in parts per
## million. For the panel, and the probe.
func drift_ppm() -> float:
	return (_ratio - 1.0) * 1000000.0


func _process(delta: float) -> void:
	if not armed():
		if _take_open:
			_end()
		if _source != null:
			_close_mic()
		return
	if _source == null and not _open_mic():
		return
	var got := _read()
	var peak := 0.0
	for f in got:
		peak = maxf(peak, absf(f.x))
	level = maxf(peak, level - delta * 1.5)
	follow(heard.call(), got)


## The take, following what the guest hears of the host's transport.
func follow(h: Dictionary, got: PackedVector2Array) -> void:
	var rolling: bool = h["valid"] and h["recording"]
	if not _take_open:
		if rolling:
			# What was read before recording was heard to start is not the take. The take is
			# everything from the next frame on.
			_take_open = true
			_take_id += 1
			_frames = 0
			_begun = false
			_estimates.clear()
			_unsent = PackedVector2Array()
			_error = 0.0
			changed.emit()
		return
	_unsent.append_array(got)
	_frames += got.size()
	# The newest frame was heard at `heard - latency`; the first is _frames - 1 earlier.
	var newest := float(h["seconds"]) - (_source.latency_ms() + offset_ms) / 1000.0
	if not _begun:
		_estimates.append(newest - float(_frames - 1) / RATE)
	elif rolling and not got.is_empty():
		var off := newest - (_start + float(_frames - 1) / RATE)
		if absf(off) > JUMP_SECONDS:
			_end()
			return
		_steer(off, got.size() / float(RATE))
	if not rolling:
		_end()
	elif _unsent.size() >= int(SEND_SECONDS * RATE):
		if _begun or _frames >= int(SETTLE_SECONDS * RATE):
			_flush()


func _flush() -> void:
	if not _begun:
		_start = _settled_start()
		# Sound from before the song's first moment has nowhere to go: a take begun at the top
		# of the song, heard late, starts a little before zero. Every frame is still unsent.
		var before := maxi(ceili(-_start * RATE), 0)
		_unsent = _unsent.slice(mini(before, _unsent.size()))
		_sent_start = _start + float(before) / RATE
		takes_sent += 1
		var take_name := "%s audio %d" % [Session.local_name, takes_sent]
		_take_into = take_track()
		_sink().send_audio_begin(_take_id, _take_into, _sent_start, take_name)
		_begun = true
	if not _unsent.is_empty():
		_sink().send_audio_chunk(_take_id, AudioTake.encode(_unsent))
		_unsent = PackedVector2Array()


func _end() -> void:
	if _frames > 0:
		_flush()
		_sink().send_audio_end(_take_id)
		last_take = {"seconds": take_seconds(), "track": _take_into, "start": _sent_start}
	_take_open = false
	changed.emit()


## The rate loop. The error is smoothed first: each reading is only as good as the capture's
## block size, and the loop should follow the clock, not the blocks.
func _steer(off: float, dt: float) -> void:
	_error += (off - _error) * 0.1
	_drift = clampf(_drift + _error * DRIFT_GAIN * dt, -RATIO_LIMIT, RATIO_LIMIT)
	_ratio = clampf(1.0 + _drift + _error * TRACK_GAIN, 1.0 - RATIO_LIMIT, 1.0 + RATIO_LIMIT)


func _sink() -> Object:
	return sink if sink != null else Session


## The median rather than the mean: one reading taken across a block boundary, or in the
## moment a clock corrects, is a long way out, and should not drag the take with it.
func _settled_start() -> float:
	if _estimates.is_empty():
		return 0.0
	var sorted := _estimates.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _open_mic() -> bool:
	_source = make_source.call()
	if _source == null or not _source.start():
		_source = null
		return false
	_resampler.reset()
	# A new microphone is a new clock.
	_ratio = 1.0
	_drift = 0.0
	changed.emit()
	return true


func _close_mic() -> void:
	_source.stop()
	_source = null
	level = 0.0
	changed.emit()


func _read() -> PackedVector2Array:
	# Fewer input frames per output frame when the song is running ahead of the take.
	var steer := _ratio if _take_open and _begun else 1.0
	return _resampler.resample(_source.read(), _source_rate() / steer, RATE)


func _source_rate() -> float:
	return _source.rate() if _source.has_method(&"rate") else AudioServer.get_input_mix_rate()


func mic_open() -> bool:
	return _source != null


## Tracks were added or removed on the host: the chosen track is still the same track, and none
## once it is gone.
func follow_renumber(map: Dictionary) -> void:
	if target_track > 0:
		target_track = int(map.get(target_track, 0))
