class_name RackCurves
extends RefCounted

## The shapes a module's knobs make, as heights from 0 to 1 across a pane: an envelope's rise, fall, hold
## and release; a filter's response from low notes to high. The rack wall draws them standing out of the
## glass, and they follow the knobs as they turn.

const POINTS := 48
const DB_LOW := -48.0
const DB_HIGH := 18.0


## An ADSR drawn against time. `a`, `d`, `r` in seconds, `s` a level; a rest is held between decay and
## release so the sustain can be seen, a fifth of the whole.
static func envelope(a: float, d: float, s: float, r: float, n := POINTS) -> PackedFloat32Array:
	a = maxf(a, 0.001)
	d = maxf(d, 0.001)
	r = maxf(r, 0.001)
	s = clampf(s, 0.0, 1.0)
	var hold := (a + d + r) * 0.25
	var total := a + d + hold + r
	# Each stage keeps at least a tenth of the pane, so a snappy attack stays visible.
	var shares: Array = [a / total, d / total, hold / total, r / total]
	var floor_share := 0.1
	var spare := 1.0
	for i in [0, 1, 3]:
		shares[i] = maxf(shares[i], floor_share)
	shares[2] = maxf(shares[2], 0.14)
	var sum := 0.0
	for v in shares:
		sum += v
	for i in 4:
		shares[i] = shares[i] / sum * spare
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(n - 1)
		var v := 0.0
		if t < shares[0]:
			v = t / shares[0]
		elif t < shares[0] + shares[1]:
			var u: float = (t - shares[0]) / shares[1]
			v = s + (1.0 - s) * exp(-4.0 * u)
		elif t < shares[0] + shares[1] + shares[2]:
			v = s
		else:
			var u2: float = (t - shares[0] - shares[1] - shares[2]) / shares[3]
			v = s * exp(-4.0 * u2) * (1.0 - u2 * u2 * u2 * 0.02)
		out[i] = clampf(v, 0.0, 1.0)
	return out


## A filter's magnitude response, 20 Hz to 18 kHz on a log axis, between DB_LOW and DB_HIGH decibels.
## `kind` is "lp", "hp" or "bp"; `poles` 2 or 4; `q` the resonance's peak.
static func filter(kind: String, poles: int, cutoff: float, q: float, n := POINTS) -> PackedFloat32Array:
	cutoff = maxf(cutoff, 1.0)
	q = maxf(q, 0.4)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var f := 20.0 * pow(18000.0 / 20.0, float(i) / float(n - 1))
		var w := f / cutoff
		var den := sqrt(pow(1.0 - w * w, 2.0) + pow(w / q, 2.0))
		var h := 1.0
		match kind:
			"hp":
				h = w * w / maxf(den, 0.0001)
			"bp":
				h = (w / q) / maxf(den, 0.0001)
			_:
				h = 1.0 / maxf(den, 0.0001)
		if poles >= 4:
			h = h * h
		var db := 20.0 * log(maxf(h, 0.00001)) / log(10.0)
		out[i] = clampf((db - DB_LOW) / (DB_HIGH - DB_LOW), 0.0, 1.0)
	return out


## The highest point of a curve, and the column it is in.
static func peak(c: PackedFloat32Array) -> float:
	var best := 0.0
	for v in c:
		best = maxf(best, v)
	return best


static func peak_at(c: PackedFloat32Array) -> int:
	var best := 0
	for i in c.size():
		if c[i] > c[best]:
			best = i
	return best


## The curve a module's knob values make, or empty for a module with none.
## `values` is knob id -> real value.
static func of(type: String, values: Dictionary) -> PackedFloat32Array:
	match type:
		"env":
			return envelope(values.get("a", 0.01), values.get("d", 0.3), values.get("s", 0.6), values.get("r", 0.3))
		"svf":
			return filter("lp", 2, values.get("cutoff", 1200.0), 0.6 + float(values.get("res", 0.3)) * 9.0)
		"ladder":
			var mode := int(values.get("mode", 0))
			var kind: String = ["lp", "lp", "bp", "bp", "hp", "hp"][clampi(mode, 0, 5)]
			var poles := 4 if mode % 2 == 0 else 2
			return filter(kind, poles, values.get("cutoff", 900.0), 0.6 + float(values.get("res", 0.4)) * 5.0)
	return PackedFloat32Array()
