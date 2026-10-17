class_name RollPresets
extends RefCounted

## Saved sets of Rig Roulette settings: three that ship, and a few slots the host fills from the
## wall. Plain data (`RollSettings.to_dict`), kept in a file of their own. A preset never carries
## a seed: it says how to roll, not which roll.

const PATH := "user://roll_presets.cfg"
const SLOTS := 3

## name -> settings, in the order the wall lists them.
static func built_in() -> Array:
	var riff := RollSettings.new()
	riff.count = 2
	riff.reroll_limit = 0
	var gentle := RollSettings.new()
	gentle.count = 1
	gentle.pool = RollSettings.Pool.TIME_BASED
	gentle.scales = RollSettings.Scales.MAJOR_MINOR
	gentle.near_semitones = 2
	gentle.reroll_limit = 2
	var chaos := RollSettings.new()
	chaos.count = 5
	chaos.pool = RollSettings.Pool.EVERYTHING
	chaos.per_track_cap = 2
	chaos.scales = RollSettings.Scales.MODES
	chaos.chaos = RollSettings.CHAOS_MAX
	chaos.tempo_pick = 1
	return [["RIFF RANDOMIZER", riff.to_dict()], ["GENTLE", gentle.to_dict()], ["CHAOS", chaos.to_dict()]]


## The words a settings dict is known by when nobody could type a name: "3 DIRTY PEDALS, PENTATONIC".
static func name_of(d: Dictionary) -> String:
	var s := RollSettings.from_dict(d)
	var pool: String = ["CHARACTER", "ANY", "TIME-BASED", "DIRTY"][s.pool]
	var scale: String = ["", ", ANY MODE", ", PENTATONIC"][s.scales]
	return "%d %s PEDAL%s%s%s" % [s.count, pool, "" if s.count == 1 else "S", scale,
			", CHAOS" if s.chaos > 0 else ""]


## The saved slots, SLOTS long, each a settings dict or {} when empty.
static func saved(path := PATH) -> Array:
	var out: Array = []
	var cfg := ConfigFile.new()
	cfg.load(path)
	for i in SLOTS:
		var d = cfg.get_value("slots", str(i), {})
		out.append(RollSettings.from_dict(d).to_dict() if d is Dictionary and not d.is_empty() else {})
	return out


## Keep `settings` in the first empty slot, or the oldest when all are full (the slots turn like a
## queue). Returns the slot it went into.
static func save(settings: RollSettings, path := PATH) -> int:
	var slots := saved(path)
	var at := -1
	for i in SLOTS:
		if slots[i].is_empty():
			at = i
			break
	var cfg := ConfigFile.new()
	cfg.load(path)
	if at < 0:
		at = int(cfg.get_value("meta", "next", 0)) % SLOTS
	var d := settings.to_dict()
	d["seed"] = 0
	cfg.set_value("slots", str(at), d)
	cfg.set_value("meta", "next", (at + 1) % SLOTS)
	cfg.save(path)
	return at
