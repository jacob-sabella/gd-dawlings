class_name LoudnessMeter
extends RefCounted

## Loudness as ITU-R BS.1770-4 measures it (EBU R128's meter), and the two other things a master
## is checked for, from stereo frames (docs/spatial_loop.md part three, F: the LEVELS wall).
##
## K-WEIGHTING. Each channel goes through BS.1770's two filters: a high shelf (+4 dB above about
## 1.7 kHz, the head's effect) and a high-pass (RLB, about 38 Hz). Their coefficients are worked
## out for the meter's own rate from the analogue prototypes (libebur128's constants), so they are
## BS.1770's at 48 kHz and right at 44.1 kHz or anything else. Both channels weigh 1 (left and
## right); a block's loudness is −0.691 + 10·log10 of its channels' mean squares added (LUFS).
##
## THE THREE READINGS. Momentary: the last 400 ms. Short-term: the last 3 s. Integrated: since the
## last `reset`, over 400 ms blocks every 100 ms (75 % overlap), gated twice -- blocks under
## −70 LUFS are left out (silence), then those more than 10 LU under the mean of what is left --
## kept as a histogram of 0.1 LU bins (count and energy each), so an hour costs what a second does.
##
## TRUE-ISH PEAK. BS.1770's true peak is 4x oversampling through a 48-tap filter; this is 4x by a
## cubic (Catmull-Rom) through the four samples round each gap, worked only where a sample is near
## the loudest yet, so it costs little. Said "≈ dBTP": close to the real thing on music, and not
## the standard's figure.
##
## CORRELATION, −1..+1: the raw (unweighted) left and right over the last 300 ms, Σlr / √(Σl²·Σr²).
## +1 is mono, 0 unrelated, −1 one side the other's opposite: summed to mono it cancels.
##
## Pure arithmetic on what it is fed (`feed`): the built-in engine feeds it its master's capture on a
## worker thread (GodotBackend), the suite feeds it sines. Nothing here touches the scene or the
## AudioServer, so it is safe off the main thread while only one thread feeds it.

const ABSOLUTE_GATE := -70.0
const RELATIVE_GATE := -10.0
## A sub-block (s): every reading is made of these.
const SUB := 0.1
const MOMENTARY_SUBS := 4
const SHORT_SUBS := 30
const CORRELATION_SUBS := 3
## The integrated histogram: 0.1 LU bins from the absolute gate up.
const BIN := 0.1
const BINS := 1000
## Under this much energy a correlation means nothing (silence): NAN.
const QUIET := 1e-9

var rate := 48000.0
var momentary := -INF
var short_term := -INF
var integrated := -INF
## The loudest true-ish peak since `reset` (dBTP), and over the last short-term window.
var true_peak_db := -INF
var true_peak_recent_db := -INF
var correlation := NAN
## How long it has listened since `reset` (s).
var seconds := 0.0

# The two biquads' coefficients: shelf, then high-pass.
var _sb0 := 0.0
var _sb1 := 0.0
var _sb2 := 0.0
var _sa1 := 0.0
var _sa2 := 0.0
var _hb0 := 1.0
var _hb1 := -2.0
var _hb2 := 1.0
var _ha1 := 0.0
var _ha2 := 0.0
# Their state, both channels at once.
var _sx1 := Vector2.ZERO
var _sx2 := Vector2.ZERO
var _sy1 := Vector2.ZERO
var _sy2 := Vector2.ZERO
var _hy1 := Vector2.ZERO
var _hy2 := Vector2.ZERO
# The last four raw samples, for the true peak's cubic.
var _p0 := Vector2.ZERO
var _p1 := Vector2.ZERO
var _p2 := Vector2.ZERO
# The sub-block being gathered: its weighted energy, raw products and peak, and how many frames.
var _energy := 0.0
var _lr := 0.0
var _ll := 0.0
var _rr := 0.0
var _peak := 0.0
var _frames := 0
var _per_sub := 4800
# The finished sub-blocks, newest last, as rings.
var _subs := PackedFloat64Array()
var _sub_lr := PackedFloat64Array()
var _sub_ll := PackedFloat64Array()
var _sub_rr := PackedFloat64Array()
var _sub_peak := PackedFloat64Array()
var _ring := 0
var _filled := 0
# The gated blocks, by 0.1 LU bin: how many, and their energies added.
var _counts := PackedInt32Array()
var _sums := PackedFloat64Array()
var _blocks := 0
var _block_energy := 0.0


