class_name PadBank
extends RefCounted

## The sampling station's sixteen pads (docs/sampling_station.md, slices 3 and 5): one sample, cut
## into a slice a pad, and what each pad plays.
##
## A sample is stereo frames at RATE: cut from the TV's sound exactly (`cut`), or from any 16-bit
## WAV. It is chopped by its attacks (DawKitTransients: a pad a hit, in order) or into equal
## slices, and a pad plays its slice as it is.
##
## In scale mode (2026-10-30: "the 16 pads need a scale mode btw. full scale, all modes") one pad's
## slice is spread across all sixteen, a pad a degree of the scale from the bottom left up: sixteen
## degrees is more than two octaves of a seven-note scale. The root is where the sample's own note
## (`sample_note`, C unless said) is moved to, the nearest way; the scale any of MODES. A pad is
## repitched by playing it faster or slower, so its slice and its envelope are the same, only higher.
##
## A pad played is a note: pads 36-51 (the MPC's own map) as they are, and in scale mode the note
## it sounds (`note_of`), so a take of scale-mode pads reads in the DAW as the melody it is; every
## note back in plays what it names (`play_of`).

const PADS := 16
const RATE := 48000
## The first pad's note out of scale mode (GM's kick; the MPC's pad 1).
const FIRST_NOTE := 36
## The note a scale-mode sample's own pitch is written as when nothing better is known: middle C.
const MIDDLE_C := 60
## The scales beyond Harmony's seven modes.
const MORE_SCALES := {
	"harmonic minor": [0, 2, 3, 5, 7, 8, 11], "melodic minor": [0, 2, 3, 5, 7, 9, 11],
	"major pentatonic": [0, 2, 4, 7, 9], "minor pentatonic": [0, 3, 5, 7, 10],
	"blues": [0, 3, 5, 6, 7, 10], "chromatic": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
}
## Every scale a pad can be spread over, in the order the station steps through them.
const MODES := ["major", "dorian", "phrygian", "lydian", "mixolydian", "minor", "locrian",
		"harmonic minor", "melodic minor", "major pentatonic", "minor pentatonic", "blues", "chromatic"]
## The shortest slice a pad keeps (s): attacks nearer than this are one.
const SHORTEST := 0.02

## How a pad plays (2026-11-04, "fully featured"): ONE plays its slice through, GATE only while the
## pad is held, LOOP over and over until it is struck again.
const PLAY_MODES := ["ONE", "GATE", "LOOP"]
## Choke groups: 0 is none; pads of one group cut each other off (an open hat shut by a closed one).
const CHOKES := 4
const TUNE_LIMIT := 12.0
const VOLUME_LIMIT := 1.5

## The sample, stereo at RATE.
var frames := PackedVector2Array()
## Each pad's slice: [first frame, frame after its last]; an empty pad's is [0, 0].
var slices: Array[Vector2i] = []
var scale_on := false
## The scale's root (0 = C ... 11 = B) and mode (one of MODES).
var root := 0
var mode := "major"
## Which pad's slice scale mode spreads.
var scale_pad := 0
## The note the sample sounds (0 = C ... 11 = B), from which the root is reached.
var sample_note := 0
## The note pad 1 answers to out of scale mode (FIRST_NOTE; moved by MIDI learn).
var first_note := FIRST_NOTE
## Each pad's own settings: {"vol": 0..VOLUME_LIMIT, "pan": -1..1, "tune": semitones, "rev": bool,
## "mode": index of PLAY_MODES, "choke": 0..CHOKES}.
var params: Array[Dictionary] = []
## Sounds already made, by what made them (the pad's settings, slice and pitch): stretching one
## is slow, striking it again is not.
var _made := {}
var _gen := 0
## Counts samples set, so a sample is told from the last without comparing them.
var revision := 0


func _init() -> void:
	_clear_slices()
	for i in PADS:
		params.append(default_params())


## A pad's settings at rest: volume, pan, tune, reverse, mode, choke, start and end, envelope, filter, send, lock and fit.
static func default_params() -> Dictionary:
	return {"vol": 1.0, "pan": 0.0, "tune": 0.0, "rev": false, "mode": 0, "choke": 0,
			"start": 0.0, "end": 1.0, "atk": 0.0, "rel": 0.0, "filt": 0.0, "send": 0.0, "lock": false, "fit": 0.0}


