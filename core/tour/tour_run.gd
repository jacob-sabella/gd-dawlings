class_name TourRun
extends RefCounted

## One Tour run's state: which brief it is on, how that brief is going, what has been drafted
## so far. Pure data -- nothing here touches DAW or Session.
##
## `to_dict`/`from_dict` are the whole of what rides `Session.tour`, the same way a room's
## facts ride `Session.room`: a small flat dictionary, replicated whole rather than in deltas,
## because a run changes state a handful of times a brief, not every frame.

enum State { IDLE, BRIEF, DRAFTING, WON, LOST }

var state: State = State.IDLE
## 0..2 are the three regular briefs, 3 is the boss (see TourBriefs).
var brief_index: int = 0
var score: int = 0
var seconds_left: float = 0.0
## Boons and curses drafted so far, by TourCard.id.
var gear: Array[StringName] = []
var curses: Array[StringName] = []
## The draft on offer right now, by TourCard.id, in the order `TourHud`'s three cards and
## `Session.ask_tour(&"draft_pick", [index])`'s index agree on. Empty outside State.DRAFTING.
var draft: Array[StringName] = []
## How much the timing brief's beat window is widened (or narrowed, for a curse): see
## TourBrief.judge and TourCard's `loose_tempo`/`tight_tempo`.
var tempo_tolerance_mult: float = 1.0
## How much the next brief's time limit is scaled, applied once then reset to 1.0: see
## TourCard's `shorter_clock`. A run-state multiplier rather than a write to TourBriefs.LIST,
## which is shared by every run and every process.
var next_brief_seconds_mult: float = 1.0
## The seed behind this run's draws, kept so a replicated run can be replayed identically if
## ever needed; not currently read back by anything but there to keep draws reproducible.
var attempt_seed: int = 0
## `Session.participants.size()` at the moment this brief started: read once, so a friend
## joining mid-brief never makes it busier until the next one.
var band_size: int = 1
## This brief's rescue song's tempo, drawn from `song_rng`.
var song_tempo: float = 120.0
## This brief's flaws by TourFlaw.id, and which are fixed right now, index for index. Guests
## draw the lines and fix gestures from TourFlaws.by_id; only ids and bools ride the wire.
var flaws: Array[StringName] = []
var fixed: Array[bool] = []
## The band is still tuning up: the brief's project is in but its parts are rendering, and the
## clock does not run until they have (see GodotBackend.parts_ready).
var tuning: bool = false

## This brief's parts (TourPart.id, core/tour/tour_part.gd), one per player up to
## TourParts.count_for(band_size). Guests read lines/instruments back from TourParts.by_id --
## only ids, ints and bools ride the wire. Index for index with `holders` (a peer id, 0 for
## open -- nobody is holding it, or whoever was has left), `hits` (on-grid notes heard so far),
## `played` (TourPart.played, once it has cleared) and `open_since` (the clock, `seconds_left`,
## a part went open at, for the grace before TourParts.reassign hands it to someone else).
var parts: Array[StringName] = []
var holders: Array[int] = []
var hits: Array[int] = []
var played: Array[bool] = []
var open_since: Array[float] = []

## Instruments spilled from the case so far: the Item.id of each copy (cowbell, cowbell2...),
## its curse (&"" none, &"sour", &"low", &"bound") and, bound, whose it is (a peer id, else 0).
## Grows across the whole run, not per brief -- a spilled instrument stays out of the case.
var instruments: Array[StringName] = []
var instrument_curses: Array[StringName] = []
var instrument_bound: Array[int] = []

## The clock this brief started with, in seconds, after `shorter_clock`'s multiplier: what
## `Tour.brief_elapsed()`/`TourChaos.schedule` measure against, since `seconds_left` only ever
## counts down and a short brief needs the real total to know where "the last 8 seconds" are.
var seconds_total: float = 0.0
## This brief's chaos events by TourChaosEvent.id, and their schedule and live state, index for
## index: `event_at` (seconds of brief clock elapsed at the strike), `event_track` (the struck
## strip, 0 for none; `tempo_lurch`'s own slot holds its sign instead, see TourChaosEvent's doc),
## `event_state` (TourChaos.State).
var events: Array[StringName] = []
var event_at: Array[float] = []
var event_track: Array[int] = []
var event_state: Array[int] = []

