class_name Spectra
extends Node

## Each track's spectrum, as the EQ wall shows it (EqWall, docs/spatial_loop.md part two, slice 36,
## idea #8): 31 third-octave bands from 20 Hz to 20 kHz, each a level in dB of full scale, a sine
## reading its own peak.
##
## Measured where the tracks are played. On the built-in engine every track bus ends in an
## AudioEffectSpectrumAnalyzer (GodotBackend.track_spectrum), after its width and its pan, where
## no cue, probe or send copy takes it; Godot runs a bus's effects before its volume, so the bands
## are scaled by the track's fader there and are silent while it cannot be heard, which makes them
## the levels heard. Read in the bands here and averaged over WINDOW. Reaper hands its tracks'
## audio to nobody, so a host on Reaper has none (Capability.SPECTRA) and the wall says so.
##
## A host sends them to its guests SEND_HZ times a second as a byte a band per track (`pack`,
## Session.send_spectra, unreliable: a lost one is overtaken by the next), and a guest shows the
## host's. This node is the one a studio stands up: on a host or alone it measures, and on a host
## it sends; `latest` is what this machine shows, wherever it came from, and `reason` what it says
## where there is nothing to show.
##
## A folder's bus is its children's sum, so it would match every one of them band for band: only
## tracks that play their own sound are measured (`measured`). A return fed by sends is the same
## kind of sum, of the tracks that send to it, but it plays its own effects, so it is measured and
## shown; it is only never found clashing with a track it carries (`feeds`).
##
## A clash (`clashes`) is where two tracks fight for the same bands: both above LOUD_DB and within
## NEAR_DB of each other, run together over neighbouring bands. LOUD_DB is under the mix's loudest
## band (`reference`), not under full scale: a track's third octave sits 20 to 50 dB under full
## scale in a mix, and the demo's loudest band is about -20 dBFS, so a floor at -30 dBFS would find
## a clash only in a mix pushed hot. Under the mix's own loudest band it finds the same fight in a
## quiet mix and a loud one. The wall's scale is the same reference: its full width is that band.

## The bands' nominal centres (Hz), ISO's third octaves, and how many.
const CENTRES := [20.0, 25.0, 31.5, 40.0, 50.0, 63.0, 80.0, 100.0, 125.0, 160.0, 200.0, 250.0,
		315.0, 400.0, 500.0, 630.0, 800.0, 1000.0, 1250.0, 1600.0, 2000.0, 2500.0, 3150.0, 4000.0,
		5000.0, 6300.0, 8000.0, 10000.0, 12500.0, 16000.0, 20000.0]
const BANDS := 31
## The range shown, bottom to top.
const LOW_HZ := 20.0
const HIGH_HZ := 20000.0
## Silence, and the loudest a band is kept to (dB). The wire's byte spans these.
const FLOOR_DB := -96.0
const TOP_DB := 6.0
## A clash: both above this (dB under the reference), and no further apart than NEAR_DB.
const LOUD_DB := -30.0
const NEAR_DB := 6.0
## The reference (the mix's loudest band) is never put lower than this (dBFS), so a near-silent mix
## is drawn small rather than blown up to the wall's full width; and it falls this fast (dB a
## second) after a loud moment, so the shapes do not jump wider between the kick's hits.
const REFERENCE_FLOOR_DB := -48.0
const REFERENCE_FALL_DB := 6.0
## How long a band is averaged over (s), how often a host or a lone player reads them (Hz), and how
## often a host sends them on (Hz).
const WINDOW := 0.3
const READ_HZ := 20.0
const SEND_HZ := 5.0
## A guest that has heard nothing from its host for this long (ms) has no spectra to show.
const STALE_MSEC := 1500
## A track's entry on the wire: its index (two bytes, little-endian), then a byte a band.
const ENTRY_BYTES := 2 + BANDS
## A parcel's most, under the MTU like the state's (Session.PARCEL_BYTES).
const PARCEL_BYTES := 1100
## Whether track `from` is heard in track `to`'s bus: its sound goes there through the folders it
## plays through and the sends of each track it reaches, a return's own sends too. A key send
## reaches only the destination's detectors, never its sound, so it does not count.
static func feeds(from: int, to: int) -> bool:
	var state := DAW.state
	if state == null or from == to or not state.tracks.has(from) or not state.tracks.has(to):
		return false
	var seen := {from: true}
	var reached: Array = [from]
	while not reached.is_empty():
		var t: int = reached.pop_back()
		var next: Array = [_folder_of(state, t)]
		for sd: MixState.SendState in (state.tracks[t] as MixState.TrackState).sends.values():
			if not sd.key:
				next.append(sd.resolve(state))
		for d: int in next:
			if d == to:
				return true
			if d > 0 and not seen.has(d) and state.tracks.has(d):
				seen[d] = true
				reached.append(d)
	return false


