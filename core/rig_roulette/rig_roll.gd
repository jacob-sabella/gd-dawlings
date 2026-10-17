class_name RigRoll
extends RefCounted

## A Rig Roulette roll worked out, not applied: how many tracks the new project has, which of
## them get which effect, and the key. The caller starts the project and puts the effects on, so
## this is the same for any engine and can be replayed from a seed.

const KEY_NAMES := ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
const MODES := ["major", "dorian", "phrygian", "lydian", "mixolydian", "minor", "locrian"]
const PENTATONICS := ["major pentatonic", "minor pentatonic", "blues"]


## The scale names a pool draws from.
static func scale_names(scales: RollSettings.Scales) -> Array:
	match scales:
		RollSettings.Scales.MODES:
			return MODES
		RollSettings.Scales.PENTATONIC:
			return PENTATONICS
	return ["major", "minor"]


## The root's index in KEY_NAMES out of a key's name ("D minor"), or -1.
static func root_of(key: String) -> int:
	return KEY_NAMES.find(key.get_slice(" ", 0))


## The seed a roll runs off, so it can always be replayed: the settings' own, else the last roll's
## when replaying, else a fresh one. Never 0.
static func seed_for(settings: RollSettings, last_seed: int) -> int:
	if settings.seed_value != 0:
		return settings.seed_value
	if settings.replay_last and last_seed != 0:
		return last_seed
	return randi_range(1, 99999)


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
## ([plugin, label] pairs, as `fx_choices` gives them). `last_key` is the key the last roll named, for a NEAR roll. Returns {"pedals": [{track, plugin}], "key": String}
## ("" when the key is locked). `rng` carries on from `track_count`.
static func plan(settings: RollSettings, rng: RandomNumberGenerator, tracks: Array, pool: Array,
		last_key := "") -> Dictionary:
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
		var roots := range(KEY_NAMES.size())
		var last := root_of(last_key)
		if settings.near_semitones > 0 and last >= 0:
			roots = roots.filter(func(r): return mini(posmod(r - last, 12), posmod(last - r, 12)) <= settings.near_semitones)
		var names := scale_names(settings.scales)
		var root: int = roots[rng.randi() % roots.size()]
		key = "%s %s" % [KEY_NAMES[root], names[rng.randi() % names.size()]]
	return {"pedals": pedals, "key": key}


## Where a knob lands: `current` moved toward a random position by the chaos (0 leaves it,
## `CHAOS_MAX` is anywhere). Always 0..1.
static func knob(rng: RandomNumberGenerator, current: float, chaos: int) -> float:
	var throw := rng.randf()
	if chaos <= 0:
		return current
	return clampf(lerpf(current, throw, float(chaos) / float(RollSettings.CHAOS_MAX)), 0.0, 1.0)


## The pool a roll draws from: CHARACTER, TIME_BASED and DIRTY keep their own kinds of `choices`; EVERYTHING, or any
## pool when the engine's list carries no kind to filter by (`kinds_known` false), is all of it.
static func pool_of(settings: RollSettings, choices: Array, kinds_known: bool) -> Array:
	if not kinds_known or settings.pool == RollSettings.Pool.EVERYTHING:
		return choices
	var kinds := {}
	for k in RollSettings.kinds_of(settings.pool):
		kinds[String(k)] = true
	return choices.filter(func(c): return kinds.has(String(c[0])))
