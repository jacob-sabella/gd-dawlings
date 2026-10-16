class_name RollSettings
extends RefCounted

## Everything the host can set about a Rig Roulette roll. Plain data: `to_dict`/`from_dict` round
## it for the wire and a saved preset, and `from_dict` holds every field to its limits, so a
## guest's or a file's word is never trusted as it comes.

enum Pool { CHARACTER, EVERYTHING, TIME_BASED, DIRTY }

## The effects a CHARACTER pool draws from (the built-in engine's FXCatalogue kinds); the same
## curated set Tour's own rig roll uses (`TourProject.RIG_FX`).
const CHARACTER_KINDS: Array[StringName] = [&"distortion", &"chorus", &"reverb", &"delay", &"phaser"]
## The kinds the narrower pools draw from. EVERYTHING is not here: it is whatever there is.
const TIME_BASED_KINDS: Array[StringName] = [&"delay", &"reverb", &"chorus", &"phaser"]
const DIRTY_KINDS: Array[StringName] = [&"distortion", &"filter", &"compressor"]
const COUNT_MIN := 1
const COUNT_MAX := 3
const TRACKS_MIN := 2
const TRACKS_MAX := 8

var count := 2
var pool := Pool.CHARACTER
var key_locked := false
## 0 rolls off fresh randomness; anything else replays: the same seed on the same settings and
## the same open tracks lands the same roll.
var seed_value := 0


func to_dict() -> Dictionary:
	return {"count": count, "pool": int(pool), "key_locked": key_locked, "seed": seed_value}


## The kinds a pool allows, or empty for EVERYTHING.
static func kinds_of(pool: Pool) -> Array[StringName]:
	match pool:
		Pool.CHARACTER:
			return CHARACTER_KINDS
		Pool.TIME_BASED:
			return TIME_BASED_KINDS
		Pool.DIRTY:
			return DIRTY_KINDS
	return []


static func from_dict(d: Dictionary) -> RollSettings:
	var s := RollSettings.new()
	s.count = clampi(int(d.get("count", s.count)), COUNT_MIN, COUNT_MAX)
	s.pool = clampi(int(d.get("pool", s.pool)), 0, Pool.size() - 1) as Pool
	s.key_locked = bool(d.get("key_locked", s.key_locked))
	s.seed_value = maxi(int(d.get("seed", 0)), 0)
	return s
