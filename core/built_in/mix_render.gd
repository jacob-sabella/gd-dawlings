class_name MixRender
extends Node

## The built-in engine's mix, and each track's stem, written to WAV files as the song plays.
##
## In real time, because Godot mixes only as fast as a sound card takes it: the transport plays
## the range once and what each bus put out is kept. Faster than real time waits on the engine
## doing its own mixing (see "Waiting on the user" in the backlog).
##
## What is kept is a capture at the end of each bus -- the master's, and each stem track's --
## which hears the bus after its effects and before its fader, because Godot applies a bus's
## volume as it sends it on. So each block of frames is multiplied by the fader the bus had while
## they were mixed: the one set before the frame that reads them. A muted track's stem is silence.
##
## Lined up to the song: the captures are emptied, the transport started and the engine's players
## set going inside one hold of the audio lock, so the first frame captured is the first the
## players play, from where they were told to start -- the song position plus the time to the
## next mix (GodotBackend.start_at).
## The render starts PREROLL before the range where it can, and the frames before the range are
## dropped.
##
## And it ends after the range by as long as the mix takes to fall silent -- a reverb's ring, a
## note's release -- up to TAIL_SECONDS: at the range's end the transport stops, so nothing more
## of the song plays, and the buses go on putting out what their effects still hold. The files
## are cut at the last frame any of them is louder than SILENT_DB. The transport stops on the
## first frame past the range, so up to a frame (17 ms at 60 frames a second) of what follows the
## range can be in the tail's first moment; sample-exact stopping waits on the engine mixing its
## own players (see "Waiting on the user").

signal finished(files: PackedStringArray, problems: PackedStringArray)

const PREROLL := 0.25
## The longest a tail may ring after the range.
const TAIL_SECONDS := DAWBackend.RENDER_TAIL_SECONDS
## Below this, a frame is silence for the tail's end.
const SILENT_DB := -80.0
## How long the mix must have been silent for the tail to be over.
const SILENT_HOLD := 0.2
## Frames a capture holds between reads: far more than a frame takes, so none is lost on a slow one.
const CAPTURE_SECONDS := 2.0

var backend: GodotBackend
var from := 0.0
var to := 0.0
## Where the files go, and what they are called: "<name> - mix.wav", "<name> - <track>.wav".
var folder := ""
var name_stem := ""
## The files' depth: 16 or 24 (dithered integer) or 32 (float). See DawKitAudioFile.write_wav.
var bits := 24
## The files' sample rate: the mix as captured, at the engine's rate, is resampled to it when it differs.
var file_rate := 48000
## The mix brought to a peak of DAWBackend.RENDER_NORMALISE_DB, the stems by the mix's gain.
var normalise := false
## Track indices to write stems of; the mix is always written.
var stems: Array = []
## Hear each stem at unity, before its fader and mute: what freezing a track keeps, so the fader
## still moves the frozen sound.
var pre_fader := false

## 0 for the master, else the track: [bus index, capture, frames so far, gain for the next read].
var _taps := {}
var _skip := 0
var _wanted := 0
var _rate := 48000
var _started := false
var _played_from := 0.0
## Past the range: the transport stopped, the effects ringing out.
var _tailing := false


## Starts once the engine's parts are ready. Answers a problem, or "".
func begin() -> String:
	if to - from <= 0.01:
		return "there is nothing to render between %.2fs and %.2fs" % [from, to]
	_rate = int(AudioServer.get_mix_rate())
	_wanted = int(roundf((to - from) * _rate))
	_tap(0, backend._master_bus)
	for index in stems:
		if backend._bus.has(index):
			_tap(index, backend._bus[index])
	DAW.transport_stop()
	_played_from = maxf(from - PREROLL, 0.0)
	DAW.seek(_played_from)
	return ""


func _tap(key: int, bus: int) -> void:
	var capture := AudioEffectCapture.new()
	capture.buffer_length = CAPTURE_SECONDS
	AudioServer.add_bus_effect(bus, capture)
	_taps[key] = [bus, capture, PackedVector2Array(), _gain(key, bus)]


## What the bus's fader multiplies its sound by now; nothing while it is muted.
func _gain(key: int, bus: int) -> float:
	if pre_fader and key != 0:
		return 1.0
	if key != 0 and AudioServer.is_bus_mute(bus):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(bus))


func _process(_delta: float) -> void:
	if not _started:
		# The engine's parts render in the background; a part not ready yet would be silence.
		if not backend._waiting_roles().is_empty():
			return
		AudioServer.lock()
		for key in _taps:
			(_taps[key][1] as AudioEffectCapture).clear_buffer()
		var first_frame_at := backend.first_frame_at(_played_from)
		DAW.transport_play()
		# The engine starts its players on its next frame, by which time mixes have gone by;
		# started here, in the same hold of the lock, the first frame mixed is theirs.
		backend._drive_meters(0.0)
		AudioServer.unlock()
		_skip = int(roundf((from - first_frame_at) * _rate))
		_started = true
		return
	_drain()
	var have := (_taps[0][2] as PackedVector2Array).size()
	if not _tailing:
		if have >= _skip + _wanted:
			_tailing = true
			DAW.transport_stop()
		return
	var tail := have - (_skip + _wanted)
	if tail >= int(TAIL_SECONDS * _rate) or (tail >= int(SILENT_HOLD * _rate) and _quiet_since(have - int(SILENT_HOLD * _rate))):
		_finish()


