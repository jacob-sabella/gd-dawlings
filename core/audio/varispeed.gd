class_name Varispeed
extends Node

## A sound read at whatever speed and direction a hand moves it (docs/spatial_loop.md part two,
## slice 27): the DJ platter's scratch. What it reads is a clip's render (`frames`, stereo, at its
## own `rate`), and where it reads is told it each frame (`follow`): the seconds into the clip the
## platter's angle says. Between one frame's place and the next it reads in a straight line, so it
## plays the clip at exactly the speed the hand turned it, forwards or backwards, and it is as loud
## as it is fast (GAIN_SPEED): a record held still is silent, not a held sample.
##
## It is heard by this player alone, on the keys' bus (AudioPorts.MONITOR), through Godot's mixer:
## a texture one player makes, said on its tag at its figure (`latency_seconds`), never the mix and
## never the DAW (docs/spatial_loop.md part two, "What is personal stays in your ears").
##
## What it plays is `read`, the one arithmetic for both the live sound and the whole of a scratch
## rendered after it (`render`, from its `path`), so what the sampler keeps is what was heard.

## The rate it plays and renders at: Foley's, the sampler's.
const RATE := Foley.RATE
## How much is queued ahead of the card (s): the scratch's own lateness, before the card's.
const BUFFER := 0.05
## A read this fast (clip seconds a second) or faster is at full level; slower is quieter in
## proportion, and still is silent.
const GAIN_SPEED := 0.25
## The bus it plays on: the keys', what a personal mix calls this player's own.
const BUS := AudioPorts.MONITOR
## A path keeps this many steps at most (ten seconds of frames, about), and PATH_SECONDS of time at
## most: a scratch is a gesture, and a longer one is kept to its start. And a step is this long at
## most (s) when it is rendered. A path asked of the host past either is refused (`fits`).
const PATH_MOST := 600
const PATH_SECONDS := 10.0
const STEP_MOST := 0.25

## The clip's render: stereo frames at `rate`, read round and round (the clip loops under the hand).
var frames := PackedVector2Array()
var rate := RATE
## Where in the clip it reads now (s), and how loud it is reading (the last frame's level).
var head := 0.0
var gain := 0.0
## The one player, made with it.
var player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback = null
## Every place it was told and the time between, while `recording`: [dt, seconds, dt, seconds...],
## from where it began (a step 0 long), a scratch's whole path for `render`.
var recording := false
var path := PackedFloat32Array()
## How long the path recorded so far runs (s), as `render` would have it.
var _path_seconds := 0.0


func _ready() -> void:
	AudioPorts.ensure_buses()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = RATE
	stream.buffer_length = BUFFER
	player = AudioStreamPlayer.new()
	player.name = "VarispeedPlayer"
	player.bus = BUS
	player.stream = stream
	add_child(player)


## The clip it reads from now on, from `at` seconds into it.
func use(source: PackedVector2Array, source_rate: int, at := 0.0) -> void:
	frames = source
	rate = maxi(source_rate, 1)
	head = wrapped(at)
	gain = 0.0


## Seconds of clip it has.
func length() -> float:
	return float(frames.size()) / float(rate)


## `at` seconds, round the clip's length.
func wrapped(at: float) -> float:
	var long := length()
	return fposmod(at, long) if long > 0.0 else 0.0


## Started: the player going, ready for `follow`. A new path begins if `record`, from where it
## reads now (its first step, no time long).
func start(record := false) -> void:
	recording = record
	path = PackedFloat32Array([0.0, head]) if record else PackedFloat32Array()
	_path_seconds = 0.0
	gain = 0.0
	if player == null:
		return
	if not player.playing:
		player.play()
	_playback = player.get_stream_playback() as AudioStreamGeneratorPlayback


## Stopped: silent at once, its queue let go.
func stop() -> void:
	recording = false
	gain = 0.0
	if player != null and player.playing:
		player.stop()
	_playback = null


func is_playing() -> bool:
	return player != null and player.playing


## This frame (`delta` seconds long) the hand has the clip at `at` seconds: what is queued is read
## from where it last was to there. The path keeps it while recording.
func follow(at: float, delta: float) -> void:
	if frames.is_empty() or delta <= 0.0:
		return
	if recording and path.size() < PATH_MOST * 2 and _path_seconds + _step_of(delta) <= PATH_SECONDS:
		path.append(delta)
		path.append(at)
		_path_seconds += _step_of(delta)
	var count := roundi(delta * RATE)
	if _playback != null:
		# The queue topped up, BUFFER's worth at most: once it is running, what the card took since
		# the last frame, which is the frame's own length.
		count = _playback.get_frames_available()
	if count <= 0:
		head = at
		return
	var made: Array = read(frames, rate, head, at, count, gain)
	head = at
	gain = made[1]
	if _playback != null:
		_playback.push_buffer(made[0])