## Whether track `index` is a return: some track sends its sound there (a key send does not).
static func is_return(index: int) -> bool:
	var state := DAW.state
	if state == null:
		return false
	for t in state.track_indices():
		for sd: MixState.SendState in (state.tracks[t] as MixState.TrackState).sends.values():
			if not sd.key and sd.resolve(state) == index:
				return true
	return false


## The folder track `index` plays through, 0 for none (the master), as GodotBackend.parent_of
## finds it, from the folder depths in track order.
static func _folder_of(state: MixState, index: int) -> int:
	var stack: Array = []
	for i in state.track_indices():
		if i == index:
			return stack[-1] if not stack.is_empty() else 0
		var depth: int = (state.tracks[i] as MixState.TrackState).folder_depth
		if depth > 0:
			stack.append(i)
		elif depth < 0:
			for _n in -depth:
				if not stack.is_empty():
					stack.pop_back()
	return 0


## What the wall says where it has nothing to show, and why.
const NEED_ENGINE := "spectra need the built-in engine"
const NEED_HOST := "spectra need the host on the built-in engine"

## (track: int) -> PackedFloat32Array, BANDS levels in dB: how a host or a lone player measures a
## track. The built-in engine's own unless a test or the probe gives another.
var measure: Callable = Callable()
## What this machine shows: track -> its bands, as last read here or heard from the host.
var _shown := {}
## What they stand against (dBFS): the mix's loudest band, held and let fall at REFERENCE_FALL_DB.
var reference := REFERENCE_FLOOR_DB
var _reference_at := -1
var _next_read := 0
var _next_send := 0


# --- the bands --------------------------------------------------------------------------------

## A band's exact centre (Hz): 1 kHz times a tenth of a decade a band, as the nominal centres round.
static func centre(band: int) -> float:
	return 1000.0 * pow(10.0, float(band - 17) / 10.0)


## A band's edges (Hz): its centre a twentieth of a decade either way, so the bands meet.
static func edges(band: int) -> Vector2:
	var c := centre(band)
	return Vector2(c * pow(10.0, -0.05), c * pow(10.0, 0.05))


## The band `hz` is in, kept to the range.
static func band_of(hz: float) -> int:
	if hz <= 0.0:
		return 0
	return clampi(roundi(10.0 * log(hz / 1000.0) / log(10.0)) + 17, 0, BANDS - 1)


## How far up the range `hz` is, 0 at LOW_HZ to 1 at HIGH_HZ, logarithmically.
static func height_of(hz: float) -> float:
	return clampf(log(maxf(hz, 1.0) / LOW_HZ) / log(HIGH_HZ / LOW_HZ), 0.0, 1.0)


## "63", "1k", "1.25k", "12.5k": a band's nominal centre as the wall letters it.
static func label(band: int) -> String:
	return hz_words(CENTRES[clampi(band, 0, BANDS - 1)])


static func hz_words(hz: float) -> String:
	if hz >= 1000.0:
		var k := hz / 1000.0
		return ("%dk" % roundi(k)) if is_equal_approx(k, roundf(k)) else ("%sk" % String.num(k, 2).trim_suffix("0"))
	return ("%d" % roundi(hz)) if is_equal_approx(hz, roundf(hz)) else String.num(hz, 1)


## "50-80 Hz", "1k-2k Hz": the span from band `from` to band `to`.
static func span_words(from: int, to: int) -> String:
	if from == to:
		return "%s Hz" % label(from)
	return "%s-%s Hz" % [label(mini(from, to)), label(maxi(from, to))]


## A spectrum of silence.
static func silent() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(BANDS)
	out.fill(FLOOR_DB)
	return out


## Whether anything in `bands` is above `db`.
static func any_above(bands: PackedFloat32Array, db: float) -> bool:
	for v in bands:
		if v > db:
			return true
	return false


