class_name RollSettings
extends RefCounted

## Everything the host can set about a Rig Roulette roll. Plain data: `to_dict`/`from_dict` round
## it for the wire and a saved preset, and `from_dict` holds every field to its limits, so a
## guest's or a file's word is never trusted as it comes.

enum Scales { MAJOR_MINOR, MODES, PENTATONIC }
enum Pool { CHARACTER, EVERYTHING, TIME_BASED, DIRTY, CUSTOM }

## The effects a CHARACTER pool draws from (the built-in engine's FXCatalogue kinds); the same
## curated set Tour's own rig roll uses (`TourProject.RIG_FX`).
const CHARACTER_KINDS: Array[StringName] = [&"distortion", &"chorus", &"reverb", &"delay", &"phaser"]
## The kinds the narrower pools draw from. EVERYTHING is not here: it is whatever there is.
const TIME_BASED_KINDS: Array[StringName] = [&"delay", &"reverb", &"chorus", &"phaser"]
const DIRTY_KINDS: Array[StringName] = [&"distortion", &"filter", &"compressor"]
## Every kind the built-in engine has, in the order the wall's KIND row walks them.
const ALL_KINDS: Array[StringName] = [&"eq", &"compressor", &"reverb", &"delay", &"chorus", &"filter",
		&"distortion", &"phaser", &"limiter"]
## The most one kind can weigh in a CUSTOM pool (0 keeps it out).
const WEIGHT_MAX := 3
const COUNT_MIN := 0
const COUNT_MAX := 6
## How far from the last roll's key (in semitones, either way) a new root may land; 0 is anywhere.
const NEAR_MAX := 6
## Re-rolls allowed after the first roll of a visit: -1 as many as it takes, 0 none (the Riff
## Randomizer rule: write the song with what you got).
const REROLLS_MAX := 3
## The tempo wheel: LOCKED leaves the project's own; the others roll a whole number of BPM in range.
const TEMPO_RANGES := [[0, 0], [60, 180], [60, 90], [90, 120], [120, 160]]
## Steps of chaos: 0 leaves every knob where the pedal came, 4 puts them anywhere.
const CHAOS_MAX := 4
const CAP_MIN := 1
const CAP_MAX := 3
const TRACKS_MIN := 2
const TRACKS_MAX := 8

var count := 2
var pool := Pool.CHARACTER
var key_locked := false
## Most pedals one track may take.
var per_track_cap := 1
## No two pedals of the same kind in one roll.
var no_repeats := false
## Which scales a rolled key is drawn from.
var scales := Scales.MAJOR_MINOR
## Roots within this many semitones of the last roll's key only; 0 is any.
var near_semitones := 0
## Roll again off the last roll's seed (when `seed_value` is 0, a fresh one otherwise).
var replay_last := false
var reroll_limit := -1
## How far a landed pedal's knobs are thrown from where they were, in quarters (see CHAOS_MAX).
var chaos := 0
## A CUSTOM pool's kinds and how much each weighs, 0 to WEIGHT_MAX (a kind not here is out).
var weights := {}
## An index of TEMPO_RANGES; 0 is LOCKED.
var tempo_pick := 0
## 0 rolls off fresh randomness; anything else replays: the same seed on the same settings and
## the same open tracks lands the same roll.
var seed_value := 0


func to_dict() -> Dictionary:
	return {"count": count, "pool": int(pool), "key_locked": key_locked, "seed": seed_value,
			"cap": per_track_cap, "no_repeats": no_repeats,
			"scales": int(scales), "near": near_semitones,
			"replay": replay_last, "limit": reroll_limit, "chaos": chaos,
			"tempo": tempo_pick, "weights": weights.duplicate()}


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


## What each kind weighs under `pool`, as a CUSTOM pool would start from it: 1 for the kinds it
## allows, 0 for the rest (EVERYTHING allows all).
static func weights_of(pool: Pool) -> Dictionary:
	var out := {}
	var allowed := ALL_KINDS if pool == Pool.EVERYTHING else kinds_of(pool)
	for k in ALL_KINDS:
		out[String(k)] = 1 if allowed.has(k) else 0
	return out


## A weights dict held to the known kinds and to 0..WEIGHT_MAX.
static func clean_weights(d) -> Dictionary:
	var out := {}
	if d is Dictionary:
		for k in ALL_KINDS:
			if d.has(String(k)):
				out[String(k)] = clampi(int(d[String(k)]), 0, WEIGHT_MAX)
	return out


static func from_dict(d: Dictionary) -> RollSettings:
	var s := RollSettings.new()
	s.count = clampi(int(d.get("count", s.count)), COUNT_MIN, COUNT_MAX)
	s.pool = clampi(int(d.get("pool", s.pool)), 0, Pool.size() - 1) as Pool
	s.key_locked = bool(d.get("key_locked", s.key_locked))
	s.per_track_cap = clampi(int(d.get("cap", s.per_track_cap)), CAP_MIN, CAP_MAX)
	s.no_repeats = bool(d.get("no_repeats", s.no_repeats))
	s.scales = clampi(int(d.get("scales", s.scales)), 0, Scales.size() - 1) as Scales
	s.near_semitones = clampi(int(d.get("near", s.near_semitones)), 0, NEAR_MAX)
	s.replay_last = bool(d.get("replay", s.replay_last))
	s.reroll_limit = clampi(int(d.get("limit", s.reroll_limit)), -1, REROLLS_MAX)
	s.chaos = clampi(int(d.get("chaos", s.chaos)), 0, CHAOS_MAX)
	s.tempo_pick = clampi(int(d.get("tempo", s.tempo_pick)), 0, TEMPO_RANGES.size() - 1)
	s.weights = clean_weights(d.get("weights", {}))
	s.seed_value = maxi(int(d.get("seed", 0)), 0)
	return s
