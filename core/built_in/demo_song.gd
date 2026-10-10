class_name DemoSong
extends RefCounted

## The built-in engine's demo song: one four-bar loop per instrument, synthesised.
##
## It exists so the built-in DAW makes music the moment it opens, with no files to find and no
## licence to check. Every part is rendered here from a handful of formulas -- a kick is a sine
## falling in pitch, a Rhodes is two-operator FM, a voice is a stack of harmonics shaped by
## vowel formants -- because a synthesised demo that sounds like a band is a better first
## impression than any amount of explaining that you could load your own.
##
## The parts follow the stand-in's track names (Kick, Snare, Bass DI, Lead Vox...), so the
## timeline's arrangement -- who plays in which section -- is the song's arrangement too.
##
## Rendered once per tempo, on worker threads, and cached under user://, because GDScript is
## not fast at this and a first launch that stalls for ten seconds would be worse than a
## silent one. See `render_async`.

const RATE := 32000
const BARS := 4
## Bump to throw away every cached render. Change it whenever a part's sound changes, or the
## cache will go on playing the old one.
const VERSION := 3
const CACHE_DIR := "user://built_in"

## A minor: Am | F | C | G. MIDI note numbers.
const CHORDS := [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]
const ROOTS := [33, 29, 36, 31]
## [beat, length in beats, MIDI note]. Four bars, one per chord.
const MELODY := [
	[0.0, 1.0, 64], [1.0, 0.5, 62], [1.5, 0.5, 60], [2.0, 2.0, 64],
	[4.0, 1.0, 65], [5.0, 1.0, 64], [6.0, 2.0, 60],
	[8.0, 1.0, 67], [9.0, 1.0, 64], [10.0, 1.0, 62], [11.0, 1.0, 60],
	[12.0, 3.0, 62], [15.0, 1.0, 59],
]
const SCALE := [57, 59, 60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79]

## Which part a track plays, from its name. Extra tracks in a padded session are named
## "Kick 2" and so on, so a prefix match gives them their role's part too.
const ROLES := {
	"kick": "kick", "snare": "snare", "hat": "hat", "oh": "overheads", "bass": "bass",
	"rhodes": "rhodes", "gtr": "guitar", "lead vox": "voice", "vox dbl": "double",
	"strings": "strings",
}


static func role_of(track_name: String) -> String:
	var n := track_name.to_lower()
	for prefix in ROLES:
		if n.begins_with(prefix):
			return ROLES[prefix]
	return ""


static func loop_seconds(tempo: float) -> float:
	return BARS * 4.0 * 60.0 / tempo


static func cache_path(role: String, tempo: float) -> String:
	return "%s/%s_%d_v%d.wav" % [CACHE_DIR, role, roundi(tempo * 10.0), VERSION]


## A finished part as a looping stream. From the cache when it is there.
static func cached(role: String, tempo: float) -> AudioStreamWAV:
	var path := cache_path(role, tempo)
	if FileAccess.file_exists(path):
		var wav := AudioStreamWAV.load_from_file(path)
		if wav != null:
			_loop(wav)
			return wav
	return null


static func to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	return stream_of(encode(samples))


## Samples as the 16-bit data a stream holds: the slow part, for a worker thread.
static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return data