func _init(sample_rate := 48000.0) -> void:
	set_rate(sample_rate)


func set_rate(sample_rate: float) -> void:
	rate = maxf(sample_rate, 8000.0)
	# The shelf (stage 1).
	var f0 := 1681.974450955533
	var g := 3.999843853973347
	var q := 0.7071752369554196
	var k := tan(PI * f0 / rate)
	var vh := pow(10.0, g / 20.0)
	var vb := pow(vh, 0.4996667741545416)
	var a0 := 1.0 + k / q + k * k
	_sb0 = (vh + vb * k / q + k * k) / a0
	_sb1 = 2.0 * (k * k - vh) / a0
	_sb2 = (vh - vb * k / q + k * k) / a0
	_sa1 = 2.0 * (k * k - 1.0) / a0
	_sa2 = (1.0 - k / q + k * k) / a0
	# The high-pass (stage 2, RLB).
	f0 = 38.13547087602444
	q = 0.5003270373238773
	k = tan(PI * f0 / rate)
	var d := 1.0 + k / q + k * k
	_ha1 = 2.0 * (k * k - 1.0) / d
	_ha2 = (1.0 - k / q + k * k) / d
	_per_sub = maxi(1, roundi(rate * SUB))
	reset()


## Forget everything: the integrated reading, the peaks and the windows start again.
func reset() -> void:
	_sx1 = Vector2.ZERO
	_sx2 = Vector2.ZERO
	_sy1 = Vector2.ZERO
	_sy2 = Vector2.ZERO
	_hy1 = Vector2.ZERO
	_hy2 = Vector2.ZERO
	_p0 = Vector2.ZERO
	_p1 = Vector2.ZERO
	_p2 = Vector2.ZERO
	_energy = 0.0
	_lr = 0.0
	_ll = 0.0
	_rr = 0.0
	_peak = 0.0
	_frames = 0
	_subs.resize(SHORT_SUBS)
	_subs.fill(0.0)
	_sub_lr.resize(SHORT_SUBS)
	_sub_lr.fill(0.0)
	_sub_ll.resize(SHORT_SUBS)
	_sub_ll.fill(0.0)
	_sub_rr.resize(SHORT_SUBS)
	_sub_rr.fill(0.0)
	_sub_peak.resize(SHORT_SUBS)
	_sub_peak.fill(0.0)
	_ring = 0
	_filled = 0
	_counts.resize(BINS)
	_counts.fill(0)
	_sums.resize(BINS)
	_sums.fill(0.0)
	_blocks = 0
	_block_energy = 0.0
	momentary = -INF
	short_term = -INF
	integrated = -INF
	true_peak_db = -INF
	true_peak_recent_db = -INF
	correlation = NAN
	seconds = 0.0


## Loudness of a mean-square energy (both channels' added), LUFS.
static func lufs(energy: float) -> float:
	return -0.691 + 10.0 * log(energy) / log(10.0) if energy > 0.0 else -INF


## Stereo frames into the meter. The readings change at each 100 ms sub-block's end.
func feed(frames: PackedVector2Array) -> void:
	var sb0 := _sb0
	var sb1 := _sb1
	var sb2 := _sb2
	var sa1 := _sa1
	var sa2 := _sa2
	var ha1 := _ha1
	var ha2 := _ha2
	var sx1 := _sx1
	var sx2 := _sx2
	var sy1 := _sy1
	var sy2 := _sy2
	var hy1 := _hy1
	var hy2 := _hy2
	var p0 := _p0
	var p1 := _p1
	var p2 := _p2
	for x in frames:
		# Stage 1, the shelf; stage 2, the high-pass, whose input is stage 1's output.
		var s := x * sb0 + sx1 * sb1 + sx2 * sb2 - sy1 * sa1 - sy2 * sa2
		sx2 = sx1
		sx1 = x
		var h := s - sy1 * 2.0 + sy2 - hy1 * ha1 - hy2 * ha2
		sy2 = sy1
		sy1 = s
		hy2 = hy1
		hy1 = h
		_energy += h.x * h.x + h.y * h.y
		_lr += x.x * x.y
		_ll += x.x * x.x
		_rr += x.y * x.y
		# The true-ish peak: the sample, and where it is near the loudest yet, the cubic between
		# the last two samples (p1 to p2, with p0 and x the outer points).
		var m := maxf(absf(x.x), absf(x.y))
		if m > _peak:
			_peak = m
		var near := maxf(maxf(absf(p1.x), absf(p1.y)), maxf(absf(p2.x), absf(p2.y)))
		if near * 1.3 > _peak:
			var cb := (p2 - p0) * 0.5
			var cc := (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - x) * 0.5
			var cd := (p1 * 3.0 - p0 - p2 * 3.0 + x) * 0.5
			var q1 := p1 + cb * 0.25 + cc * 0.0625 + cd * 0.015625
			var q2 := p1 + cb * 0.5 + cc * 0.25 + cd * 0.125
			var q3 := p1 + cb * 0.75 + cc * 0.5625 + cd * 0.421875
			_peak = maxf(_peak, maxf(maxf(maxf(absf(q1.x), absf(q1.y)), maxf(absf(q2.x), absf(q2.y))), maxf(absf(q3.x), absf(q3.y))))
		p0 = p1
		p1 = p2
		p2 = x
		_frames += 1
		if _frames >= _per_sub:
			_end_sub()
	_sx1 = sx1
	_sx2 = sx2
	_sy1 = sy1
	_sy2 = sy2
	_hy1 = hy1
	_hy2 = hy2
	_p0 = p0
	_p1 = p1
	_p2 = p2


