class_name TourChaos
extends RefCounted

## The chaos catalogue and its seeded schedule: rare, loud, telegraphed, survivable trouble mid-
## brief, on top of a brief's flaws -- see core/tour/tour_chaos_event.gd for one event's shape
## and core/tour/tour.gd's `_tick_chaos`/`_tick_chaos_shown` for the clock that drives it.
##
## Shaped like TourFlaws -- a static holder, a seeded `draw` -- plus the scheduling TourFlaws
## never needed: a flaw is drawn once and is just fixed or not; an event also has to say WHEN it
## strikes, so `schedule` lives here and nowhere else.

## 1.5-2 s of warning asked for by the design; the sounds and the rattle take about this long to
## read, so the strike lands right as the telegraph finishes rather than stepping on it.
const TELEGRAPH_SECONDS := 2.0
## Never in the first 10 s of a brief...
const FIRST_SECONDS := 10.0
## ...nor the last 8.
const LAST_SECONDS := 8.0
## Two strikes in the same brief never land closer together than this.
const GAP_SECONDS := 8.0
const LIGHTS_OUT_BARS := 1
## `tempo_lurch`'s kick, in BPM either way -- 14, not `TourFlaws.TEMPO_KICK_BPM`'s 16, so a test
## (or a player who has played both) can tell the two apart.
const TEMPO_LURCH_BPM := 14.0

enum State { PENDING, TELEGRAPHED, STRUCK, RECOVERED }

static var _cached: Array[TourChaosEvent] = []


static func all() -> Array[TourChaosEvent]:
	if _cached.is_empty():
		_cached = _build()
	return _cached


static func by_id(id: StringName) -> TourChaosEvent:
	for e in all():
		if e.id == id:
			return e
	return null


## Never on brief 0, however big the band: a first brief is where a run learns its own flaws,
## not where it also learns chaos exists. After that: 1-2 players see one six tries in ten, 3-5
## always one and sometimes a second, 6-8 two and sometimes a third; the boss brief adds one
## more on top, capped at how many events there are to draw at all.
static func count_for(band_size: int, brief_index: int, is_boss: bool, rng: RandomNumberGenerator) -> int:
	if brief_index <= 0:
		return 0
	var n := 0
	if band_size <= 2:
		n = 1 if rng.randf() < 0.6 else 0
	elif band_size <= 5:
		n = 1 if rng.randf() < 0.5 else 2
	else:
		n = 2 if rng.randf() < 0.5 else 3
	if is_boss:
		n += 1
	return mini(n, all().size())


## `count` strike times in [FIRST_SECONDS, total - LAST_SECONDS], each at least GAP_SECONDS from
## every other, sorted ascending. Rejection-sampled, 40 tries per event: a short clock (a
## shorter_clock card's 0.75x) can honestly come back with fewer than asked rather than cheat the
## gap, but never with two closer together than it.
static func schedule(rng: RandomNumberGenerator, count: int, total_seconds: float) -> Array[float]:
	var out: Array[float] = []
	var lo := FIRST_SECONDS
	var hi := total_seconds - LAST_SECONDS
	if count <= 0 or hi <= lo:
		return out
	var tries := 0
	while out.size() < count and tries < 40:
		tries += 1
		var t := rng.randf_range(lo, hi)
		var ok := true
		for s in out:
			if absf(s - t) < GAP_SECONDS:
				ok = false
				break
		if ok:
			out.append(t)
	out.sort()
	return out


## `count` events, shuffled with `rng`, skipping any whose `excludes_flaws` meets `flaws` (this
## brief's own flaw ids) -- never the same id twice in one brief, `all()` having none repeated.
static func draw(rng: RandomNumberGenerator, count: int, flaws: Array[StringName]) -> Array[TourChaosEvent]:
	var pool := all().duplicate()
	_shuffle(pool, rng)
	var picked: Array[TourChaosEvent] = []
	for e in pool:
		if picked.size() >= count:
			break
		var blocked: bool = e.excludes_flaws.any(func(fid: StringName) -> bool: return fid in flaws)
		if not blocked:
			picked.append(e)
	return picked


## A sounding rescue track by index: not Stage, not Keys, not muted, not named in
## `excluded_names` (this brief's own flaw tracks, plus an event's own `extra_track_excludes`).
static func pick_track(rng: RandomNumberGenerator, state: MixState, excluded_names: Array[String]) -> int:
	var candidates: Array[int] = []
	for index in state.track_indices():
		if index == Tour.STAGE_TRACK or index == Tour.TIMING_TRACK:
			continue
		var t: MixState.TrackState = state.tracks[index]
		if t.mute or t.name in excluded_names:
			continue
		candidates.append(index)
	if candidates.is_empty():
		return 0
	candidates.sort()
	return candidates[rng.randi() % candidates.size()]


