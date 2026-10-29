class_name FXCatalogue
extends RefCounted

## Godot's own audio effects, described the way a rack wants a plugin described: a name, and a
## list of parameters each with a range, a curve and a way of printing itself.
##
## The rack, the knobs and the replication all speak normalised 0..1 per parameter, the same as
## Reaper's OSC does. This is the only place that knows a compressor's ratio runs 1 to 48 on a
## log curve, so the rest of the studio cannot tell a Godot compressor from a ReaComp.

## kind -> {"name": rack caption, "make": Callable() -> AudioEffect, "params": [Param...]}
static var _kinds: Dictionary = {}


class Param:
	var name := ""
	var low := 0.0
	var high := 1.0
	var curved := false
	var unit := ""
	## Set the value on the effect. Defaults to `effect.set(property, value)`.
	var apply: Callable
	var property := ""

	func _init(p_name: String, p_property: String, p_low: float, p_high: float,
			p_unit := "", p_log := false) -> void:
		name = p_name
		property = p_property
		low = p_low
		high = p_high
		unit = p_unit
		curved = p_log

	func value_of(v: float) -> float:
		v = clampf(v, 0.0, 1.0)
		if curved and low > 0.0:
			return low * pow(high / low, v)
		return lerpf(low, high, v)

	func normalise(x: float) -> float:
		if curved and low > 0.0:
			return clampf(log(x / low) / log(high / low), 0.0, 1.0)
		return clampf(inverse_lerp(low, high, x), 0.0, 1.0)

	func text(v: float) -> String:
		var x := value_of(v)
		match unit:
			"Hz":
				return "%.1f kHz" % (x / 1000.0) if x >= 1000.0 else "%d Hz" % roundi(x)
			"dB":
				return "%+.1f dB" % x
			"ms":
				return "%d ms" % roundi(x)
			"%":
				return "%d%%" % roundi(x * 100.0)
			":1":
				return "%.1f:1" % x
			"":
				return "%.2f" % x
		return "%.1f %s" % [x, unit]

	func set_on(effect: AudioEffect, v: float) -> void:
		if apply.is_valid():
			apply.call(effect, value_of(v))
		else:
			effect.set(property, value_of(v))


