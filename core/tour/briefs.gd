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
## `measures`/`targets`: the master bus's own two bars are off until they are calibrated. The
## built-in engine's limiter sits at -0.3 dB, above every loudness ceiling a brief could set, so
## the levels check could never pass; the balance check's spread has never been measured clean,
## so there is nothing to set its target against. Both come back once a probe flag measures the
## clean band through the real bus -- see docs/loop_backlog.md's "Tour" section.
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