## The crowd's two bars (TourEar.BARS: level, balance) right now, index for index. Both stay
## empty until `TourMeasure.Ear` has heard a full window -- which is also how a guest and the
## HUD tell "listening..." apart from "unhappy": an empty array is neither. `crowd_over` only
## means anything where the matching `crowd_happy` is false, and says which direction (loud/mud
## vs. quiet/thin) the HUD's line picks.
var crowd_happy: Array[bool] = []
var crowd_over: Array[bool] = []


## This brief's own random stream, seeded off `attempt_seed` and `index` so it never draws the
## same numbers the draft's (`attempt_seed + brief_index + 1`) does, and replays identically on
## any machine given the same `attempt_seed`.
func song_rng(index: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([attempt_seed, "song", index])
	return rng


## This brief's chaos stream -- its own, not a continuation of `song_rng`'s: every existing
## seed-replay test keeps its numbers (TourFlaws/TourParts drawing exactly as before), and a
## count change on either side can never shift the chaos draw.
func chaos_rng(index: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([attempt_seed, "chaos", index])
	return rng


func to_dict() -> Dictionary:
	return {
		"state": int(state),
		"brief_index": brief_index,
		"score": score,
		"seconds_left": seconds_left,
		"gear": (gear as Array).map(func(g): return String(g)),
		"curses": (curses as Array).map(func(c): return String(c)),
		"draft": (draft as Array).map(func(d): return String(d)),
		"tempo_tolerance_mult": tempo_tolerance_mult,
		"next_brief_seconds_mult": next_brief_seconds_mult,
		"attempt_seed": attempt_seed,
		"band_size": band_size,
		"song_tempo": song_tempo,
		"flaws": (flaws as Array).map(func(f): return String(f)),
		"fixed": (fixed as Array).duplicate(),
		"tuning": tuning,
		"parts": (parts as Array).map(func(p): return String(p)),
		"holders": (holders as Array).duplicate(),
		"hits": (hits as Array).duplicate(),
		"played": (played as Array).duplicate(),
		"open_since": (open_since as Array).duplicate(),
		"instruments": (instruments as Array).map(func(i): return String(i)),
		"instrument_curses": (instrument_curses as Array).map(func(c): return String(c)),
		"instrument_bound": (instrument_bound as Array).duplicate(),
		"seconds_total": seconds_total,
		"events": (events as Array).map(func(e): return String(e)),
		"event_at": (event_at as Array).duplicate(),
		"event_track": (event_track as Array).duplicate(),
		"event_state": (event_state as Array).duplicate(),
		"crowd_happy": (crowd_happy as Array).duplicate(),
		"crowd_over": (crowd_over as Array).duplicate(),
	}


static func from_dict(d: Dictionary) -> TourRun:
	var run := TourRun.new()
	run.state = clampi(int(d.get("state", State.IDLE)), State.IDLE, State.LOST) as State
	run.brief_index = int(d.get("brief_index", 0))
	run.score = int(d.get("score", 0))
	run.seconds_left = float(d.get("seconds_left", 0.0))
	var gear_in: Array = d.get("gear", [])
	run.gear.assign(gear_in.map(func(g): return StringName(g)))
	var curses_in: Array = d.get("curses", [])
	run.curses.assign(curses_in.map(func(c): return StringName(c)))
	var draft_in: Array = d.get("draft", [])
	run.draft.assign(draft_in.map(func(c): return StringName(c)))
	run.tempo_tolerance_mult = float(d.get("tempo_tolerance_mult", 1.0))
	run.next_brief_seconds_mult = float(d.get("next_brief_seconds_mult", 1.0))
	run.attempt_seed = int(d.get("attempt_seed", 0))
	run.band_size = int(d.get("band_size", 1))
	run.song_tempo = float(d.get("song_tempo", 120.0))
	var flaws_in: Array = d.get("flaws", [])
	run.flaws.assign(flaws_in.map(func(f): return StringName(f)))
	var fixed_in: Array = d.get("fixed", [])
	run.fixed.assign(fixed_in.map(func(b): return bool(b)))
	while run.fixed.size() < run.flaws.size():
		run.fixed.append(false)
	run.fixed.resize(run.flaws.size())
	run.tuning = bool(d.get("tuning", false))
	var parts_in: Array = d.get("parts", [])
	run.parts.assign(parts_in.map(func(p): return StringName(p)))
	var holders_in: Array = d.get("holders", [])
	run.holders.assign(holders_in.map(func(h): return int(h)))
	while run.holders.size() < run.parts.size():
		run.holders.append(0)
	run.holders.resize(run.parts.size())
	var hits_in: Array = d.get("hits", [])
	run.hits.assign(hits_in.map(func(h): return int(h)))
	while run.hits.size() < run.parts.size():
		run.hits.append(0)
	run.hits.resize(run.parts.size())
	var played_in: Array = d.get("played", [])
	run.played.assign(played_in.map(func(p): return bool(p)))
	while run.played.size() < run.parts.size():
		run.played.append(false)
	run.played.resize(run.parts.size())
	var open_since_in: Array = d.get("open_since", [])
	run.open_since.assign(open_since_in.map(func(o): return float(o)))
	while run.open_since.size() < run.parts.size():
		run.open_since.append(0.0)
	run.open_since.resize(run.parts.size())
	var instruments_in: Array = d.get("instruments", [])
	run.instruments.assign(instruments_in.map(func(i): return StringName(i)))
	var instrument_curses_in: Array = d.get("instrument_curses", [])
	run.instrument_curses.assign(instrument_curses_in.map(func(c): return StringName(c)))
	while run.instrument_curses.size() < run.instruments.size():
		run.instrument_curses.append(&"")
	run.instrument_curses.resize(run.instruments.size())
	var instrument_bound_in: Array = d.get("instrument_bound", [])
	run.instrument_bound.assign(instrument_bound_in.map(func(b): return int(b)))
	while run.instrument_bound.size() < run.instruments.size():
		run.instrument_bound.append(0)
	run.instrument_bound.resize(run.instruments.size())
	run.seconds_total = float(d.get("seconds_total", 0.0))
	var events_in: Array = d.get("events", [])
	run.events.assign(events_in.map(func(e): return StringName(e)))
	var event_at_in: Array = d.get("event_at", [])
	run.event_at.assign(event_at_in.map(func(a): return float(a)))
	while run.event_at.size() < run.events.size():
		run.event_at.append(INF)
	run.event_at.resize(run.events.size())
	var event_track_in: Array = d.get("event_track", [])
	run.event_track.assign(event_track_in.map(func(t): return int(t)))
	while run.event_track.size() < run.events.size():
		run.event_track.append(0)
	run.event_track.resize(run.events.size())
	var event_state_in: Array = d.get("event_state", [])
	run.event_state.assign(event_state_in.map(func(s): return int(s)))
	while run.event_state.size() < run.events.size():
		run.event_state.append(TourChaos.State.PENDING)
	run.event_state.resize(run.events.size())
	var crowd_happy_in: Array = d.get("crowd_happy", [])
	run.crowd_happy.assign(crowd_happy_in.map(func(b): return bool(b)))
	var crowd_over_in: Array = d.get("crowd_over", [])
	run.crowd_over.assign(crowd_over_in.map(func(b): return bool(b)))
	var crowd_n := maxi(run.crowd_happy.size(), run.crowd_over.size())
	while run.crowd_happy.size() < crowd_n:
		run.crowd_happy.append(false)
	while run.crowd_over.size() < crowd_n:
		run.crowd_over.append(false)
	return run