## Whether every tap has been below SILENT_DB from frame `from` on.
func _quiet_since(from: int) -> bool:
	var floor_level := db_to_linear(SILENT_DB)
	for key in _taps:
		var frames: PackedVector2Array = _taps[key][2]
		for i in range(maxi(from, 0), frames.size()):
			if absf(frames[i].x) > floor_level or absf(frames[i].y) > floor_level:
				return false
	return true


## The frames to keep after the range's start: the range, and the tail up to its last sound.
func _kept_frames() -> int:
	var floor_level := db_to_linear(SILENT_DB)
	var last := _wanted
	for key in _taps:
		var frames: PackedVector2Array = _taps[key][2]
		var i := mini(frames.size(), _skip + _wanted + int(TAIL_SECONDS * _rate)) - 1
		while i >= _skip + last:
			if absf(frames[i].x) > floor_level or absf(frames[i].y) > floor_level:
				last = i - _skip + 1
				break
			i -= 1
	return last


func _drain() -> void:
	AudioServer.lock()
	var got := {}
	for key in _taps:
		var c: AudioEffectCapture = _taps[key][1]
		got[key] = c.get_buffer(c.get_frames_available())
	AudioServer.unlock()
	# The master's count is the frames mixed; a bus that was given nothing to mix has fewer.
	var n: int = (got[0] as PackedVector2Array).size()
	for key in _taps:
		var tap: Array = _taps[key]
		var block: PackedVector2Array = got[key]
		if block.size() < n:
			var silence := PackedVector2Array()
			silence.resize(n - block.size())
			block = silence + block
		elif block.size() > n:
			block = block.slice(block.size() - n)
		var gain: float = tap[3]
		if not is_equal_approx(gain, 1.0):
			for i in block.size():
				block[i] *= gain
		tap[2] = (tap[2] as PackedVector2Array) + block
		tap[3] = _gain(key, tap[0])


func _finish() -> void:
	set_process(false)
	DAW.transport_stop()
	var kept := _kept_frames()
	var files := PackedStringArray()
	var problems := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(folder)
	var cut := {}
	for key in _taps:
		var tap: Array = _taps[key]
		var frames: PackedVector2Array = tap[2]
		if _skip < 0:
			var lead := PackedVector2Array()
			lead.resize(-_skip)
			frames = lead + frames
		else:
			frames = frames.slice(_skip)
		# Every file the same length, the range and the mix's tail; a quiet stem has silence there.
		frames = frames.slice(0, kept)
		if frames.size() < kept:
			var pad := PackedVector2Array()
			pad.resize(kept - frames.size())
			frames += pad
		cut[key] = frames
	var gain := normalise_gain(cut[0]) if normalise else 1.0
	for key in _taps:
		var frames: PackedVector2Array = cut[key]
		if file_rate != _rate:
			frames = Resampler.new().resample(frames, _rate, file_rate)
		var samples := PackedFloat32Array()
		samples.resize(frames.size() * 2)
		for i in frames.size():
			samples[i * 2] = frames[i].x * gain
			samples[i * 2 + 1] = frames[i].y * gain
		var label := "mix" if key == 0 else DAW.state.track(key).display_name()
		var path := folder.path_join("%s - %s.wav" % [name_stem, label.validate_filename()])
		var err := DawKitAudioFile.write_wav(path, samples, 2, file_rate, bits)
		if err == OK:
			files.append(path)
		else:
			problems.append("%s could not be written (%s)" % [path.get_file(), error_string(err)])
	_untap()
	finished.emit(files, problems)
	queue_free()


## What brings `frames`' loudest sample to DAWBackend.RENDER_NORMALISE_DB: up for a quiet mix,
## down for one over full scale. 1 for silence, which no gain makes louder.
static func normalise_gain(frames: PackedVector2Array) -> float:
	var peak := 0.0
	for f in frames:
		peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
	return db_to_linear(DAWBackend.RENDER_NORMALISE_DB) / peak if peak > 0.000001 else 1.0


## Takes the captures off again, wherever on their buses they now are.
func _untap() -> void:
	for key in _taps:
		var bus: int = _taps[key][0]
		if bus < 0 or bus >= AudioServer.bus_count:
			continue
		for i in range(AudioServer.get_bus_effect_count(bus) - 1, -1, -1):
			if AudioServer.get_bus_effect(bus, i) == _taps[key][1]:
				AudioServer.remove_bus_effect(bus, i)
	_taps.clear()


func _exit_tree() -> void:
	_untap()
