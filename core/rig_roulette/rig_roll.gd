class_name RigRoll
extends RefCounted

## A Rig Roulette roll worked out, not applied: how many tracks the new project has, which of
## them get which effect, and the key. The caller starts the project and puts the effects on, so
## this is the same for any engine and can be replayed from a seed.

const KEY_NAMES := ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]


## The generator for a roll: seeded when the settings carry a seed, fresh otherwise.
static func rng_for(settings: RollSettings) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	if settings.seed_value != 0:
		rng.seed = settings.seed_value
	else:
		rng.randomize()
	return rng


## How many tracks the new project starts with.
static func track_count(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(RollSettings.TRACKS_MIN, RollSettings.TRACKS_MAX)


## `tracks` are the new project's track indices, `pool` the effects it may land
## ([plugin, label] pairs, as `fx_choices` gives them). Returns {"pedals": [{track, plugin}], "key": String}
## ("" when the key is locked). `rng` carries on from `track_count`.
static func plan(settings: RollSettings, rng: RandomNumberGenerator, tracks: Array, pool: Array) -> Dictionary:
	var eligible := tracks.duplicate()
	for i in range(eligible.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = eligible[i]
		eligible[i] = eligible[j]
		eligible[j] = tmp
	# Each track's turn comes round once per pedal it may take: the shuffled order, then again.
	var slots: Array = []
	for _round in settings.per_track_cap:
		slots.append_array(eligible)
	var pedals: Array = []
	var used := {}
	for i in mini(settings.count, slots.size()):
		var from := pool
		if settings.no_repeats:
			from = pool.filter(func(c): return not used.has(str(c[0])))
		if from.is_empty():
			break
		var plugin := str(from[rng.randi() % from.size()][0])
		used[plugin] = true
		pedals.append({"track": slots[i], "plugin": plugin})
	var key := ""
	if not settings.key_locked:
		key = "%s %s" % [KEY_NAMES[rng.randi() % KEY_NAMES.size()], "major" if rng.randi() % 2 == 0 else "minor"]
	return {"pedals": pedals, "key": key}


## The pool a roll draws from: CHARACTER, TIME_BASED and DIRTY keep their own kinds of `choices`; EVERYTHING, or any
## pool when the engine's list carries no kind to filter by (`kinds_known` false), is all of it.
static func pool_of(settings: RollSettings, choices: Array, kinds_known: bool) -> Array:
	if not kinds_known or settings.pool == RollSettings.Pool.EVERYTHING:
		return choices
	var kinds := {}
	for k in RollSettings.kinds_of(settings.pool):
		kinds[String(k)] = true
	return choices.filter(func(c): return kinds.has(String(c[0])))
