class_name TourBriefs
extends RefCounted

## Tour's one venue, first version: three briefs and a boss, built once.
##
## GDScript cannot initialise an `Array[TourBrief]` of constructed objects as a const at parse
## time, so `all()` builds the list on first call and keeps it in a static holder -- the nearest
## thing to a cached static field GDScript allows.

static var _cached: Array[TourBrief] = []


static func all() -> Array[TourBrief]:
	if _cached.is_empty():
		_cached = _build()
	return _cached


static func brief(index: int) -> TourBrief:
	var list := all()
	return list[clampi(index, 0, list.size() - 1)]


static func count() -> int:
	return all().size()


static func _build() -> Array[TourBrief]:
	var out: Array[TourBrief] = []

	var levels := TourBrief.new()
	levels.id = &"levels_check"
	levels.title = "Levels Check"
	levels.flavour = "The room's waiting. Keep it hot, but keep it clean."
	levels.seconds = 45.0
	levels.measures = [&"loudness"]
	levels.targets = {"loudness_min_db": -16.0, "loudness_max_db": -10.0, "loudness_peak_max_db": -1.0}
	out.append(levels)

	var tone := TourBrief.new()
	tone.id = &"tone_check"
	tone.title = "Tone Check"
	tone.flavour = "Nothing buried, nothing screaming. Keep it even across the board."
	tone.seconds = 45.0
	tone.measures = [&"balance"]
	tone.targets = {"balance_spread_max_db": 8.0}
	out.append(tone)

	var pocket := TourBrief.new()
	pocket.id = &"pocket_check"
	pocket.title = "Pocket Check"
	pocket.flavour = "Right on the grid. Nobody rushing, nobody dragging."
	pocket.seconds = 45.0
	pocket.measures = [&"timing"]
	pocket.targets = {"timing_mean_max_beats": 0.12, "timing_worst_max_beats": 0.30}
	out.append(pocket)

	var boss := TourBrief.new()
	boss.id = &"label_exec"
	boss.title = "The Label Exec"
	boss.flavour = "One shot. Hit it clean, or they walk."
	boss.seconds = 60.0
	boss.measures = [&"loudness", &"balance", &"timing"]
	boss.targets = {
		"loudness_min_db": -14.0, "loudness_max_db": -12.0, "loudness_peak_max_db": -2.0,
		"balance_spread_max_db": 5.0,
		"timing_mean_max_beats": 0.08, "timing_worst_max_beats": 0.18,
	}
	boss.is_boss = true
	out.append(boss)

	return out