# --- clashes ----------------------------------------------------------------------------------

## The loudest band anywhere in `spectra` (dBFS), FLOOR_DB for none.
static func peak_of(spectra: Dictionary) -> float:
	var most := FLOOR_DB
	for bands: PackedFloat32Array in spectra.values():
		for v in bands:
			most = maxf(most, v)
	return most


## The reference `spectra` stand against by themselves: their loudest band, kept to
## REFERENCE_FLOOR_DB.
static func reference_of(spectra: Dictionary) -> float:
	return maxf(peak_of(spectra), REFERENCE_FLOOR_DB)


## Where two tracks fight: band `i` of tracks `a` and `b` both above LOUD_DB under `reference` and
## within NEAR_DB of each other.
static func clash_at(a: PackedFloat32Array, b: PackedFloat32Array, i: int, reference: float) -> bool:
	var loud := reference + LOUD_DB
	return a[i] > loud and b[i] > loud and absf(a[i] - b[i]) <= NEAR_DB


## Every clash in `spectra` (track -> bands), worst first: {"a", "b" (a < b), "from", "to" (the
## run's bands, inclusive), "score", "wet"}. The score is how far above the floor the quieter of
## the two is, added up over the run, so a long loud clash outranks a short quiet one. Against
## `reference` (dBFS), or with none (NAN) against their own (`reference_of`); the wall gives the
## whole mix's, so showing two tracks of it does not move the floor.
##
## Two tracks one of which carries the other (`feeds`: a reverb return and a track that sends to
## it) never clash: the return matches its sources by being made of them. A clash with a return
## that does not carry the other is "wet" and comes after every clash between two dry tracks,
## whatever its score: what a return plays is other tracks' sound through its effects, so its
## fight is theirs at one remove, and the wall's few glows go first to the fights at the source,
## the kick's with the bass's.
static func clashes(spectra: Dictionary, reference := NAN) -> Array:
	var ref := reference_of(spectra) if is_nan(reference) else reference
	var tracks: Array = spectra.keys()
	tracks.sort()
	var wet := {}
	for t in tracks:
		wet[t] = is_return(t)
	var out: Array = []
	for n in tracks.size():
		for m in range(n + 1, tracks.size()):
			var a: PackedFloat32Array = spectra[tracks[n]]
			var b: PackedFloat32Array = spectra[tracks[m]]
			if a.size() != BANDS or b.size() != BANDS:
				continue
			if feeds(tracks[n], tracks[m]) or feeds(tracks[m], tracks[n]):
				continue
			var from := -1
			var score := 0.0
			for i in BANDS + 1:
				if i < BANDS and clash_at(a, b, i, ref):
					if from < 0:
						from = i
						score = 0.0
					score += minf(a[i], b[i]) - (ref + LOUD_DB)
				elif from >= 0:
					out.append({"a": tracks[n], "b": tracks[m], "from": from, "to": i - 1, "score": score,
							"wet": wet[tracks[n]] or wet[tracks[m]]})
					from = -1
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return x["score"] > y["score"] if x["wet"] == y["wet"] else y["wet"])
	return out


## The two tracks that clash most, by their clashes' scores added up, two dry tracks before any
## pair with a return as `clashes` ranks them; empty when none do.
static func worst_pair(spectra: Dictionary, reference := NAN) -> Array:
	var totals := {}
	var wet := {}
	for c: Dictionary in clashes(spectra, reference):
		var key := Vector2i(c["a"], c["b"])
		totals[key] = float(totals.get(key, 0.0)) + float(c["score"])
		wet[key] = c["wet"]
	var best := Vector2i.ZERO
	var most := 0.0
	for key: Vector2i in totals:
		var dry_first: bool = best != Vector2i.ZERO and wet[best] and not wet[key]
		if dry_first or (totals[key] > most and (best == Vector2i.ZERO or wet[key] == wet[best])):
			most = totals[key]
			best = key
	return [] if best == Vector2i.ZERO else [best.x, best.y]


# --- the wire ---------------------------------------------------------------------------------

## A band's level as a byte: FLOOR_DB to TOP_DB in 255 steps, 0.4 dB each.
static func to_byte(db: float) -> int:
	return clampi(roundi((db - FLOOR_DB) / (TOP_DB - FLOOR_DB) * 255.0), 0, 255)


