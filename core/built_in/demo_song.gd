class_name DemoSong
extends RefCounted

## The built-in engine's demo song: one four-bar loop per instrument, synthesised, in the song's
## time signature: a bar of 3/4 is a waltz's, one of 6/8 two dotted beats, an odd one in groups of
## two and three; 4/4 is the song as written.
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
const VERSION := 4
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


const FOUR_FOUR := Vector2i(4, 4)


## Beats (quarter notes) in a bar of `sig`, numerator and denominator.
static func bar_beats(sig: Vector2i) -> float:
	return sig.x * 4.0 / sig.y


static func loop_seconds(tempo: float, sig := FOUR_FOUR) -> float:
	return BARS * bar_beats(sig) * 60.0 / tempo


static func cache_path(role: String, tempo: float, sig := FOUR_FOUR) -> String:
	var meter := "" if sig == FOUR_FOUR else "_%dx%d" % [sig.x, sig.y]
	return "%s/%s_%d%s_v%d.wav" % [CACHE_DIR, role, roundi(tempo * 10.0), meter, VERSION]


## A finished part as a looping stream. From the cache when it is there.
static func cached(role: String, tempo: float, sig := FOUR_FOUR) -> AudioStreamWAV:
	var path := cache_path(role, tempo, sig)
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


static func save(role: String, tempo: float, wav: AudioStreamWAV, sig := FOUR_FOUR) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	wav.save_to_wav(cache_path(role, tempo, sig))


## Renders every part not already cached, on the worker pool, and calls `done(role, stream)` on
## the main thread for each as it is ready. Returns how many renders were started.
static func render_async(roles: Array, tempo: float, done: Callable, sig := FOUR_FOUR) -> int:
	var started := 0
	for role in roles:
		var have := cached(role, tempo, sig)
		if have != null:
			done.call(role, have)
			continue
		started += 1
		WorkerThreadPool.add_task(func():
			var samples := render(role, tempo, sig)
			(func():
				var wav := to_stream(samples)
				save(role, tempo, wav, sig)
				# Whoever asked may have gone while it rendered.
				if done.is_valid():
					done.call(role, wav)).call_deferred())
	return started


static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## One part, as mono samples at RATE, exactly BARS bars of `sig` long so it loops seamlessly.
## Anything still sounding at the end is wrapped round to the start, which is what makes a release
## tail or a reverb-ish decay at the loop point not click.
static func render(role: String, tempo: float, sig := FOUR_FOUR) -> PackedFloat32Array:
	var beat := 60.0 / tempo
	var out := PackedFloat32Array()
	out.resize(int(round(loop_seconds(tempo, sig) * RATE)))
	var length := bar_beats(sig)
	var bars: Array = []
	for k in BARS:
		bars.append([k * length, length, sig, k])
	_play(role, out, bars, func(b: float) -> float: return b * beat, -INF, INF)
	_normalise(out, 0.8)
	return out


## Bars a window of a part holds, and how many beats before its first loop are only there for
## what still rings into it.
const WINDOW_BARS := 2 * BARS
const WINDOW_LEAD_BEATS := 4.0