## A looping part's stream around its data.
static func stream_of(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	_loop(wav)
	return wav


static func _loop(wav: AudioStreamWAV) -> void:
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = wav.data.size() / 2


static func save(role: String, tempo: float, wav: AudioStreamWAV) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	wav.save_to_wav(cache_path(role, tempo))


## Renders every part not already cached, on the worker pool, and calls `done(role, stream)` on
## the main thread for each as it is ready. Returns how many renders were started.
static func render_async(roles: Array, tempo: float, done: Callable) -> int:
	var started := 0
	for role in roles:
		var have := cached(role, tempo)
		if have != null:
			done.call(role, have)
			continue
		started += 1
		WorkerThreadPool.add_task(func():
			var samples := render(role, tempo)
			(func():
				var wav := to_stream(samples)
				save(role, tempo, wav)
				done.call(role, wav)).call_deferred())
	return started


static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## One part, as mono samples at RATE, exactly BARS bars long so it loops seamlessly. Anything
## still sounding at the end is wrapped round to the start, which is what makes a release tail
## or a reverb-ish decay at the loop point not click.
static func render(role: String, tempo: float) -> PackedFloat32Array:
	var beat := 60.0 / tempo
	var out := PackedFloat32Array()
	out.resize(int(round(loop_seconds(tempo) * RATE)))
	_play(role, out, func(b: float) -> float: return b * beat, -INF, INF)
	_normalise(out, 0.8)
	return out


## Beats a window of a part holds, and how many of them before its first loop are only there for
## what still rings into it.
const WINDOW_BEATS := 2 * BARS * 4
const WINDOW_LEAD_BEATS := 4.0


## A stretch of a part through a tempo map (DawKitTempoMap's points), from loop `loop` of the
## song: WINDOW_LEAD_BEATS before that loop's first beat to WINDOW_BEATS after it. Every note is
## where the map puts its beat and as long as the map makes its beats, so a ramp is a ramp.
## Nothing wraps: a window is played once, from its start, and the next takes over. Returns
## [samples, seconds into the song of its first sample]. Its level is the looped part's, so a
## window and a loop at one tempo sound the same.
static func render_window(role: String, map_points: Array, loop: int) -> Array:
	var map := DawKitTempoMap.from_array(map_points)
	var loop_beats := float(BARS * 4)
	var from_beat := loop * loop_beats - WINDOW_LEAD_BEATS
	var to_beat := loop * loop_beats + WINDOW_BEATS
	var from_s := map.seconds_at(from_beat)
	var out := PackedFloat32Array()
	out.resize(int(round((map.seconds_at(to_beat) - from_s) * RATE)))
	var first := floori(from_beat / loop_beats)
	for l in range(first, ceili(to_beat / loop_beats)):
		var origin := l * loop_beats
		_play(role, out, func(b: float) -> float: return map.seconds_at(origin + b) - from_s,
				from_beat - origin, to_beat - origin)
	_scale(out, _level_of(role, map.points[0][1]))
	return [out, from_s]


## What `render` scales a part by to bring it to its level: the same number for the same part at
## a tempo, so a window can be brought to the loop's.
static func _level_of(role: String, tempo: float) -> float:
	var beat := 60.0 / tempo
	var out := PackedFloat32Array()
	out.resize(int(round(loop_seconds(tempo) * RATE)))
	_play(role, out, func(b: float) -> float: return b * beat, -INF, INF)
	var top := 0.0
	for v in out:
		top = maxf(top, absf(v))
	return 0.8 / top if top > 0.0 else 1.0


static func _scale(out: PackedFloat32Array, by: float) -> void:
	for i in out.size():
		out[i] *= by


## A part's notes into `out`, each where `at` puts its beat in the loop (0 to BARS * 4), and as
## long as `at` makes its beats; only notes from beat `from` up to `to` of the loop.
static func _play(role: String, out: PackedFloat32Array, at: Callable, from: float, to: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(role)
	# Every note draws its noise from the one generator in the same order, wherever the window is.
	var span := func(b: float, beats: float) -> float: return float(at.call(b + beats)) - float(at.call(b))
	var on := func(b: float) -> bool: return b >= from and b < to
	match role:
		"kick":
			for bar in BARS:
				var hits := [0.0, 2.5] if bar < BARS - 1 else [0.0, 2.5, 3.5]
				for b in hits:
					if on.call(bar * 4 + b):
						_kick(out, at.call(bar * 4 + b), 1.0 if b == 0.0 else 0.8)
		"snare":
			for bar in BARS:
				for b in [1.0, 3.0]:
					_snare(out, at.call(bar * 4 + b), rng, 0.9, on.call(bar * 4 + b))
				if bar == BARS - 1:
					_snare(out, at.call(bar * 4 + 3.75), rng, 0.35, on.call(bar * 4 + 3.75))
		"hat":
			for step in BARS * 8:
				_hat(out, at.call(step * 0.5), rng, 0.55 if step % 2 == 1 else 0.3, 0.035, on.call(step * 0.5))
		"overheads":
			_hat(out, at.call(0.0), rng, 0.5, 1.4, on.call(0.0))
			for b in BARS * 4:
				_hat(out, at.call(float(b)), rng, 0.12, 0.09, on.call(float(b)))
		"bass":
			for bar in BARS:
				var root: int = ROOTS[bar]
				for spec in [[0.0, 1.4, 0], [1.5, 0.45, 0], [2.0, 0.9, 12], [3.0, 0.9, 7]]:
					var b: float = bar * 4 + spec[0]
					if on.call(b):
						_bass(out, at.call(b), span.call(b, spec[1]), midi_hz(root + spec[2]))
		"rhodes":
			for bar in BARS:
				for spec in [[0.0, 2.4], [2.5, 1.5]]:
					var b: float = bar * 4 + spec[0]
					if on.call(b):
						for note in CHORDS[bar]:
							_rhodes(out, at.call(b), span.call(b, spec[1]), midi_hz(note), 0.22)
		"guitar":
			for bar in BARS:
				var root: int = ROOTS[bar] + 12
				for step in 8:
					var b: float = bar * 4 + step * 0.5
					if on.call(b):
						var accent := 1.0 if step % 4 == 0 else 0.55
						_guitar(out, at.call(b), span.call(b, 0.42),
								[midi_hz(root), midi_hz(root + 7), midi_hz(root + 12)], accent)
		"voice", "double":
			for n in MELODY:
				if not on.call(float(n[0])):
					continue
				var note: float = n[2]
				if role == "double":
					note = _third_above(int(n[2])) + 0.08
				_voice(out, at.call(float(n[0])), span.call(float(n[0]), float(n[1])), midi_hz(note),
						0.5 if role == "voice" else 0.32)
		"strings":
			for bar in BARS:
				if on.call(float(bar * 4)):
					for note in CHORDS[bar]:
						_pad(out, at.call(float(bar * 4)), span.call(float(bar * 4), 4.0), midi_hz(note + 12), 0.1)


static func _third_above(note: int) -> int:
	var i := SCALE.find(note)
	return SCALE[i + 2] if i >= 0 and i + 2 < SCALE.size() else note + 4


## Adds `value` at sample `i`, wrapping round the loop. A window's tail past its end lands in its
## lead, which is never played.
static func _add(out: PackedFloat32Array, i: int, value: float) -> void:
	var n := out.size()
	out[posmod(i, n)] += value


static func _kick(out: PackedFloat32Array, at: float, gain: float) -> void:
	var start := int(at * RATE)
	var phase := 0.0
	for i in int(0.45 * RATE):
		var t := float(i) / RATE
		phase += TAU * (46.0 + 90.0 * exp(-t * 30.0)) / RATE
		var click := exp(-t * 400.0) * 0.4
		_add(out, start + i, gain * (sin(phase) * exp(-t * 6.5) + click))


static func _snare(out: PackedFloat32Array, at: float, rng: RandomNumberGenerator, gain: float, sound := true) -> void:
	var start := int(at * RATE)
	var prev := 0.0
	for i in int(0.3 * RATE):
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		var bright := noise - prev * 0.6
		prev = noise
		var body := sin(TAU * 185.0 * t) * exp(-t * 30.0) * 0.6
		if sound:
			_add(out, start + i, gain * (bright * exp(-t * 16.0) * 0.55 + body))


static func _hat(out: PackedFloat32Array, at: float, rng: RandomNumberGenerator, gain: float, decay: float, sound := true) -> void:
	var start := int(at * RATE)
	var a := 0.0
	var b := 0.0
	for i in int(decay * 5.0 * RATE):
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		# Two differences: a crude high-pass that leaves the sizzle and drops the hiss's body.
		var hp := noise - 2.0 * a + b
		b = a
		a = noise
		if sound:
			_add(out, start + i, gain * hp * 0.25 * exp(-t / decay))


static func _bass(out: PackedFloat32Array, at: float, length: float, hz: float) -> void:
	var start := int(at * RATE)
	var lp := 0.0
	var cut := 1.0 - exp(-TAU * 420.0 / RATE)
	for i in int((length + 0.06) * RATE):
		var t := float(i) / RATE
		var saw := 2.0 * fmod(hz * t, 1.0) - 1.0
		lp += cut * (saw - lp)
		var env := minf(t / 0.004, 1.0) * (0.75 + 0.25 * exp(-t * 8.0))
		if t > length:
			env *= exp(-(t - length) * 60.0)
		_add(out, start + i, env * (lp * 0.7 + sin(TAU * hz * t) * 0.6))


static func _rhodes(out: PackedFloat32Array, at: float, length: float, hz: float, gain: float) -> void:
	var start := int(at * RATE)
	for i in int((length + 0.3) * RATE):
		var t := float(i) / RATE
		var index := 1.4 * exp(-t * 4.0) + 0.2
		var tone := sin(TAU * hz * t + index * sin(TAU * hz * t))
		var tremolo := 1.0 + 0.18 * sin(TAU * 4.6 * t)
		var env := minf(t / 0.003, 1.0) * exp(-t * 0.9)
		if t > length:
			env *= exp(-(t - length) * 14.0)
		_add(out, start + i, gain * tone * env * tremolo)


static func _guitar(out: PackedFloat32Array, at: float, length: float, freqs: Array, gain: float) -> void:
	var start := int(at * RATE)
	var lp := 0.0
	var cut := 1.0 - exp(-TAU * 1800.0 / RATE)
	for i in int((length + 0.03) * RATE):
		var t := float(i) / RATE
		var sum := 0.0
		for f in freqs:
			sum += 2.0 * fmod(f * t * 1.0008, 1.0) - 1.0
		var driven := tanh(sum * 2.2)
		lp += cut * (driven - lp)
		var env := minf(t / 0.002, 1.0) * exp(-t * 5.0)
		if t > length:
			env *= exp(-(t - length) * 80.0)
		_add(out, start + i, gain * 0.35 * lp * env)


## A sung "ah": harmonics of the note weighted by how close each lands to the vowel's formants,
## with vibrato that arrives after the onset, the way a singer's does.
static func _voice(out: PackedFloat32Array, at: float, length: float, hz: float, gain: float) -> void:
	var start := int(at * RATE)
	var formants := [[730.0, 1.0, 90.0], [1090.0, 0.55, 110.0], [2440.0, 0.25, 160.0]]
	var harmonics := 14
	var weights := PackedFloat32Array()
	weights.resize(harmonics)
	for k in harmonics:
		var f := hz * (k + 1)
		var w := 0.04
		for fm in formants:
			w += fm[1] * exp(-pow((f - fm[0]) / (fm[2] * 2.0), 2.0))
		weights[k] = w / sqrt(k + 1.0)
	var phase := 0.0
	for i in int((length + 0.12) * RATE):
		var t := float(i) / RATE
		var vib := 1.0 + 0.006 * sin(TAU * 5.4 * t) * clampf((t - 0.18) / 0.3, 0.0, 1.0)
		phase += TAU * hz * vib / RATE
		var sum := 0.0
		for k in harmonics:
			if hz * (k + 1) > RATE * 0.45:
				break
			sum += weights[k] * sin(phase * (k + 1))
		var env := minf(t / 0.06, 1.0)
		if t > length:
			env *= exp(-(t - length) * 30.0)
		_add(out, start + i, gain * 0.35 * sum * env)


static func _pad(out: PackedFloat32Array, at: float, length: float, hz: float, gain: float) -> void:
	var start := int(at * RATE)
	var lp := 0.0
	var cut := 1.0 - exp(-TAU * 2200.0 / RATE)
	for i in int((length + 0.5) * RATE):
		var t := float(i) / RATE
		var sum := 0.0
		for detune in [0.996, 1.0, 1.005]:
			sum += 2.0 * fmod(hz * detune * t, 1.0) - 1.0
		lp += cut * (sum - lp)
		var env := minf(t / 0.45, 1.0)
		if t > length:
			env *= exp(-(t - length) * 6.0)
		_add(out, start + i, gain * lp * env)


static func _normalise(out: PackedFloat32Array, peak: float) -> void:
	var top := 0.0
	for v in out:
		top = maxf(top, absf(v))
	if top <= 0.0:
		return
	var k := peak / top
	for i in out.size():
		out[i] *= k
