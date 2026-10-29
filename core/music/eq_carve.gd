class_name EqCarve
extends RefCounted

## Carving a clash on the EQ wall (docs/spatial_loop.md part two, slice 37, idea #8): a glowing
## overlap (EqWall.Clash) grabbed on one track's side and pushed into the wall cuts that track
## where the two fight. No verb of its own: the carve is add_fx and set_fx_param, inside the push's
## one edit. Static and pure, so every machine reads a carve the same way; the push itself, and
## what it remembers between frames, is the glow's.
##
## On the built-in engine the carve is an EQ21 (FXCatalogue's `eq21`: 21 fixed half-octave bands,
## gain only) at the end of the track's chain, put there by the first push. A push cuts the bands
## whose centres fall inside the clash's span, or the nearest one where none does (`bands_for`),
## each from where it was by how far the push went, down to CUT_MOST_DB. So it is half an octave
## wide a band, not a narrow notch, and the card says which bands.
##
## On Reaper it is a ReaEQ: its first peaking band (`reaeq_params`, found by its parameters'
## names) set to the clash's middle frequency, its bandwidth to the clash's span in octaves, and its
## gain to the push. ReaEQ's normalised laws (`reaeq_*_value`) are taken as ReaEQ's ranges have
## them: frequency logarithmic over 20 Hz to 24 kHz, gain as amplitude over four (0.25 at 0 dB, as
## ReaComp's threshold is amplitude), bandwidth linear over 0 to 4 octaves. Its gain writes are OSC
## writes, so on Reaper each is Reaper's own undo point; the ReaEQ's adding is the edit's. It is one
## band, so a push on a second clash moves it there and the first clash's cut goes; the card says so
## where the band is cutting somewhere else (`push_words`).

## The deepest a carve cuts (dB), how far a push goes to get there (m: a hand into the wall, or a
## drag down it), and a wheel notch's cut (dB; Shift a fifth of it).
const CUT_MOST_DB := -12.0
const PUSH_FULL := 0.2
const NOTCH_DB := 0.5
const FINE_NOTCH_DB := 0.1
## The built-in carve's kind, and ReaEQ's range of frequency and bandwidth for its laws.
const KIND := &"eq21"
const REAEQ_LOW_HZ := 20.0
const REAEQ_HIGH_HZ := 24000.0
const REAEQ_MOST_OCTAVES := 4.0
## How near (octaves) a ReaEQ's band must already be to a clash for a push to start from its gain
## rather than from flat: a push on another clash moves the band there.
const SAME_BAND_OCTAVES := 0.34


## Which engine carves: &"built_in" where the DAW's plugin choices have the `eq21` kind, &"reaper"
## where they have a ReaEQ, &"" where neither, read from the choices so a guest reads it as its
## host does.
static func engine() -> StringName:
	if DAW.state == null:
		return &""
	var reaper := false
	for c in DAW.state.fx_choices:
		var row := c as Array
		if row.is_empty():
			continue
		if str(row[0]) == String(KIND):
			return &"built_in"
		if (str(row[0]) + " " + (str(row[1]) if row.size() > 1 else "")).to_lower().contains("reaeq"):
			reaper = true
	return &"reaper" if reaper else &""


## The plugin a first push adds: `eq21`, or the ReaEQ's id; "" where the DAW offers neither.
static func choice() -> String:
	var which := engine()
	if which == &"built_in":
		return String(KIND)
	if which == &"reaper":
		for c in DAW.state.fx_choices:
			var row := c as Array
			if row.size() >= 1 and (str(row[0]) + " " + (str(row[1]) if row.size() > 1 else "")).to_lower().contains("reaeq"):
				return str(row[0])
	return ""


## Whether a plugin is one a carve moves: the built-in EQ21, or a ReaEQ.
static func is_carver(f: MixState.FXState) -> bool:
	if f == null:
		return false
	match engine():
		&"built_in":
			return f.name == str(FXCatalogue.kinds()[KIND]["name"])
		&"reaper":
			return f.name.to_lower().contains("reaeq")
	return false


## The carving EQ on `track` (its FX index): the last carver in its chain, so a push moves the one
## a push put at the end; -1 for none.
static func carver_on(track: int) -> int:
	var t := DAW.state.track(track, false) if DAW.state != null else null
	if t == null:
		return -1
	var found := -1
	for i in t.plugins():
		if is_carver(t.fx[i]):
			found = i
	return found


# --- the built-in carve's bands -------------------------------------------------------------