static func kinds() -> Dictionary:
	if not _kinds.is_empty():
		return _kinds
	var eq_bands := ["32 Hz", "100 Hz", "320 Hz", "1 kHz", "3.2 kHz", "10 kHz"]
	var eq_params: Array = []
	for b in eq_bands.size():
		var p := Param.new(eq_bands[b], "", -15.0, 15.0, "dB")
		var band := b
		p.apply = func(e: AudioEffect, x: float): (e as AudioEffectEQ6).set_band_gain_db(band, x)
		eq_params.append(p)
	# EQ21: half-octave bands, gain only, each named by its centre. EQ6's 100 Hz band covers a
	# kick's lows and a bass's both, so the EQ wall carves with this one (EqCarve).
	var eq21_params: Array = []
	for b in EQ21_HZ.size():
		var p := Param.new(band_name(EQ21_HZ[b]), "", -15.0, 15.0, "dB")
		var band := b
		p.apply = func(e: AudioEffect, x: float): (e as AudioEffectEQ21).set_band_gain_db(band, x)
		eq21_params.append(p)
	_kinds = {
		&"eq": {"name": "EQ6", "make": func(): return AudioEffectEQ6.new(), "params": eq_params},
		&"eq21": {"name": "EQ21", "make": func(): return AudioEffectEQ21.new(), "params": eq21_params},
		&"compressor": {"name": "Compressor", "make": func(): return AudioEffectCompressor.new(),
			"params": [
				Param.new("Thresh", "threshold", -60.0, 0.0, "dB"),
				Param.new("Ratio", "ratio", 1.0, 48.0, ":1", true),
				Param.new("Makeup", "gain", 0.0, 20.0, "dB"),
				Param.new("Attack", "attack_us", 20.0, 2000.0, "us", true),
				Param.new("Release", "release_ms", 20.0, 2000.0, "ms", true),
				Param.new("Mix", "mix", 0.0, 1.0, "%"),
			]},
		&"reverb": {"name": "Reverb", "make": func(): return AudioEffectReverb.new(),
			"params": [
				Param.new("Size", "room_size", 0.0, 1.0, "%"),
				Param.new("Damping", "damping", 0.0, 1.0, "%"),
				Param.new("Spread", "spread", 0.0, 1.0, "%"),
				Param.new("Pre-delay", "predelay_msec", 20.0, 500.0, "ms"),
				Param.new("Hi-pass", "hipass", 0.0, 1.0, "%"),
				Param.new("Wet", "wet", 0.0, 1.0, "%"),
				Param.new("Dry", "dry", 0.0, 1.0, "%"),
			]},
		&"delay": {"name": "Delay", "make": func(): return AudioEffectDelay.new(),
			"params": [
				Param.new("Time", "feedback_delay_ms", 20.0, 1500.0, "ms", true),
				Param.new("Feedback", "feedback_level_db", -60.0, 0.0, "dB"),
				Param.new("Tap", "tap1_delay_ms", 20.0, 1500.0, "ms", true),
				Param.new("Tap level", "tap1_level_db", -60.0, 0.0, "dB"),
				Param.new("Dry", "dry", 0.0, 1.0, "%"),
			]},
		&"chorus": {"name": "Chorus", "make": func(): return AudioEffectChorus.new(),
			"params": [
				Param.new("Wet", "wet", 0.0, 1.0, "%"),
				Param.new("Dry", "dry", 0.0, 1.0, "%"),
				Param.new("Rate", "voice/1/rate_hz", 0.1, 20.0, "Hz", true),
				Param.new("Depth", "voice/1/depth_ms", 0.0, 20.0, "ms"),
			]},
		&"filter": {"name": "Low-pass", "make": func(): return AudioEffectLowPassFilter.new(),
			"params": [
				Param.new("Cutoff", "cutoff_hz", 20.0, 20000.0, "Hz", true),
				Param.new("Resonance", "resonance", 0.0, 1.0, "%"),
			]},
		&"distortion": {"name": "Drive", "make": func(): return AudioEffectDistortion.new(),
			"params": [
				Param.new("Drive", "drive", 0.0, 1.0, "%"),
				Param.new("Pre-gain", "pre_gain", -24.0, 24.0, "dB"),
				Param.new("Post-gain", "post_gain", -24.0, 24.0, "dB"),
				Param.new("Keep HF", "keep_hf_hz", 1000.0, 20000.0, "Hz", true),
			]},
		&"phaser": {"name": "Phaser", "make": func(): return AudioEffectPhaser.new(),
			"params": [
				Param.new("Rate", "rate_hz", 0.01, 10.0, "Hz", true),
				Param.new("Depth", "depth", 0.1, 4.0, ""),
				Param.new("Feedback", "feedback", 0.1, 0.9, "%"),
				Param.new("Low", "range_min_hz", 10.0, 10000.0, "Hz", true),
				Param.new("High", "range_max_hz", 10.0, 10000.0, "Hz", true),
			]},
		&"limiter": {"name": "Limiter", "make": func(): return AudioEffectHardLimiter.new(),
			"params": [
				Param.new("Ceiling", "ceiling_db", -24.0, 0.0, "dB"),
				Param.new("Pre-gain", "pre_gain_db", 0.0, 24.0, "dB"),
				Param.new("Release", "release", 0.01, 1.0, "s", true),
			]},
	}
	return _kinds


## AudioEffectEQ21's fixed band centres (Hz), half an octave apart, 22 Hz to 22 kHz, in its order.
const EQ21_HZ := [22.0, 32.0, 44.0, 63.0, 90.0, 125.0, 175.0, 250.0, 350.0, 500.0, 700.0, 1000.0,
		1400.0, 2000.0, 2800.0, 4000.0, 5600.0, 8000.0, 11000.0, 16000.0, 22000.0]


## A band's parameter name, by its centre: "63 Hz", "1.4 kHz".
static func band_name(hz: float) -> String:
	if hz >= 1000.0:
		var k := hz / 1000.0
		return ("%d kHz" % roundi(k)) if is_equal_approx(k, roundf(k)) else ("%s kHz" % String.num(k, 1))
	return "%d Hz" % roundi(hz)


## Which of `kind`'s parameters is called `param_name`, or -1: an EQ's band by its name.
static func param_named(kind: StringName, param_name: String) -> int:
	if not kinds().has(kind):
		return -1
	var list := params(kind)
	for i in list.size():
		if (list[i] as Param).name == param_name:
			return i
	return -1


static func make(kind: StringName) -> AudioEffect:
	return kinds()[kind]["make"].call()


static func params(kind: StringName) -> Array:
	return kinds()[kind]["params"]


## Where a freshly made effect's parameters sit, normalised: read back from the effect, so the
## knobs open on Godot's own defaults rather than on a guess about them.
static func defaults(kind: StringName) -> PackedFloat32Array:
	var effect := make(kind)
	var out := PackedFloat32Array()
	for p in params(kind):
		var x = effect.get(p.property) if p.property != "" else 0.0
		out.append(p.normalise(float(x)) if x != null else 0.5)
	return out