## A stretch of a part through a tempo map (DawKitTempoMap's points) and a meter (DawKitMeter's;
## empty for 4/4 throughout), from loop `loop` of the song, a loop being BARS bars: from
## WINDOW_LEAD_BEATS before that loop's first bar to WINDOW_BARS bars after it. Every note is
## where the map puts its beat and as long as the map makes its beats, so a ramp is a ramp, and
## every bar is played in its own signature. Nothing wraps: a window is played once, from its
## start, and the next takes over. Returns [samples, seconds into the song of its first sample].
## Its level is the looped part's, so a window and a loop at one tempo sound the same.
static func render_window(role: String, map_points: Array, loop: int, meter_points: Array = []) -> Array:
	var map := DawKitTempoMap.from_array(map_points)
	var meter := DawKitMeter.from_array(meter_points)
	var from_beat := meter.beat_of_bar(loop * BARS) - WINDOW_LEAD_BEATS
	var to_beat := meter.beat_of_bar(loop * BARS + WINDOW_BARS)
	var from_s := map.seconds_at(from_beat)
	var out := PackedFloat32Array()
	out.resize(int(round((map.seconds_at(to_beat) - from_s) * RATE)))
	var bars: Array = []
	for k in range(floori(meter.bar_at(from_beat)), loop * BARS + WINDOW_BARS):
		var start := meter.beat_of_bar(k)
		bars.append([start, meter.beat_of_bar(k + 1) - start, meter.signature_at(start), k])
	_play(role, out, bars, func(b: float) -> float: return map.seconds_at(b) - from_s, from_beat, to_beat)
	_scale(out, _level_of(role, map.points[0][1], meter.signature_at(0.0)))
	return [out, from_s]


## What `render` scales a part by to bring it to its level: the same number for the same part at
## a tempo, so a window can be brought to the loop's.
static func _level_of(role: String, tempo: float, sig := FOUR_FOUR) -> float:
	var beat := 60.0 / tempo
	var out := PackedFloat32Array()
	out.resize(int(round(loop_seconds(tempo, sig) * RATE)))
	var length := bar_beats(sig)
	var bars: Array = []
	for k in BARS:
		bars.append([k * length, length, sig, k])
	_play(role, out, bars, func(b: float) -> float: return b * beat, -INF, INF)
	var top := 0.0
	for v in out:
		top = maxf(top, absf(v))
	return 0.8 / top if top > 0.0 else 1.0


static func _scale(out: PackedFloat32Array, by: float) -> void:
	for i in out.size():
		out[i] *= by


## Where a bar of `sig` is felt, in beats from its start: every count in x/4; every third count
## in a compound x/8 (6/8, 9/8, 12/8); otherwise counts in twos with a three at the end (7/8 is
## 2+2+3).
static func pulses(sig: Vector2i) -> Array:
	var count := 4.0 / sig.y
	var out: Array = []
	if sig.y <= 4:
		for c in sig.x:
			out.append(c * count)
	elif sig.x % 3 == 0 and sig.x > 3:
		for c in range(0, sig.x, 3):
			out.append(c * count)
	else:
		var c := 0
		while c < sig.x:
			out.append(c * count)
			c += 3 if sig.x - c == 3 else 2
	return out


## A part's notes into `out`, bar by bar. `bars` are [beat it starts at, its beats (fewer than its
## signature's where a change cuts it short), its signature, its number in the song]; `at` puts a
## beat in `out`, in seconds, and only notes from beat `from` up to `to` sound. A bar's chord,
## and whether it ends the loop, are by its number, so a window and the loop agree.
static func _play(role: String, out: PackedFloat32Array, bars: Array, at: Callable, from: float, to: float) -> void:
	var rng := RandomNumberGenerator.new()
	for bar in bars:
		var start: float = bar[0]
		var length: float = bar[1]
		var sig: Vector2i = bar[2]
		var k := posmod(int(bar[3]), BARS)
		# Every note draws its noise from the one generator in the same order, wherever the
		# window is.
		rng.seed = hash([role, k])
		_play_bar(role, out, rng, start, length, sig, k, at, from, to)


