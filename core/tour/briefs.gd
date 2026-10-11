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


## Every brief here judges off its flaws (TourFlaws, baked into TourProject.song_for), not off
## `measures`/`targets`: the old per-brief loudness/balance checks stay dead -- the built-in
## engine's limiter sits at -0.3 dB, above any loudness ceiling a brief could set, so a `peak_db`
## check could never pass, and nothing here ever measured the clean band's spread to set a
## target against. The master bus's own two bars are judged a different way now: every brief's
## `crowd` defaults to true, and `Tour` runs `TourMeasure.Ear` live alongside the flaws, judged by
## `TourEar.THRESHOLDS` -- numbers measured by tools/tour_ear.sh, not a target set here. See
## docs/loop_backlog.md's "Tour" section, "The crowd's ear".
static func _build() -> Array[TourBrief]:
	var out: Array[TourBrief] = []

	var levels := TourBrief.new()
	levels.id = &"levels_check"
	levels.title = "Levels Check"
	levels.flavour = "Doors in forty-five. The opener left the desk a mess."
	levels.seconds = 45.0
	levels.measures = []
	levels.targets = {}
	out.append(levels)

	var tone := TourBrief.new()
	tone.id = &"tone_check"
	tone.title = "Tone Check"
	tone.flavour = "Soundcheck's over. Something's still wrong and the room's filling up."
	tone.seconds = 45.0
	tone.measures = []
	tone.targets = {}
	out.append(tone)

	var pocket := TourBrief.new()
	pocket.id = &"pocket_check"
	pocket.title = "Pocket Check"
	pocket.flavour = "The headliner's manager is watching from the wings. Don't embarrass anyone."
	pocket.seconds = 45.0
	pocket.measures = []
	pocket.targets = {}
	out.append(pocket)

	var boss := TourBrief.new()
	boss.id = &"label_exec"
	boss.title = "The Label Exec"
	boss.flavour = "One take. The label's at the back of the room."
	boss.seconds = 60.0
	boss.measures = []
	boss.targets = {}
	boss.is_boss = true
	out.append(boss)

	return out
