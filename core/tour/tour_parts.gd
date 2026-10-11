class_name TourParts
extends RefCounted

## The part catalogue: jobs a brief hands out, one per player, played rather than mixed -- a
## backbeat, a pulse of eighths, a stab on the one (see core/tour/tour_part.gd). Shaped like
## TourFlaws -- a static holder, a seeded `draw` -- except a part is also held by someone
## (`assign`, and the leaving/grace handling below), where a flaw is just fixed or not.
##
## One copy of each instrument exists in the room (core/items/item_room.gd's KINDS: one shaker,
## one tambourine, one keytar), so at most INSTRUMENTS players can hold a note-making part today;
## the rest of a big band stays on flaws. A second copy of each, and a sing part on the mic's
## audio take, are backlog ideas -- see docs/loop_backlog.md's "Tour" section.

## One part per instrument there is to hold. The boss brief does not raise this: there is
## nothing more in the room to give a ninth, tenth... job to.
const INSTRUMENTS := 3
## How long an open part (nobody holding it, or whoever did has left) sits before it is handed
## to whoever on the roster holds the fewest parts right now.
const PART_GRACE := 8.0

## The room's own three, always there: INSTRUMENTS == ROOM.size().
const ROOM: Array[StringName] = [&"shaker", &"tambourine", &"keytar"]
## Kinds a draft card can still spill out of the case, each with two voices (`COPIES`) -- see
## docs/loop_backlog.md's "Tour" section for why two: the judge tells parts apart by
## (channel, pitch), so a second copy of a kind needs its own pitch to be a job rather than a
## decoy, and a second voice ("the low one") is where that pitch comes from.
const SPILL_KINDS: Array[StringName] = [&"cowbell", &"woodblock", &"pad", &"triangle", &"claves", &"hihat"]
const COPIES := 2

static var _cached: Array[TourPart] = []


## The id of the `n`th copy of `kind` out of the case: 0 is the kind's own id, 1 is "the low
## one", named by appending its one-based voice number.
static func instance_id(kind: StringName, n: int) -> StringName:
	return kind if n == 0 else StringName(String(kind) + str(n + 1))


## The kind a spilled instance's own id names, its voice number stripped off.
static func kind_of(id: StringName) -> StringName:
	return StringName(String(id).rstrip("0123456789"))


## How many copies of `kind` have already been spilled, by its instance ids in `spilled`
## (`TourRun.instruments`).
static func copies_of(kind: StringName, spilled: Array[StringName]) -> int:
	var n := 0
	for id in spilled:
		if kind_of(id) == kind:
			n += 1
	return n


## What a big band's first brief already has out of the case, so it starts with enough to do
## rather than spending its whole first brief on flaws alone: `clampi(band_size - ROOM.size(),
## 0, SPILL_KINDS.size())` kinds, drawn from `SPILL_KINDS` shuffled with `rng` -- band 4 gets
## one, 5 gets two, 6 gets three, 7 gets four, 8 (the biggest band there is) gets five of the six
## -- never all of them, now that the catalogue has outgrown what an 8-person first brief can
## draw; 3 and under, none (the room's own three already cover them).
static func first_spill(rng: RandomNumberGenerator, band_size: int) -> Array[StringName]:
	var n := clampi(band_size - ROOM.size(), 0, SPILL_KINDS.size())
	var pool := SPILL_KINDS.duplicate()
	_shuffle(pool, rng)
	return pool.slice(0, n)


static func all() -> Array[TourPart]:
	if _cached.is_empty():
		_cached = _build()
	return _cached


static func by_id(id: StringName) -> TourPart:
	for p in all():
		if p.id == id:
			return p
	return null


## Solo and a duo get one part each to hold, one job at a time, so a run alone or with a friend
## stays winnable; three and up, one part per instrument there is to hold -- the room's own
## three by default, or more once `available` (TourRun.instruments, added to ROOM at the call
## site) says the case has spilled some. `is_boss` changes nothing -- there being nothing more
## to hand a fourth, ninth... job to beyond what is actually in the room -- but is kept so this
## reads the same as TourFlaws.count_for at the call site.
static func count_for(band_size: int, _is_boss: bool, available: int = INSTRUMENTS) -> int:
	return mini(maxi(band_size, 1), available)