## Pad `pad`'s setting `key` moved by `by` (a bool flips, a mode or a choke steps round), kept in
## its range. Returns the new value.
func nudge(pad: int, key: String, by: float) -> Variant:
	if pad < 0 or pad >= PADS:
		return null
	var p := params[pad]
	match key:
		"vol":
			p[key] = clampf(snappedf(float(p[key]) + by, 0.05), 0.0, VOLUME_LIMIT)
		"pan":
			p[key] = clampf(snappedf(float(p[key]) + by, 0.05), -1.0, 1.0)
		"tune":
			p[key] = clampf(snappedf(float(p[key]) + by, 0.05), -TUNE_LIMIT, TUNE_LIMIT)
		"rev", "lock":
			p[key] = not bool(p[key])
		"start":
			p[key] = clampf(snappedf(float(p[key]) + by, 0.01), 0.0, float(p["end"]) - 0.02)
		"end":
			p[key] = clampf(snappedf(float(p[key]) + by, 0.01), float(p["start"]) + 0.02, 1.0)
		"atk":
			p[key] = clampf(snappedf(float(p[key]) + by, 0.005), 0.0, 0.5)
		"rel":
			p[key] = clampf(snappedf(float(p[key]) + by, 0.01), 0.0, 1.0)
		"filt":
			p[key] = clampf(snappedf(float(p[key]) + by, 0.1), -1.0, 1.0)
		"send":
			p[key] = clampf(snappedf(float(p[key]) + by, 0.25), 0.0, 1.0)
		"mode":
			p[key] = posmod(int(p[key]) + int(by), PLAY_MODES.size())
		"choke":
			p[key] = posmod(int(p[key]) + int(by), CHOKES + 1)
	_made.clear()
	return p.get(key)


func clear_made() -> void:
	_made.clear()


## Pad `pad`'s setting `key` set outright.
func set_param(pad: int, key: String, value: Variant) -> void:
	if pad >= 0 and pad < PADS and params[pad].has(key):
		params[pad][key] = value
		_made.clear()


## The pad a note strikes out of scale mode (FIRST_NOTE up), or -1.
func pad_of_note(note: int) -> int:
	if scale_on:
		for i in PADS:
			if note_of(i) == note:
				return i
		return -1
	var pad := note - first_note
	return pad if pad >= 0 and pad < PADS else -1


func _clear_slices() -> void:
	_gen += 1
	_made.clear()
	slices.clear()
	for i in PADS:
		slices.append(Vector2i.ZERO)