## `tempo_lurch` has no strip of its own -- its slot in `run.event_track` holds this instead,
## +1 or -1, the direction the deck's belt slips.
static func pick_sign(rng: RandomNumberGenerator) -> int:
	return 1 if rng.randf() < 0.5 else -1


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## The six, each a chaos event's own strike (DAW verbs only) and the room control that undoes
## it -- see docs/loop_backlog.md's "Tour" section for the full table.
static func _build() -> Array[TourChaosEvent]:
	var out: Array[TourChaosEvent] = []

	var power_flicker := TourChaosEvent.new()
	power_flicker.id = &"power_flicker"
	power_flicker.telegraph = "DECK: The power's browning out. Hold on to something."
	power_flicker.line = "%s is dead. MUTE off."
	power_flicker.wants_track = true
	power_flicker._strike = func(_run: TourRun, track_index: int) -> void:
		DAW.set_track_mute(track_index, true)
	power_flicker._recovered = func(state: MixState, _run: TourRun, track_index: int) -> bool:
		var t := state.track(track_index, false)
		return t == null or not t.mute
	out.append(power_flicker)

	var solo_leaned := TourChaosEvent.new()
	solo_leaned.id = &"solo_leaned"
	solo_leaned.telegraph = "KICK: Somebody's leaning on SOLO. Get them off it."
	solo_leaned.line = "Only %s is getting through. SOLO off."
	solo_leaned.wants_track = true
	solo_leaned._strike = func(_run: TourRun, track_index: int) -> void:
		DAW.set_track_solo(track_index, true)
	solo_leaned._recovered = func(state: MixState, _run: TourRun, _track_index: int) -> bool:
		for index in state.track_indices():
			if state.tracks[index].solo:
				return false
		return true
	out.append(solo_leaned)

	var stage_unplugged := TourChaosEvent.new()
	stage_unplugged.id = &"stage_unplugged"
	stage_unplugged.telegraph = "STAGE: The stage box is working loose. Somebody check the cable."
	stage_unplugged.line = "Nothing's landing on Stage. REC arm it again."
	stage_unplugged.wants_track = false
	stage_unplugged._strike = func(_run: TourRun, _track_index: int) -> void:
		DAW.set_track_rec_arm(Tour.STAGE_TRACK, false)
	stage_unplugged._recovered = func(state: MixState, _run: TourRun, _track_index: int) -> bool:
		var t := state.track(Tour.STAGE_TRACK, false)
		return t == null or t.rec_arm
	out.append(stage_unplugged)

	var crowd_throws := TourChaosEvent.new()
	crowd_throws.id = &"crowd_throws"
	crowd_throws.telegraph = "HOUSE: Incoming. The crowd's throwing things."
	crowd_throws.line = "Something hit the desk. The %s fader's on the floor."
	crowd_throws.wants_track = true
	crowd_throws._strike = func(_run: TourRun, track_index: int) -> void:
		DAW.set_track_volume(track_index, DAW.db_to_taper(-30.0))
	crowd_throws._recovered = func(state: MixState, _run: TourRun, track_index: int) -> bool:
		var t := state.track(track_index, false)
		return t != null and t.volume_db >= -12.0 and t.volume_db <= 3.0
	out.append(crowd_throws)

	var plugin_haywire := TourChaosEvent.new()
	plugin_haywire.id = &"plugin_haywire"
	plugin_haywire.telegraph = "%s: A plugin's gone haywire. Kill it or flatten it."
	plugin_haywire.line = "%s: that plugin is still screaming. Bypass it, flatten it, or pull it."
	plugin_haywire.wants_track = true
	plugin_haywire.extra_track_excludes = ["Bass DI"]
	plugin_haywire._strike = func(_run: TourRun, track_index: int) -> void:
		# The built-in engine's own EQ (FXCatalogue's &"eq" kind, GodotBackend.add_fx): the one
		# plugin this strikes and the one muddy_bass bakes, so the two are judged by the same
		# TourFlaws.eq_clean. "eq" is the catalogue KIND add_fx takes, not TourFlaws.EQ_NAME
		# ("EQ6"), which is the display name the row comes back with.
		DAW.add_fx(track_index, "eq", -1)
		var t := DAW.state.track(track_index, false)
		if t == null or t.fx.is_empty():
			return
		var fx_index: int = t.fx.size() - 1
		DAW.set_fx_param(track_index, fx_index, 0, 1.0)
		DAW.set_fx_param(track_index, fx_index, 1, 1.0)
	plugin_haywire._recovered = func(state: MixState, _run: TourRun, track_index: int) -> bool:
		var t := state.track(track_index, false)
		return t == null or TourFlaws.eq_clean(state, t.name)
	out.append(plugin_haywire)

	var tempo_lurch := TourChaosEvent.new()
	tempo_lurch.id = &"tempo_lurch"
	tempo_lurch.telegraph = "DECK: The deck's belt is slipping. Grab the tempo."
	tempo_lurch.line = "The tempo's miles off the setlist. Grab it back."
	tempo_lurch.wants_track = false
	tempo_lurch.excludes_flaws = [&"wrong_tempo", &"dragging_keys"]
	tempo_lurch._strike = func(run: TourRun, track_index: int) -> void:
		# No strip of its own: `track_index` here is the sign this run's own draw picked
		# (+1/-1, `pick_sign`), stored in the same `event_track` slot a strip's index would
		# otherwise ride in -- see TourChaosEvent.wants_track's doc.
		DAW.set_tempo(run.song_tempo + TEMPO_LURCH_BPM * (1.0 if track_index >= 0 else -1.0))
	tempo_lurch._recovered = func(state: MixState, run: TourRun, _track_index: int) -> bool:
		return absf(state.tempo - run.song_tempo) <= 3.0
	out.append(tempo_lurch)

	return out
