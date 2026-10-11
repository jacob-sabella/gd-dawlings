class_name TourFlaws
extends RefCounted

## The flaw catalogue: six things that can be wrong with a brief's rescue song, drawn for a run
## the way TourDeck draws a draft -- shaped the same way, a static holder and a seeded `draw`.
##
## Five flaws are judged off the desk's own replicated numbers (`volume_db`, `mute`, `pan`,
## `fx[].params`/`enabled`, `tempo`), which every DAW verb already writes and which are exact
## headless. `dragging_keys` reuses the existing Timing measure with a quarter-beat grid instead:
## a quantised lane reads 0.0 beats off, where the eighth-grid default could never fail at all
## (see measure.gd). None of the six reads the master bus -- that is the crowd's job now
## (TourEar, off TourMeasure.Ear, judged live by `Tour` alongside these), not a per-strip flaw's;
## see docs/loop_backlog.md's "Tour" section, "The crowd's ear", for how it was calibrated.

const TEMPOS := [84.0, 92.0, 100.0, 108.0, 116.0, 124.0]
const LATE_BEATS := 0.22
const TEMPO_KICK_BPM := 16.0
## The desk's name for the built-in engine's EQ (FXCatalogue's `eq` kind): the one plugin the
## muddy-bass flaw bakes, and the only one it judges.
const EQ_NAME := "EQ6"

static var _cached: Array[TourFlaw] = []


static func all() -> Array[TourFlaw]:
	if _cached.is_empty():
		_cached = _build()
	return _cached


static func by_id(id: StringName) -> TourFlaw:
	for f in all():
		if f.id == id:
			return f
	return null


## 1 flaw solo, 2 for 2-3 players, 3 for 4-5, 4 for 6-8; the boss adds one more; capped at 5,
## one short of the whole catalogue, since one pair (`wrong_tempo`/`dragging_keys`) can never
## both be drawn.
static func count_for(band_size: int, is_boss: bool) -> int:
	var n := 1 if band_size <= 1 else 2 if band_size <= 3 else 3 if band_size <= 5 else 4
	return mini(n + (1 if is_boss else 0), all().size() - 1)


static func tempo_for(rng: RandomNumberGenerator) -> float:
	return TEMPOS[rng.randi_range(0, TEMPOS.size() - 1)]


## `count` flaws, never two that exclude each other: `all()` shuffled with `rng`, walked in
## order, each one skipped if it excludes (or is excluded by) one already picked.
static func draw(rng: RandomNumberGenerator, count: int) -> Array[TourFlaw]:
	var pool := all().duplicate()
	_shuffle(pool, rng)
	var picked: Array[TourFlaw] = []
	for f in pool:
		if picked.size() >= count:
			break
		var blocked := picked.any(func(p: TourFlaw) -> bool:
			return f.id in p.excludes or p.id in f.excludes)
		if not blocked:
			picked.append(f)
	return picked


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## The rescue track named `name` in a project being baked, or null.
static func _dk_track_named(p: DawKitProject, track_name: String) -> DawKitTrack:
	for t in p.tracks:
		if t.name == track_name:
			return t
	return null


## The rescue track named `name` on the live desk, or null.
static func _track_named(state: MixState, track_name: String) -> MixState.TrackState:
	for index in state.track_indices():
		var t: MixState.TrackState = state.tracks[index]
		if t.name == track_name:
			return t
	return null


## Whether `track_name`'s EQ (EQ_NAME, in whichever slot) is clean -- no band past +3 dB on one
## that is in the chain and switched on. `muddy_bass`'s own judge, and `plugin_haywire`'s (a
## chaos event, core/tour/tour_chaos.gd): one plugin, one test, read in both places rather than
## kept honest twice by eye. A track with none, or that no longer exists, is clean.
static func eq_clean(state: MixState, track_name: String) -> bool:
	var t := TourFlaws._track_named(state, track_name)
	if t == null:
		return true
	for fx_index in t.fx:
		var f: MixState.FXState = t.fx[fx_index]
		if not f.enabled or f.name != EQ_NAME:
			continue
		for v in f.params.values():
			if float(v) > 0.6:
				return false
	return true