## The span `from` to `to` (s) of a 16-bit PCM WAV stream (the TV's sound: stereo, any rate), as
## stereo frames at RATE: exact to the frame at RATE, the sound read in a straight line between its
## own samples where its rate is not RATE.
static func cut(stream: AudioStreamWAV, from: float, to: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if stream == null or stream.format != AudioStreamWAV.FORMAT_16_BITS or to <= from:
		return out
	var data := stream.data
	var channels := 2 if stream.stereo else 1
	var rate := stream.mix_rate
	var total := data.size() / (2 * channels)
	var step := float(rate) / float(RATE)
	var count := roundi((to - from) * RATE)
	out.resize(maxi(count, 0))
	var at := from * rate
	for i in count:
		var t := at + i * step
		var j := int(t)
		if j >= total - 1:
			out.resize(i)
			break
		var f := t - j
		var a := _frame(data, j, channels)
		var b := _frame(data, j + 1, channels)
		out[i] = a.lerp(b, f)
	return out


static func _frame(data: PackedByteArray, i: int, channels: int) -> Vector2:
	var at := i * 2 * channels
	var l := data.decode_s16(at) / 32768.0
	var r := data.decode_s16(at + 2) / 32768.0 if channels == 2 else l
	return Vector2(l, r)


## Replace the whole sample with `sound` and cut it into equal pad slices.
func set_sample(sound: PackedVector2Array) -> void:
	revision += 1
	_made.clear()
	frames = sound
	chop_equal()


## The sample made of `sounds` (sixteen, one a pad; an empty one is an empty pad), laid end to end,
## each pad's slice its own sound. The pads' settings stay as they are.
func assemble(sounds: Array) -> void:
	revision += 1
	_made.clear()
	var all := PackedVector2Array()
	_clear_slices()
	for i in mini(sounds.size(), PADS):
		var sound: PackedVector2Array = sounds[i]
		if sound.is_empty():
			continue
		slices[i] = Vector2i(all.size(), all.size() + sound.size())
		all.append_array(sound)
	frames = all


## Pad `pad`'s slice replaced by `sound` (its trim reset), the other pads' slices as they were.
func put(pad: int, sound: PackedVector2Array) -> void:
	if pad < 0 or pad >= PADS or sound.is_empty():
		return
	var sounds: Array = []
	for i in PADS:
		var s := slices[i]
		if i == pad:
			sounds.append(sound)
		elif s.y > s.x and s.y <= frames.size():
			sounds.append(frames.slice(s.x, s.y))
		else:
			sounds.append(PackedVector2Array())
	assemble(sounds)
	params[pad]["start"] = 0.0
	params[pad]["end"] = 1.0
	params[pad]["fit"] = 0.0


## Pad `pad`'s own slice as it is, trimmed to the pad's IN and OUT.
func slice_frames(pad: int) -> PackedVector2Array:
	if pad < 0 or pad >= PADS:
		return PackedVector2Array()
	var s := slices[pad]
	if s.y <= s.x or s.y > frames.size():
		return PackedVector2Array()
	var total := s.y - s.x
	var from := s.x + int(float(params[pad]["start"]) * total)
	var to := s.x + maxi(int(float(params[pad]["end"]) * total), int(float(params[pad]["start"]) * total) + 1)
	return frames.slice(from, mini(to, s.y))


func seconds() -> float:
	return frames.size() / float(RATE)


## Cut into `count` equal slices, a pad each from the first; the pads past them empty.
func chop_equal(count := PADS) -> void:
	_clear_slices()
	count = clampi(count, 1, PADS)
	if frames.is_empty():
		return
	for i in count:
		slices[i] = Vector2i(frames.size() * i / count, frames.size() * (i + 1) / count)


## Cut at its attacks, a pad a hit from the first, each to the next hit or the end: the first
## sixteen; a sample that starts before its first attack keeps that lead-in on no pad. None found,
## it is one slice. Returns how many pads it filled.
func chop_transients() -> int:
	_clear_slices()
	if frames.is_empty():
		return 0
	var mixed := PackedFloat32Array()
	mixed.resize(frames.size() * 2)
	for i in frames.size():
		mixed[i * 2] = frames[i].x
		mixed[i * 2 + 1] = frames[i].y
	var onsets := DawKitTransients.find(mixed, 2, RATE)
	var starts: Array[int] = []
	for t in onsets:
		var at := int(t * RATE)
		if starts.is_empty() or at - starts.back() >= int(SHORTEST * RATE):
			starts.append(at)
	# A sample cut on a hit starts loud, with no quiet before it for the finder to hear it rise out
	# of: its first frame is a hit too.
	if starts.is_empty() or (starts[0] >= int(SHORTEST * RATE) and _starts_loud()):
		starts.push_front(0)
	var used := mini(starts.size(), PADS)
	for i in used:
		var end := starts[i + 1] if i + 1 < starts.size() else frames.size()
		slices[i] = Vector2i(starts[i], end)
	return used


## Whether its first 10 ms are a quarter as loud as its loudest, or more.
func _starts_loud() -> bool:
	var peak := 0.0
	for f in frames:
		peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
	var head := 0.0
	for i in mini(RATE / 100, frames.size()):
		head = maxf(head, maxf(absf(frames[i].x), absf(frames[i].y)))
	return peak > 0.0 and head >= peak * 0.25


## The semitones the `degree`th step of `scale_name` is above its root, octaves added past its last.
static func degree_semitones(scale_name: String, degree: int) -> int:
	var steps: Array = steps_of(scale_name)
	var n := steps.size()
	return int(steps[posmod(degree, n)]) + 12 * floori(float(degree) / n)


## The semitone steps of scale `scale_name` (a mode alias is resolved); major if unknown.
static func steps_of(scale_name: String) -> Array:
	if Harmony.SCALES.has(scale_name):
		return Harmony.SCALES[scale_name]
	return MORE_SCALES.get(Harmony.MODE_ALIASES.get(scale_name, scale_name), Harmony.SCALES["major"])


## The semitones from the sample's own note to the root, the nearer way (−6 to +5).
func root_shift() -> int:
	return wrapi(root - sample_note, -6, 6)


## The semitones pad `pad` is played at, from its slice as sampled: 0 out of scale mode.
func pad_semitones(pad: int) -> int:
	if not scale_on:
		return 0
	return root_shift() + degree_semitones(mode, pad)


## The slice pad `pad` plays (scale mode: the spread pad's, on every pad).
func slice_of(pad: int) -> Vector2i:
	if pad < 0 or pad >= PADS:
		return Vector2i.ZERO
	return slices[scale_pad if scale_on else pad]


## The note a press of pad `pad` is recorded as.
func note_of(pad: int) -> int:
	if scale_on:
		return MIDDLE_C + sample_note + pad_semitones(pad)
	return first_note + pad


## What note `note` plays: [slice, semitones], the slice empty for a note no pad answers to. In
## scale mode every note plays the spread pad's slice at its own pitch, in the scale or not.
func play_of(note: int) -> Array:
	if scale_on:
		return [slices[scale_pad], note - MIDDLE_C - sample_note]
	var pad := note - first_note
	if pad < 0 or pad >= PADS:
		return [Vector2i.ZERO, 0]
	return [slices[pad], 0]


## A slice as a sound to play: 16-bit stereo at RATE, with the rate to play it at for `semitones`
## (AudioStreamPlayer.pitch_scale). Null for an empty slice.
## With `pad` (0..15) the pad's own settings apply too: trim, direction, filter, envelope, volume,
## pan, tune, loop, and key-lock (the pitch changes and the length does not: the slice is stretched
## by the rate it will be played at). Without, the slice as sampled.
func sound_of(slice: Vector2i, semitones := 0, pad := -1) -> Array:
	if slice.y <= slice.x or slice.y > frames.size():
		return [null, 1.0]
	var own := params[pad] if pad >= 0 and pad < PADS else default_params()
	var rate := pow(2.0, (semitones + float(own["tune"])) / 12.0)
	var key := "%s|%s|%d|%d|%d" % [var_to_str(own), slice, frames.size(), semitones, _gen]
	if pad >= 0 and _made.has(key):
		return [_made[key], rate]
	var total := slice.y - slice.x
	var from := slice.x + int(float(own["start"]) * total)
	var to := slice.x + maxi(int(float(own["end"]) * total), int(float(own["start"]) * total) + 1)
	var n := to - from
	var src := PackedVector2Array()
	src.resize(n)
	var rev := bool(own["rev"])
	for i in n:
		src[i] = frames[from + (n - 1 - i if rev else i)]
	if float(own["filt"]) != 0.0:
		_filter(src, float(own["filt"]))
	if float(own["fit"]) > 0.0 and n > 0:
		# FIT: the slice stretched (pitch kept) to the length the player set, a beat's fraction at the tempo.
		src = stretch(src, float(own["fit"]) * RATE / n)
		n = src.size()
	if bool(own["lock"]) and absf(rate - 1.0) > 0.001:
		src = stretch(src, rate)
		n = src.size()
	var atk := mini(int(float(own["atk"]) * RATE * rate), n)
	var rel := mini(int(float(own["rel"]) * RATE * rate), n)
	var pan := float(own["pan"])
	# Equal-power pan: both sides full at the centre.
	var left := minf(1.0, 1.0 - pan) * float(own["vol"])
	var right := minf(1.0, 1.0 + pan) * float(own["vol"])
	var data := PackedByteArray()
	data.resize(n * 4)
	for i in n:
		var g := 1.0
		if i < atk:
			g = float(i) / atk
		if rel > 0 and i >= n - rel:
			g *= float(n - 1 - i) / rel
		var f := src[i] * g
		data.encode_s16(i * 4, clampi(roundi(f.x * left * 32767.0), -32768, 32767))
		data.encode_s16(i * 4 + 2, clampi(roundi(f.y * right * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	stream.mix_rate = RATE
	stream.data = data
	if int(own["mode"]) == 2:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = n
	if pad >= 0:
		_made[key] = stream
	return [stream, rate]


## A state-variable filter over `s`, in place: `amount` below 0 is a low pass closing from 18 kHz
## to 200 Hz, above 0 a high pass opening from 20 Hz to 4 kHz.
static func _filter(s: PackedVector2Array, amount: float) -> void:
	var cutoff := 18000.0 * pow(200.0 / 18000.0, -amount) if amount < 0.0 else 20.0 * pow(200.0, amount)
	var f := 2.0 * sin(PI * minf(cutoff, RATE * 0.45) / RATE)
	var q := 0.8
	var low := Vector2.ZERO
	var band := Vector2.ZERO
	for i in s.size():
		low += band * f
		var high := s[i] - low - band * q
		band += high * f
		s[i] = low if amount < 0.0 else high


## `s` made `factor` times longer without changing its pitch: overlapped Hann grains read from
## slower (or faster) along the source than they are laid down.
static func stretch(s: PackedVector2Array, factor: float) -> PackedVector2Array:
	var n := s.size()
	var out_n := maxi(int(n * factor), 1)
	var out := PackedVector2Array()
	out.resize(out_n)
	if n < 256:
		for i in out_n:
			out[i] = s[mini(int(i / factor), n - 1)]
		return out
	var grain := mini(1024, n)
	var hop := grain / 4
	var weight := PackedFloat32Array()
	weight.resize(out_n)
	var window := PackedFloat32Array()
	window.resize(grain)
	for i in grain:
		window[i] = 0.5 - 0.5 * cos(TAU * (i + 0.5) / grain)
	var at := 0
	while at < out_n:
		var read := clampi(int(at / factor), 0, maxi(n - grain, 0))
		for i in mini(grain, out_n - at):
			var w := window[i]
			out[at + i] += s[read + i] * w
			weight[at + i] += w
		at += hop
	for i in out_n:
		if weight[i] > 0.0001:
			out[i] /= weight[i]
	return out


## Every pad's name in scale mode: the note it plays ("C3", "D3" ...), or "" out of it.
func pad_label(pad: int) -> String:
	if not scale_on:
		return ""
	var n := note_of(pad)
	return Harmony.SHARP_NAMES[posmod(n, 12)] + str(floori(n / 12.0) - 1)
