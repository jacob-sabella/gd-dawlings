class_name FaderLaw
extends RefCounted

## Reaper's fader taper: where on a 0..1 fader a given dB sits.
##
## Measured, not derived. Reaper's OSC volume is not the 40*log10 curve that a fader drawing a
## control surface usually assumes: 0 dB sits at 0.716, the top of travel is +12 dB, and below
## about -40 dB each 12 dB down is a fixed ratio (10^(-1/5)) of travel. The table below is Reaper
## 7 answering `/track/n/volume` for each dB set through the API, every 3 dB from +12 to -60,
## and interpolating it in log space reproduces the 0.5 dB measurements to within 0.006 dB.
## The old formula put a cap labelled -12 dB at -11.1 dB in Reaper, which is the kind of lie a
## mix engineer finds by ear an hour later.

const TOP_DB := 12.0
const STEP_DB := 3.0
## Taper at TOP_DB, TOP_DB - 3, ... down to -60 dB.
const TABLE: PackedFloat64Array = [
	1.00000, 0.92470, 0.85229, 0.78276, 0.71600, 0.65284, 0.59285, 0.53648, 0.48395, 0.43538,
	0.39080, 0.35015, 0.31330, 0.28003, 0.25009, 0.22322, 0.19916, 0.17764, 0.15841, 0.14123,
	0.12591, 0.11224, 0.10005, 0.08917, 0.07948,
]
## Below the table the curve is a straight line in log space: 60 dB per decade of travel.
const TAIL_DB_PER_DECADE := 60.0


static func to_taper(db: float) -> float:
	if db == -INF:
		return 0.0
	if db >= TOP_DB:
		return 1.0
	var at := (TOP_DB - db) / STEP_DB
	var last := TABLE.size() - 1
	if at >= last:
		var floor_db := TOP_DB - last * STEP_DB
		return TABLE[last] * pow(10.0, (db - floor_db) / TAIL_DB_PER_DECADE)
	var i := int(at)
	var f := at - i
	return pow(10.0, lerpf(log(TABLE[i]), log(TABLE[i + 1]), f) / log(10.0))


static func to_db(taper: float) -> float:
	if taper <= 0.0:
		return -INF
	if taper >= 1.0:
		return TOP_DB
	var last := TABLE.size() - 1
	if taper <= TABLE[last]:
		var floor_db := TOP_DB - last * STEP_DB
		return floor_db + TAIL_DB_PER_DECADE * log(taper / TABLE[last]) / log(10.0)
	# Descending table: find the pair the taper falls between.
	var i := 0
	while i < last - 1 and taper < TABLE[i + 1]:
		i += 1
	var f := (log(taper) - log(TABLE[i])) / (log(TABLE[i + 1]) - log(TABLE[i]))
	return TOP_DB - (i + f) * STEP_DB