## The figure on its tag: how late what the hand does is heard (s), its queue and the card's.
static func latency_seconds() -> float:
	return BUFFER + AudioServer.get_output_latency()


## `count` frames at RATE of `source` (stereo, at `source_rate`, read round its length), read in a
## straight line from `from` to `to` seconds into it, at the level its speed gives (GAIN_SPEED),
## eased from `gain_from`. [the frames, the level it ended at]. Pure: the live sound and a rendered
## scratch are this.
static func read(source: PackedVector2Array, source_rate: int, from: float, to: float, count: int,
		gain_from: float) -> Array:
	var out := PackedVector2Array()
	if count <= 0 or source.is_empty():
		return [out, gain_from]
	out.resize(count)
	var long := float(source.size())
	var speed := absf(to - from) / (float(count) / float(RATE))
	var gain_to := clampf(speed / GAIN_SPEED, 0.0, 1.0)
	for i in count:
		var k := float(i + 1) / float(count)
		var at := fposmod(lerpf(from, to, k) * float(source_rate), long)
		var j := int(at)
		var next := (j + 1) % source.size()
		out[i] = source[j].lerp(source[next], at - float(j)) * lerpf(gain_from, gain_to, k)
	return [out, gain_to]


## How long a step `dt` long is rendered (s): STEP_MOST at most, and none for one that is not a time.
static func _step_of(dt: float) -> float:
	return clampf(dt, 0.0, STEP_MOST) if is_finite(dt) else 0.0


## How long `scratch` ([dt, seconds, ...]) runs rendered (s).
static func path_seconds(scratch: PackedFloat32Array) -> float:
	var long := 0.0
	for n in range(0, scratch.size() - 1, 2):
		long += _step_of(scratch[n])
	return long


## Whether `scratch` is a path the host renders when it is asked one: an even count of numbers, a
## step and a place each, PATH_MOST steps at most and PATH_SECONDS long at most. What `follow`
## records always is.
static func fits(scratch: PackedFloat32Array) -> bool:
	return scratch.size() % 2 == 0 and scratch.size() <= PATH_MOST * 2 \
			and path_seconds(scratch) <= PATH_SECONDS + 0.0001


## A whole scratch, as it was heard: `scratch` ([dt, seconds, ...], what `follow` was told while
## recording, from where it began), one frame's worth of RATE a step, mixed to mono. Its samples:
## PATH_SECONDS of them at most, however long the path.
static func render(source: PackedVector2Array, source_rate: int, scratch: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var at := scratch[1] if scratch.size() >= 2 and is_finite(scratch[1]) else 0.0
	var level := 0.0
	var long := 0.0
	for n in range(0, scratch.size() - 1, 2):
		if not is_finite(scratch[n]) or not is_finite(scratch[n + 1]):
			break
		long += _step_of(scratch[n])
		if long > PATH_SECONDS + 0.0001:
			break
		var count := roundi(_step_of(scratch[n]) * RATE)
		var made: Array = read(source, source_rate, at, scratch[n + 1], count, level)
		at = scratch[n + 1]
		level = made[1]
		for f: Vector2 in made[0]:
			out.append((f.x + f.y) * 0.5)
	return out


## Mono samples as a 16-bit mono stream at RATE, as the sampler writes one (Sampler.write).
static func wav_of(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(roundf(clampf(samples[i], -1.0, 1.0) * 32767.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## A WAV's sound as stereo frames (a mono one doubled), from `from` seconds for `seconds` (all of
## it after `from` for a negative), backwards if `reversed`: an audio clip's stretch of its file.
## Empty for a format it cannot read (only 8 and 16 bits). Safe off the main thread.
static func frames_of(wav: AudioStreamWAV, from := 0.0, seconds := -1.0, reversed := false) -> PackedVector2Array:
	var out := PackedVector2Array()
	if wav == null or wav.data.is_empty():
		return out
	var wide := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else (1 if wav.format == AudioStreamWAV.FORMAT_8_BITS else 0)
	if wide == 0:
		return out
	var channels := 2 if wav.stereo else 1
	var total := wav.data.size() / (wide * channels)
	var begin := clampi(roundi(from * wav.mix_rate), 0, total)
	var end := total if seconds < 0.0 else clampi(begin + roundi(seconds * wav.mix_rate), begin, total)
	out.resize(end - begin)
	for i in out.size():
		var at := (begin + i) * wide * channels
		var l := _sample(wav.data, at, wide)
		var r := _sample(wav.data, at + wide, wide) if channels == 2 else l
		out[i] = Vector2(l, r)
	if reversed:
		out.reverse()
	return out


static func _sample(data: PackedByteArray, at: int, wide: int) -> float:
	if wide == 2:
		return data.decode_s16(at) / 32767.0
	# Godot keeps 8-bit sound signed, whatever the file had.
	return data.decode_s8(at) / 127.0