## `count` parts, never two on the same instance (there being only one of each to hold):
## `all()` filtered to instruments in `available`, shuffled with `rng`, walked in order, each
## one skipped once its instrument is taken.
static func draw(rng: RandomNumberGenerator, count: int, available: Array[StringName] = ROOM) -> Array[TourPart]:
	var pool := all().filter(func(p: TourPart) -> bool: return p.instrument in available)
	_shuffle(pool, rng)
	var picked: Array[TourPart] = []
	var taken := {}
	for p in pool:
		if picked.size() >= count:
			break
		if taken.has(p.instrument):
			continue
		taken[p.instrument] = true
		picked.append(p)
	return picked


## Who holds each of `parts`, index for index: the roster, sorted so a replay is not at the
## mercy of a Dictionary's own order, then shuffled by the same `rng` the draw came from (so a
## seed replays identically), one part per peer in that order. Solo, the one peer there is (the
## host) holds it; empty, as nothing ever is a run has a band, falls back to the host.
static func assign(rng: RandomNumberGenerator, parts: Array[TourPart], peers: Array[int]) -> Array[int]:
	var roster := peers.duplicate()
	roster.sort()
	_shuffle(roster, rng)
	var holders: Array[int] = []
	for i in parts.size():
		holders.append(roster[i] if i < roster.size() else (roster[0] if not roster.is_empty() else 1))
	return holders


## `peer_id` just left: every part they held goes open (holder 0), timestamped by the run's own
## clock (`seconds_left`, which only counts down) so the grace before it is handed on can be read
## back as `open_since[i] - run.seconds_left`.
static func open(run: TourRun, peer_id: int) -> void:
	for i in run.holders.size():
		if run.holders[i] == peer_id:
			run.holders[i] = 0
			if i < run.open_since.size():
				run.open_since[i] = run.seconds_left


## Hands each open part (`holders[i] == 0`) whose `ready[i]` is true to whoever on `roster`
## holds the fewest parts right now (ties to the lowest peer id), one at a time so two parts
## opening together do not both land on the same person. `ready` is the caller's own "has THIS
## part's grace run out" check, index for index (`Tour._tick_parts`, against `open_since` and
## `run.seconds_left`); this does not read the clock itself, and a part still inside its own
## grace stays open while another past its own is handed on. Returns the last peer a part was
## handed to, 0 when none was, for the suite.
static func reassign(run: TourRun, roster: Array[int], ready: Array[bool]) -> int:
	if roster.is_empty():
		return 0
	var sorted_roster := roster.duplicate()
	sorted_roster.sort()
	var last := 0
	for i in run.holders.size():
		if run.holders[i] != 0 or i >= ready.size() or not ready[i]:
			continue
		var counts := {}
		for peer in sorted_roster:
			counts[peer] = 0
		for h in run.holders:
			if counts.has(h):
				counts[h] += 1
		var best: int = sorted_roster[0]
		for peer in sorted_roster:
			if counts[peer] < counts[best]:
				best = peer
		run.holders[i] = best
		last = best
	return last


