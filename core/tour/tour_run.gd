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
	return run