static func _play_bar(role: String, out: PackedFloat32Array, rng: RandomNumberGenerator, start: float,
		length: float, sig: Vector2i, k: int, at: Callable, from: float, to: float) -> void:
	var whole := bar_beats(sig)
	var four := sig == FOUR_FOUR
	var last := k == BARS - 1
	var p := pulses(sig)
	var n := p.size()
	var count := 4.0 / sig.y
	# A beat of the bar, in the song; and whether a note there sounds: inside the bar as cut, and
	# inside what is being rendered.
	var on := func(b: float) -> bool: return b < length - 0.000001 and start + b >= from and start + b < to
	var t := func(b: float) -> float: return float(at.call(start + b))
	var span := func(b: float, beats: float) -> float: return float(at.call(start + b + beats)) - float(at.call(start + b))
	match role:
		"kick":
			var hits: Array = [0.0, 2.5] if four else [0.0]
			if not four and n >= 4:
				hits.append(p[n / 2])
			if last:
				var pickup := 3.5 if four else whole - count
				if pickup > hits.back():
					hits.append(pickup)
			for b in hits:
				if on.call(b):
					_kick(out, t.call(b), 1.0 if b == 0.0 else 0.8)
		"snare":
			var hits: Array = [1.0, 3.0]
			if not four:
				hits = []
				for i in range(1, n):
					if n == 3 or i % 2 == 1:
						hits.append(p[i])
			for b in hits:
				_snare(out, t.call(b), rng, 0.9, on.call(b))
			if last:
				_snare(out, t.call(whole - 0.25), rng, 0.35, on.call(whole - 0.25))
		"hat":
			for step in floori(whole * 2.0 + 0.000001):
				_hat(out, t.call(step * 0.5), rng, 0.55 if step % 2 == 1 else 0.3, 0.035, on.call(step * 0.5))
		"overheads":
			if k == 0:
				_hat(out, t.call(0.0), rng, 0.5, 1.4, on.call(0.0))
			for c in sig.x:
				_hat(out, t.call(c * count), rng, 0.12, 0.09, on.call(c * count))
		"bass":
			var root: int = ROOTS[k]
			var specs: Array = [[0.0, 1.4, 0], [1.5, 0.45, 0], [2.0, 0.9, 12], [3.0, 0.9, 7]]
			if not four:
				specs = []
				for i in n:
					var next: float = p[i + 1] if i + 1 < n else whole
					specs.append([p[i], (next - p[i]) * 0.9, [0, 12, 7][i % 3]])
			for spec in specs:
				if on.call(spec[0]):
					_bass(out, t.call(spec[0]), span.call(spec[0], spec[1]), midi_hz(root + spec[2]))
		"rhodes":
			var specs: Array = [[0.0, 2.4], [2.5, 1.5]]
			if not four:
				var half: float = p[ceili(n / 2.0)] if n >= 2 else whole
				specs = [[0.0, half * 0.95]]
				if half < whole:
					specs.append([half, (whole - half) * 0.95])
			for spec in specs:
				if on.call(spec[0]):
					for note in CHORDS[k]:
						_rhodes(out, t.call(spec[0]), span.call(spec[0], spec[1]), midi_hz(note), 0.22)
		"guitar":
			var root: int = ROOTS[k] + 12
			for step in floori(whole * 2.0 + 0.000001):
				var b := step * 0.5
				if on.call(b):
					# Hard on every other pulse: beats 1 and 3 of 4/4, the bar's top in 6/8.
					var at_pulse := p.find(b)
					var accent := 1.0 if at_pulse >= 0 and at_pulse % 2 == 0 else 0.55
					_guitar(out, t.call(b), span.call(b, 0.42),
							[midi_hz(root), midi_hz(root + 7), midi_hz(root + 12)], accent)
		"voice", "double":
			# The tune is written in 4/4; in another signature each bar's phrase fills its bar.
			var stretch := whole / 4.0
			for m in MELODY:
				if int(float(m[0]) / 4.0) != k:
					continue
				var b: float = (float(m[0]) - k * 4.0) * stretch
				if not on.call(b):
					continue
				var note: float = m[2]
				if role == "double":
					note = _third_above(int(m[2])) + 0.08
				_voice(out, t.call(b), span.call(b, float(m[1]) * stretch), midi_hz(note),
						0.5 if role == "voice" else 0.32)
		"strings":
			if on.call(0.0):
				for note in CHORDS[k]:
					_pad(out, t.call(0.0), span.call(0.0, whole), midi_hz(note + 12), 0.1)


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