## The catalogue: a backbeat, a four-on-the-floor pulse and just the four for the tambourine; a
## wall of eighths and the offbeats for the shaker; a stab on the one and on 1-and-3 for the
## keytar, whose chord is the player's own call. See the design note in docs/loop_backlog.md's
## "Tour" section for how `window`/`need`/`clean` were sized: tight enough that flailing fails.
static func _build() -> Array[TourPart]:
	var out: Array[TourPart] = []

	var tamb_backbeat := TourPart.new()
	tamb_backbeat.id = &"tamb_backbeat"
	tamb_backbeat.instrument = &"tambourine"
	tamb_backbeat.line = "TAMBOURINE: strike it on 2 and 4, every bar"
	tamb_backbeat.channel = 9
	tamb_backbeat.pitches = PackedInt32Array([54])
	tamb_backbeat.beats = PackedFloat64Array([1.0, 3.0])
	tamb_backbeat.window = 0.2
	tamb_backbeat.need = 8
	tamb_backbeat.clean = 0.7
	out.append(tamb_backbeat)

	var tamb_four := TourPart.new()
	tamb_four.id = &"tamb_four"
	tamb_four.instrument = &"tambourine"
	tamb_four.line = "TAMBOURINE: a hit on every beat, keep it even"
	tamb_four.channel = 9
	tamb_four.pitches = PackedInt32Array([54])
	tamb_four.grid = 1.0
	tamb_four.window = 0.2
	tamb_four.need = 12
	tamb_four.clean = 0.7
	out.append(tamb_four)

	var tamb_last := TourPart.new()
	tamb_last.id = &"tamb_last"
	tamb_last.instrument = &"tambourine"
	tamb_last.line = "TAMBOURINE: just the four, the last beat of every bar"
	tamb_last.channel = 9
	tamb_last.pitches = PackedInt32Array([54])
	tamb_last.beats = PackedFloat64Array([3.0])
	tamb_last.window = 0.2
	tamb_last.need = 4
	tamb_last.clean = 0.6
	out.append(tamb_last)

	var shaker_eighths := TourPart.new()
	shaker_eighths.id = &"shaker_eighths"
	shaker_eighths.instrument = &"shaker"
	shaker_eighths.line = "SHAKER: every eighth, don't stop"
	shaker_eighths.channel = 9
	shaker_eighths.pitches = PackedInt32Array([82])
	shaker_eighths.grid = 0.5
	shaker_eighths.window = 0.1
	shaker_eighths.need = 24
	shaker_eighths.clean = 0.7
	out.append(shaker_eighths)

	var shaker_offbeats := TourPart.new()
	shaker_offbeats.id = &"shaker_offbeats"
	shaker_offbeats.instrument = &"shaker"
	shaker_offbeats.line = "SHAKER: the \"and\" of every beat, nothing on the beat"
	shaker_offbeats.channel = 9
	shaker_offbeats.pitches = PackedInt32Array([82])
	shaker_offbeats.beats = PackedFloat64Array([0.5, 1.5, 2.5, 3.5])
	shaker_offbeats.window = 0.12
	shaker_offbeats.need = 12
	shaker_offbeats.clean = 0.7
	out.append(shaker_offbeats)

	var keys_one := TourPart.new()
	keys_one.id = &"keys_one"
	keys_one.instrument = &"keytar"
	keys_one.line = "KEYTAR: one stab on the one, every bar"
	keys_one.channel = -1
	keys_one.beats = PackedFloat64Array([0.0])
	keys_one.window = 0.2
	keys_one.need = 4
	keys_one.clean = 0.6
	out.append(keys_one)

	var keys_one_three := TourPart.new()
	keys_one_three.id = &"keys_one_three"
	keys_one_three.instrument = &"keytar"
	keys_one_three.line = "KEYTAR: stabs on 1 and 3, the chord's your call"
	keys_one_three.channel = -1
	keys_one_three.beats = PackedFloat64Array([0.0, 2.0])
	keys_one_three.window = 0.2
	keys_one_three.need = 8
	keys_one_three.clean = 0.6
	out.append(keys_one_three)

	out.append(_part(&"cowbell_one", &"cowbell", "COWBELL: one clank on the one, every bar",
			PackedInt32Array([56]), PackedFloat64Array([0.0]), 0.0, 0.2, 4, 0.6))
	out.append(_part(&"cowbell_four", &"cowbell", "COWBELL: every beat, more cowbell",
			PackedInt32Array([56]), PackedFloat64Array(), 1.0, 0.2, 12, 0.7))
	out.append(_part(&"lowbell_backbeat", &"cowbell2", "LOW COWBELL: 2 and 4, under the tambourine",
			PackedInt32Array([68]), PackedFloat64Array([1.0, 3.0]), 0.0, 0.2, 8, 0.7))
	out.append(_part(&"lowbell_ands", &"cowbell2", "LOW COWBELL: the \"and\" of 2 and the \"and\" of 4",
			PackedInt32Array([68]), PackedFloat64Array([1.5, 3.5]), 0.0, 0.15, 8, 0.7))
	out.append(_part(&"block_offbeats", &"woodblock", "WOODBLOCK: the \"and\" of every beat",
			PackedInt32Array([76]), PackedFloat64Array([0.5, 1.5, 2.5, 3.5]), 0.0, 0.15, 12, 0.7))
	out.append(_part(&"block_three", &"woodblock", "WOODBLOCK: one knock on the three",
			PackedInt32Array([76]), PackedFloat64Array([2.0]), 0.0, 0.2, 4, 0.6))
	out.append(_part(&"lowblock_one_three", &"woodblock2", "LOW WOODBLOCK: knocks on 1 and 3",
			PackedInt32Array([77]), PackedFloat64Array([0.0, 2.0]), 0.0, 0.2, 8, 0.7))
	out.append(_part(&"lowblock_eighths", &"woodblock2", "LOW WOODBLOCK: every eighth, a ticking clock",
			PackedInt32Array([77]), PackedFloat64Array(), 0.5, 0.12, 24, 0.7))
	out.append(_part(&"pad_four", &"pad", "DRUM PAD: a tom on every beat",
			PackedInt32Array([47]), PackedFloat64Array(), 1.0, 0.2, 12, 0.7))
	out.append(_part(&"pad_backbeat", &"pad", "DRUM PAD: hit 2 and 4 with the snare",
			PackedInt32Array([47]), PackedFloat64Array([1.0, 3.0]), 0.0, 0.2, 8, 0.7))
	out.append(_part(&"lowpad_one", &"pad2", "LOW PAD: one boom on the one",
			PackedInt32Array([45]), PackedFloat64Array([0.0]), 0.0, 0.2, 4, 0.6))
	out.append(_part(&"lowpad_one_three", &"pad2", "LOW PAD: booms on 1 and 3",
			PackedInt32Array([45]), PackedFloat64Array([0.0, 2.0]), 0.0, 0.2, 8, 0.7))
	out.append(_part(&"triangle_turnaround", &"triangle", "TRIANGLE: a ding on the \"and\" of 4, every bar",
			PackedInt32Array([81]), PackedFloat64Array([3.5]), 0.0, 0.2, 4, 0.6))
	out.append(_part(&"triangle_shimmer", &"triangle", "TRIANGLE: a ring on the one and the three",
			PackedInt32Array([81]), PackedFloat64Array([0.0, 2.0]), 0.0, 0.2, 8, 0.7))
	out.append(_part(&"mute_triangle_backbeat", &"triangle2", "MUTED TRIANGLE: choked, right on 2 and 4",
			PackedInt32Array([80]), PackedFloat64Array([1.0, 3.0]), 0.0, 0.15, 8, 0.7))
	out.append(_part(&"mute_triangle_eighths", &"triangle2", "MUTED TRIANGLE: every eighth, choked short",
			PackedInt32Array([80]), PackedFloat64Array(), 0.5, 0.12, 24, 0.7))
	out.append(_part(&"claves_one", &"claves", "CLAVES: one sharp crack on the one, every bar",
			PackedInt32Array([75]), PackedFloat64Array([0.0]), 0.0, 0.2, 4, 0.6))
	out.append(_part(&"claves_backbeat", &"claves", "CLAVES: the \"and\" of 2 and 4, the backbeat crack",
			PackedInt32Array([75]), PackedFloat64Array([1.5, 3.5]), 0.0, 0.15, 8, 0.7))
	out.append(_part(&"lowclaves_backbeat", &"claves2", "LOW CLAVES: 2 and 4, under the tambourine",
			PackedInt32Array([58]), PackedFloat64Array([1.0, 3.0]), 0.0, 0.15, 8, 0.7))
	out.append(_part(&"lowclaves_eighths", &"claves2", "LOW CLAVES: every eighth, sharp and steady",
			PackedInt32Array([58]), PackedFloat64Array(), 0.5, 0.12, 24, 0.7))
	out.append(_part(&"hihat_eighths", &"hihat", "HI-HAT: every eighth, keep it tight and closed",
			PackedInt32Array([42]), PackedFloat64Array(), 0.5, 0.12, 24, 0.7))
	out.append(_part(&"hihat_offbeats", &"hihat", "HI-HAT: the \"and\" of every beat",
			PackedInt32Array([42]), PackedFloat64Array([0.5, 1.5, 2.5, 3.5]), 0.0, 0.15, 12, 0.7))
	out.append(_part(&"openhat_backbeat", &"hihat2", "OPEN HI-HAT: 2 and 4, let it wash out",
			PackedInt32Array([46]), PackedFloat64Array([1.0, 3.0]), 0.0, 0.2, 8, 0.7))
	out.append(_part(&"openhat_one", &"hihat2", "OPEN HI-HAT: one open splash on the one",
			PackedInt32Array([46]), PackedFloat64Array([0.0]), 0.0, 0.2, 4, 0.6))

	return out


## One part on channel 9 (the hand percussion's), the shared shape of the twelve spilled-kit
## parts above -- a one-line builder so the table in docs/loop_backlog.md's "Tour" section is
## the catalogue, not twelve repeats of the same eight assignments.
static func _part(id: StringName, instrument: StringName, line: String, pitches: PackedInt32Array,
		beats: PackedFloat64Array, grid: float, window: float, need: int, clean: float) -> TourPart:
	var p := TourPart.new()
	p.id = id
	p.instrument = instrument
	p.line = line
	p.channel = 9
	p.pitches = pitches
	p.beats = beats
	p.grid = grid
	p.window = window
	p.need = need
	p.clean = clean
	return p


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