## A sub-block done: into the rings, and the readings made again from them.
func _end_sub() -> void:
	var n := float(_frames)
	_subs[_ring] = _energy / n
	_sub_lr[_ring] = _lr
	_sub_ll[_ring] = _ll
	_sub_rr[_ring] = _rr
	_sub_peak[_ring] = _peak
	_ring = (_ring + 1) % SHORT_SUBS
	_filled = mini(_filled + 1, SHORT_SUBS)
	seconds += n / rate
	_energy = 0.0
	_lr = 0.0
	_ll = 0.0
	_rr = 0.0
	_frames = 0
	var tp := 20.0 * log(_peak) / log(10.0) if _peak > 0.0 else -INF
	true_peak_db = maxf(true_peak_db, tp)
	_peak = 0.0
	momentary = lufs(_mean(MOMENTARY_SUBS)) if _filled >= MOMENTARY_SUBS else -INF
	short_term = lufs(_mean(SHORT_SUBS)) if _filled >= SHORT_SUBS else lufs(_mean(_filled))
	var recent := 0.0
	var lr := 0.0
	var ll := 0.0
	var rr := 0.0
	for i in _filled:
		var at := posmod(_ring - 1 - i, SHORT_SUBS)
		recent = maxf(recent, _sub_peak[at])
		if i < CORRELATION_SUBS:
			lr += _sub_lr[at]
			ll += _sub_ll[at]
			rr += _sub_rr[at]
	true_peak_recent_db = 20.0 * log(recent) / log(10.0) if recent > 0.0 else -INF
	correlation = clampf(lr / sqrt(ll * rr), -1.0, 1.0) if ll > QUIET and rr > QUIET else NAN
	# A 400 ms gating block every 100 ms, once there are four sub-blocks.
	if _filled >= MOMENTARY_SUBS and is_finite(momentary) and momentary > ABSOLUTE_GATE:
		var e := _mean(MOMENTARY_SUBS)
		var bin := clampi(int((momentary - ABSOLUTE_GATE) / BIN), 0, BINS - 1)
		_counts[bin] += 1
		_sums[bin] += e
		_blocks += 1
		_block_energy += e
	integrated = _gated()


## The mean energy of the last `subs` sub-blocks.
func _mean(subs: int) -> float:
	if subs <= 0:
		return 0.0
	var sum := 0.0
	for i in subs:
		sum += _subs[posmod(_ring - 1 - i, SHORT_SUBS)]
	return sum / float(subs)


## The integrated reading: the blocks over the absolute gate, then those within RELATIVE_GATE of
## their mean.
func _gated() -> float:
	if _blocks == 0:
		return -INF
	var threshold := lufs(_block_energy / float(_blocks)) + RELATIVE_GATE
	var from := clampi(int(ceil((threshold - ABSOLUTE_GATE) / BIN)), 0, BINS)
	var count := 0
	var sum := 0.0
	for bin in range(from, BINS):
		count += _counts[bin]
		sum += _sums[bin]
	return lufs(sum / float(count)) if count > 0 else -INF


## A loudness in words: "−14.2 LUFS", "−∞ LUFS".
static func words(value: float) -> String:
	if not is_finite(value):
		return "−∞ LUFS"
	return "%s%.1f LUFS" % ["−" if value < 0.0 else "", absf(value)]
