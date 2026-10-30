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


func _init() -> void:
	_clear_slices()


func _clear_slices() -> void:
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


func set_sample(sound: PackedVector2Array) -> void:
	frames = sound
	chop_equal()


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
	return FIRST_NOTE + pad


## What note `note` plays: [slice, semitones], the slice empty for a note no pad answers to. In
## scale mode every note plays the spread pad's slice at its own pitch, in the scale or not.
func play_of(note: int) -> Array:
	if scale_on:
		return [slices[scale_pad], note - MIDDLE_C - sample_note]
	var pad := note - FIRST_NOTE
	if pad < 0 or pad >= PADS:
		return [Vector2i.ZERO, 0]
	return [slices[pad], 0]


## A slice as a sound to play: 16-bit stereo at RATE, with the rate to play it at for `semitones`
## (AudioStreamPlayer.pitch_scale). Null for an empty slice.
func sound_of(slice: Vector2i, semitones := 0) -> Array:
	if slice.y <= slice.x or slice.y > frames.size():
		return [null, 1.0]
	var data := PackedByteArray()
	data.resize((slice.y - slice.x) * 4)
	for i in slice.y - slice.x:
		var f := frames[slice.x + i]
		data.encode_s16(i * 4, clampi(roundi(f.x * 32767.0), -32768, 32767))
		data.encode_s16(i * 4 + 2, clampi(roundi(f.y * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	stream.mix_rate = RATE
	stream.data = data
	return [stream, pow(2.0, semitones / 12.0)]


## Every pad's name in scale mode: the note it plays ("C3", "D3" ...), or "" out of it.
func pad_label(pad: int) -> String:
	if not scale_on:
		return ""
	var n := note_of(pad)
	return Harmony.SHARP_NAMES[posmod(n, 12)] + str(floori(n / 12.0) - 1)