static func _build() -> Array[TourFlaw]:
	var out: Array[TourFlaw] = []

	var quiet_vox := TourFlaw.new()
	quiet_vox.id = &"quiet_vox"
	quiet_vox.line = "The lead vocal is buried. Nobody can hear a word."
	quiet_vox.track = "Lead Vox"
	quiet_vox._bake = func(p: DawKitProject, _rng: RandomNumberGenerator, _tempo: float) -> void:
		var t := TourFlaws._dk_track_named(p, "Lead Vox")
		if t != null:
			t.volume_db = -24.0
	quiet_vox._fixed = func(state: MixState, _run: TourRun) -> bool:
		var t := TourFlaws._track_named(state, "Lead Vox")
		return t != null and not t.mute and t.volume_db >= -6.0 and t.volume_db <= 3.0
	out.append(quiet_vox)

	var muddy_bass := TourFlaw.new()
	muddy_bass.id = &"muddy_bass"
	muddy_bass.line = "The bass is a mudslide. Something is pumping the lows."
	muddy_bass.track = "Bass DI"
	muddy_bass._bake = func(p: DawKitProject, _rng: RandomNumberGenerator, _tempo: float) -> void:
		var t := TourFlaws._dk_track_named(p, "Bass DI")
		if t == null:
			return
		var eq := DawKitEffect.new()
		eq.kind = "eq"
		eq.name = EQ_NAME
		eq.enabled = true
		# [32 Hz, 100 Hz, 320 Hz, 1 kHz, 3.2 kHz, 10 kHz], normalised 0.5 = 0 dB: +15 dB on the
		# two lowest bands, everything else left flat.
		eq.values = [1.0, 1.0, 0.5, 0.5, 0.5, 0.5]
		t.effects.append(eq)
	# Judged on the bass's EQs alone -- any band still boosted past +3 dB on an EQ that is in the
	# chain and switched on. Not every plugin's every knob: a compressor the band drops on the
	# bass has a threshold that sits above 0.6 by default, and must not read as mud.
	muddy_bass._fixed = func(state: MixState, _run: TourRun) -> bool:
		return TourFlaws.eq_clean(state, "Bass DI")
	out.append(muddy_bass)

	var dragging_keys := TourFlaw.new()
	dragging_keys.id = &"dragging_keys"
	dragging_keys.line = "The keys player is dragging. Every stab lands late."
	dragging_keys.track = "Keys"
	dragging_keys._bake = func(p: DawKitProject, _rng: RandomNumberGenerator, tempo: float) -> void:
		var t := TourFlaws._dk_track_named(p, "Keys")
		if t == null or t.clips.is_empty():
			return
		t.clips[0].notes = TourProject.stab_notes(tempo, TourProject.BARS, LATE_BEATS)
	# The current DAW.state, not the `state` argument, because the Timing measure it rides reads
	# the global transport's placed notes, not a snapshot handed to it; every caller of `fixed`
	# in Tour passes DAW.state anyway, so the two are the same object every time this runs.
	dragging_keys._fixed = func(_state: MixState, run: TourRun) -> bool:
		var timing := TourMeasure.Timing.new()
		timing.start(Tour.TIMING_TRACK, 0.0, 1.0)
		var r := timing.result()
		var notes := int(r.get("notes", 0))
		var avg: float = r.get("avg_beats_off", 1.0)
		var worst: float = r.get("worst_beats_off", 1.0)
		return notes > 0 and avg <= 0.06 * run.tempo_tolerance_mult and worst <= 0.10 * run.tempo_tolerance_mult
	out.append(dragging_keys)

	var muted_rhodes := TourFlaw.new()
	muted_rhodes.id = &"muted_rhodes"
	muted_rhodes.line = "The Rhodes is muted. The chords are gone."
	muted_rhodes.track = "Rhodes"
	muted_rhodes._bake = func(p: DawKitProject, _rng: RandomNumberGenerator, _tempo: float) -> void:
		var t := TourFlaws._dk_track_named(p, "Rhodes")
		if t != null:
			t.mute = true
	muted_rhodes._fixed = func(state: MixState, _run: TourRun) -> bool:
		var t := TourFlaws._track_named(state, "Rhodes")
		return t != null and not t.mute and t.volume_db >= -12.0
	out.append(muted_rhodes)

	var hard_pan := TourFlaw.new()
	hard_pan.id = &"hard_pan"
	hard_pan.line = "The guitar is jammed hard to one side. One ear's worth of band."
	hard_pan.track = "Gtr Amp"
	hard_pan._bake = func(p: DawKitProject, rng: RandomNumberGenerator, _tempo: float) -> void:
		var t := TourFlaws._dk_track_named(p, "Gtr Amp")
		if t != null:
			t.pan = -1.0 if rng.randf() < 0.5 else 1.0
	hard_pan._fixed = func(state: MixState, _run: TourRun) -> bool:
		var t := TourFlaws._track_named(state, "Gtr Amp")
		return t != null and t.pan >= 0.35 and t.pan <= 0.65
	out.append(hard_pan)

	var wrong_tempo := TourFlaw.new()
	wrong_tempo.id = &"wrong_tempo"
	wrong_tempo.line = "Someone kicked the deck. The setlist says %d BPM."
	wrong_tempo.track = ""
	wrong_tempo.excludes = [&"dragging_keys"]
	wrong_tempo._bake = func(p: DawKitProject, rng: RandomNumberGenerator, song_tempo: float) -> void:
		p.tempo = song_tempo + (TEMPO_KICK_BPM if rng.randf() < 0.5 else -TEMPO_KICK_BPM)
	wrong_tempo._fixed = func(state: MixState, run: TourRun) -> bool:
		return absf(state.tempo - run.song_tempo) <= 3.0
	out.append(wrong_tempo)

	return out