static func from_byte(b: int) -> float:
	return FLOOR_DB + float(b) / 255.0 * (TOP_DB - FLOOR_DB)


## `spectra` (track -> bands) as parcels for the wire, each at most PARCEL_BYTES: a track's index
## (two bytes) and a byte a band, track after track.
static func pack(spectra: Dictionary) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var parcel := PackedByteArray()
	var tracks: Array = spectra.keys()
	tracks.sort()
	for t in tracks:
		var bands: PackedFloat32Array = spectra[t]
		if typeof(t) != TYPE_INT or t < 0 or t > 0xffff or bands.size() != BANDS:
			continue
		if parcel.size() + ENTRY_BYTES > PARCEL_BYTES:
			out.append(parcel)
			parcel = PackedByteArray()
		parcel.append(t & 0xff)
		parcel.append(t >> 8)
		for v in bands:
			parcel.append(to_byte(v))
	if not parcel.is_empty():
		out.append(parcel)
	return out


## A parcel back as track -> bands; empty for one that is not a whole number of entries.
static func unpack(parcel: PackedByteArray) -> Dictionary:
	var out := {}
	if parcel.is_empty() or parcel.size() % ENTRY_BYTES != 0 or parcel.size() > PARCEL_BYTES:
		return out
	for at in range(0, parcel.size(), ENTRY_BYTES):
		var t := parcel[at] | (parcel[at + 1] << 8)
		var bands := PackedFloat32Array()
		bands.resize(BANDS)
		for i in BANDS:
			bands[i] = from_byte(parcel[at + 2 + i])
		out[t] = bands
	return out


# --- this machine's -------------------------------------------------------------------------

## Whether track `index` is measured: one that plays its own sound, not a folder (its children's
## sum).
static func measured(index: int) -> bool:
	var t := DAW.state.track(index, false) if DAW.state != null else null
	return t != null and t.folder_depth <= 0


## What the wall says where it has nothing to show, from whether this machine is a guest, whether
## it can measure, and how long ago (ms) a guest last heard its host's (-1 for never); empty where
## there is something to show.
static func reason_for(guest: bool, can_measure: bool, heard_ago: int) -> String:
	if guest:
		return NEED_HOST if heard_ago < 0 or heard_ago > STALE_MSEC else ""
	return "" if can_measure else NEED_ENGINE


func can_measure() -> bool:
	return measure.is_valid() or DAW.can(DAWBackend.Capability.SPECTRA)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if Session.role == Session.Role.GUEST:
		_hold_reference(latest(), now)
		return
	if now >= _next_read:
		_next_read = now + int(1000.0 / READ_HZ)
		_shown = _measure_all() if can_measure() else {}
		_hold_reference(_shown, now)
	if Session.role == Session.Role.HOST and now >= _next_send:
		_next_send = now + int(1000.0 / SEND_HZ)
		if not _shown.is_empty():
			Session.send_spectra(_shown)


## The reference followed: up at once to a louder moment, down at REFERENCE_FALL_DB after it.
func _hold_reference(spectra: Dictionary, now: int) -> void:
	var want := reference_of(spectra)
	var seconds := float(now - _reference_at) / 1000.0 if _reference_at >= 0 else 0.0
	_reference_at = now
	reference = want if want >= reference else maxf(want, reference - REFERENCE_FALL_DB * seconds)


func _measure_all() -> Dictionary:
	var out := {}
	var how := measure
	if not how.is_valid():
		var engine := DAW.backend as GodotBackend
		if engine == null:
			return out
		how = engine.track_spectrum
	for index in DAW.state.track_indices():
		if measured(index):
			out[index] = how.call(index)
	return out


## What this machine shows: track -> bands. Measured here, or the host's as last heard while it is
## fresh; only tracks still in the mix, and measured ones.
func latest() -> Dictionary:
	if Session.role != Session.Role.GUEST:
		return _shown
	if reason() != "":
		return {}
	var out := {}
	for t in Session.spectra:
		if DAW.state != null and DAW.state.tracks.has(t) and measured(t):
			out[t] = Session.spectra[t]
	return out


func reason() -> String:
	var guest := Session.role == Session.Role.GUEST
	var ago := Time.get_ticks_msec() - Session.spectra_heard_msec if Session.spectra_heard_msec >= 0 else -1
	return reason_for(guest, can_measure(), ago)