## The EQ21 bands (indices) a clash over Spectra bands `from` to `to` cuts: those whose centres
## fall inside its span's edges, or the nearest to its middle where none does.
static func bands_for(from: int, to: int) -> Array[int]:
	var lo := Spectra.edges(mini(from, to)).x
	var hi := Spectra.edges(maxi(from, to)).y
	var out: Array[int] = []
	for i in FXCatalogue.EQ21_HZ.size():
		var hz: float = FXCatalogue.EQ21_HZ[i]
		if hz >= lo and hz <= hi:
			out.append(i)
	if out.is_empty():
		var mid := sqrt(lo * hi)
		var best := 0
		for i in FXCatalogue.EQ21_HZ.size():
			if absf(log(FXCatalogue.EQ21_HZ[i] / mid)) < absf(log(FXCatalogue.EQ21_HZ[best] / mid)):
				best = i
		out.append(best)
	return out


## "63 + 90 Hz": the bands' centres as the card says what a push cuts.
static func bands_words(bands: Array[int]) -> String:
	return "%s Hz" % " + ".join(PackedStringArray(bands.map(func(b: int) -> String: return Spectra.hz_words(FXCatalogue.EQ21_HZ[b]))))


## "the 63 and 90 Hz bands", "the 63 Hz band".
static func bands_list(bands: Array[int]) -> String:
	var names: Array = bands.map(func(b: int) -> String: return Spectra.hz_words(FXCatalogue.EQ21_HZ[b]))
	if names.size() == 1:
		return "the %s Hz band" % names[0]
	return "the %s and %s Hz bands" % [", ".join(PackedStringArray(names.slice(0, names.size() - 1))), names[-1]]


## A built-in band's gain (dB) from its normalised value, and back.
static func eq21_db(v: float) -> float:
	return (FXCatalogue.params(KIND)[0] as FXCatalogue.Param).value_of(v)


static func eq21_value(db: float) -> float:
	return (FXCatalogue.params(KIND)[0] as FXCatalogue.Param).normalise(db)


# --- ReaEQ -------------------------------------------------------------------------------------

## ReaEQ's first peaking band, by its parameters' names as Reaper reports them ("Freq-Band 2",
## "Gain-Band 2", "BW-Band 2"; or "Freq-Band" and so on, repeated per band): the first frequency
## parameter whose name says band and not shelf, and the gain and bandwidth (or Q) parameters after
## it with the same suffix. {"freq", "gain", "bw"} as parameter indices, or {} until the names have
## come.
static func reaeq_params(f: MixState.FXState) -> Dictionary:
	if f == null:
		return {}
	var order: Array = f.param_names.keys()
	order.sort()
	for i: int in order:
		var n := str(f.param_names[i])
		var low := n.to_lower()
		if not low.begins_with("freq") or not low.contains("band") or low.contains("shelf") or not n.contains("-"):
			continue
		var suffix := n.substr(n.find("-") + 1)
		var out := {"freq": i}
		for j: int in order:
			if j <= i:
				continue
			var m := str(f.param_names[j])
			if not out.has("gain") and m.to_lower() == ("gain-" + suffix).to_lower():
				out["gain"] = j
			elif not out.has("bw") and (m.to_lower() == ("bw-" + suffix).to_lower() or m.to_lower() == ("q-" + suffix).to_lower()):
				out["bw"] = j
			if out.has("gain") and out.has("bw"):
				return out
	return {}


static func reaeq_freq_value(hz: float) -> float:
	return clampf(log(clampf(hz, REAEQ_LOW_HZ, REAEQ_HIGH_HZ) / REAEQ_LOW_HZ) / log(REAEQ_HIGH_HZ / REAEQ_LOW_HZ), 0.0, 1.0)


static func reaeq_freq_hz(v: float) -> float:
	return REAEQ_LOW_HZ * pow(REAEQ_HIGH_HZ / REAEQ_LOW_HZ, clampf(v, 0.0, 1.0))


static func reaeq_gain_value(db: float) -> float:
	return clampf(db_to_linear(db) * 0.25, 0.0, 1.0)


static func reaeq_gain_db(v: float) -> float:
	return linear_to_db(maxf(v * 4.0, 0.000001))


static func reaeq_bw_value(octaves: float) -> float:
	return clampf(octaves / REAEQ_MOST_OCTAVES, 0.0, 1.0)


## A clash's middle (Hz) and its span in octaves, from its Spectra bands' edges.
static func middle_hz(from: int, to: int) -> float:
	return sqrt(Spectra.edges(mini(from, to)).x * Spectra.edges(maxi(from, to)).y)


static func span_octaves(from: int, to: int) -> float:
	return log(Spectra.edges(maxi(from, to)).y / Spectra.edges(mini(from, to)).x) / log(2.0)


# --- a push ---------------------------------------------------------------------------------

## How far a push has cut (dB, 0 to CUT_MOST_DB's range, negative cuts): `depth` m into the wall
## or down it; a pull back out raises again.
static func cut_of(depth: float) -> float:
	return CUT_MOST_DB * depth / PUSH_FULL


## Where a band starts from and where `change` dB takes it: never past CUT_MOST_DB below, and never
## boosted past where it began or flat.
static func carved(start_db: float, change: float) -> float:
	return clampf(start_db + change, minf(start_db, CUT_MOST_DB), maxf(start_db, 0.0))


## What a push on `track`'s EQ `fx` over Spectra bands `from` to `to` starts from: {param: dB}, the
## gains it moves as they are now; or {} while the EQ (or, on Reaper, its parameters' names) has not
## come.
static func start_of(track: int, fx: int, from: int, to: int) -> Dictionary:
	var f := DAW.state.fx(track, fx, false) if DAW.state != null and fx >= 0 else null
	if f == null:
		return {}
	var out := {}
	if engine() == &"built_in":
		for b in bands_for(from, to):
			out[b] = eq21_db(float(f.params.get(b, 0.5)))
		return out
	var band := reaeq_params(f)
	if band.is_empty():
		return {}
	var gain := 0.0
	if f.params.has(band["freq"]) and f.params.has(band["gain"]):
		var was := reaeq_freq_hz(float(f.params[band["freq"]]))
		if absf(log(was / middle_hz(from, to)) / log(2.0)) <= SAME_BAND_OCTAVES:
			gain = minf(reaeq_gain_db(float(f.params[band["gain"]])), 0.0)
	out[band["gain"]] = gain
	return out


## The push's writes: each gain in `start` ({param: dB}, start_of) taken `change` dB on, written
## only where it moved; on Reaper the band's frequency and bandwidth set to the clash first, where
## they are not there already. Inside whatever edit the push has open.
static func write(track: int, fx: int, from: int, to: int, start: Dictionary, change: float) -> void:
	var f := DAW.state.fx(track, fx, false) if DAW.state != null else null
	if f == null:
		return
	if engine() == &"reaper":
		var band := reaeq_params(f)
		if band.is_empty():
			return
		var hz := reaeq_freq_value(middle_hz(from, to))
		var bw := reaeq_bw_value(span_octaves(from, to))
		if absf(float(f.params.get(band["freq"], -1.0)) - hz) > 0.0005:
			DAW.set_fx_param(track, fx, band["freq"], hz)
		if absf(float(f.params.get(band["bw"], -1.0)) - bw) > 0.0005:
			DAW.set_fx_param(track, fx, band["bw"], bw)
		for p: int in start:
			var v := reaeq_gain_value(carved(float(start[p]), change))
			if absf(float(f.params.get(p, -1.0)) - v) > 0.0005:
				DAW.set_fx_param(track, fx, p, v)
		return
	for p: int in start:
		var v := eq21_value(carved(float(start[p]), change))
		if absf(float(f.params.get(p, -1.0)) - v) > 0.0005:
			DAW.set_fx_param(track, fx, p, v)


## Where `track`'s ReaEQ band is cutting (Hz) when that is not the clash over `from` to `to`, so a
## push there would move it and give that cut back; 0 where it is not cutting, or is here already.
static func reaeq_cut_elsewhere(track: int, from: int, to: int) -> float:
	var fx := carver_on(track)
	var f := DAW.state.fx(track, fx, false) if fx >= 0 else null
	var band := reaeq_params(f)
	if band.is_empty() or not f.params.has(band["freq"]) or not f.params.has(band["gain"]):
		return 0.0
	var hz := reaeq_freq_hz(float(f.params[band["freq"]]))
	if absf(log(hz / middle_hz(from, to)) / log(2.0)) <= SAME_BAND_OCTAVES or reaeq_gain_db(float(f.params[band["gain"]])) > -FINE_NOTCH_DB:
		return 0.0
	return hz


## The cut a track's carver has in a clash's bands now (dB, the deepest of them), or 0.
static func cut_now(track: int, from: int, to: int) -> float:
	var fx := carver_on(track)
	var start := start_of(track, fx, from, to)
	var most := 0.0
	for p in start:
		most = minf(most, float(start[p]))
	return most


## What a push on `track`'s side of a clash over `from` to `to` does, for its card: "push: cut BASS
## DI at 63 + 90 Hz · cuts the 63 and 90 Hz bands, each half an octave".
static func push_words(track: int, from: int, to: int) -> String:
	var t := DAW.state.track(track, false) if DAW.state != null else null
	var who := t.display_name().to_upper() if t != null else "TRACK %d" % track
	match engine():
		&"built_in":
			var bands := bands_for(from, to)
			return "push: cut %s at %s · cuts %s, %s" % [who, bands_words(bands), bands_list(bands),
					"half an octave wide" if bands.size() == 1 else "each half an octave"]
		&"reaper":
			var said := "push: cut %s at %s Hz, a ReaEQ band %s wide" % [who, Spectra.hz_words(roundf(middle_hz(from, to))),
					Spectra.span_words(from, to)]
			var elsewhere := reaeq_cut_elsewhere(track, from, to)
			if elsewhere > 0.0:
				said += " · its one band, cutting %s Hz now, moves here" % Spectra.hz_words(roundf(elsewhere))
			return said
	return "this DAW offers no EQ to carve %s with" % who
