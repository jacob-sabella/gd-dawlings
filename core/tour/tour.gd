extends Node

## Autoload `Tour`. The one run this process is, or is not, in right now -- the same reason
## `Session`/`DAW` are autoloads: exactly one thing per process owns it.
##
## Host-authoritative, like everything else that touches the DAW. Every mutation here runs on
## the host and ends with `Session.publish_tour(run.to_dict())` (or `{}` once the run ends); a
## guest never mutates `run` from the network -- it listens to `Session.tour_changed` and
## rebuilds a read-only `TourRun.from_dict(Session.tour)`, and the one thing it can ask for is
## `Session.ask_tour(&"draft_pick", [index])`.
##
## Package A note: nothing here knows about `core/items/`, `scenes/`, or `hardware/` -- the
## case that starts a run (Package B) calls `start_run()` directly once it has taken enough
## hits, the same way anything else that wants a run under way would. An earlier draft of this
## plan had a `register_case_hit()` here that counted hits toward breaking the case, but that
## would have made Tour hold a notion of "the case", which belongs entirely to Package B; it is
## dropped from the final contract (see the case's own `hits`/`HITS_TO_BREAK` instead).

signal run_started()
signal brief_started(index: int)
## `passed`: whether the just-finished brief was cleared. `score`: this brief's score (0-100).
signal brief_ended(passed: bool, score: int, detail: PackedStringArray)
signal drafting_started(cards: Array[TourCard])
signal run_ended(won: bool)

## `null` when `Tour.run.state == IDLE` -- i.e. always `null` between runs. On the host this is
## the live run; on a guest it is a read-only copy rebuilt from `Session.tour` on every change.
var run: TourRun = null
var unlocks: TourUnlocks

## The track a run's throwaway project uses for its pocket-check timing brief. Always this one:
## every throwaway project (`TourProject.blank_for`) is built fresh with known numbering.
const TIMING_TRACK := 1

## The host's project, captured the moment the run started, restored exactly when it ends.
var _snapshot: Dictionary = {}
var _loudness: TourMeasure.Loudness = null
var _balance: TourMeasure.Balance = null
var _timing: TourMeasure.Timing = null
## The cards offered by the draft under way, by index, for `pick_draft` to apply.
var _draft: Array[TourCard] = []


func _ready() -> void:
	unlocks = TourUnlocks.new()
	unlocks.load_saved()
	# Deferred: Session is also an autoload, and may not be in the tree yet.
	(func():
		Session.tour_changed.connect(_on_tour_changed)
		Session.tour_asked.connect(_on_tour_asked)).call_deferred()


func _physics_process(delta: float) -> void:
	if run == null or not Session.is_authority() or run.state != TourRun.State.BRIEF:
		return
	_on_measure_tick(delta)


## Whether a run can be started here right now: the built-in engine only (real loudness and
## spectrum measurement needs real audio), and only on the host.
func is_available() -> bool:
	return DAW.backend is GodotBackend and Session.is_authority()


## Host only. Captures the real project, swaps in the first brief's throwaway one, and starts
## it. Refuses quietly when a run is already under way or the engine cannot support one.
func start_run() -> void:
	if run != null or not is_available():
		return
	var backend := DAW.backend as OfflineBackend
	_snapshot = TourProject.capture(backend)
	var problems := ProjectBridge.load(TourProject.blank_for(TourBriefs.brief(0)), backend)
	if not problems.is_empty():
		push_warning("Tour: could not load the first brief's project: %s" % [problems])
		_snapshot = {}
		return
	run = TourRun.new()
	run.attempt_seed = randi()
	run_started.emit()
	_start_brief(0)


## Host only. The current draft's card, applied and run advanced to the next brief. A guest
## reaches this through `Session.ask_tour(&"draft_pick", [index])` -> `tour_asked` -> here.
func pick_draft(index: int) -> void:
	if run == null or not Session.is_authority() or run.state != TourRun.State.DRAFTING:
		return
	if index < 0 or index >= _draft.size():
		return
	var card: TourCard = _draft[index]
	card.apply(run)
	if card.is_curse:
		run.curses.append(card.id)
	else:
		run.gear.append(card.id)
	_draft = []
	run.draft = []
	_start_brief(run.brief_index + 1)


## Host only. Calls the run off early, same ending path as a loss.
func abandon_run() -> void:
	if run == null or not Session.is_authority():
		return
	_end_run(false)


func _start_brief(index: int) -> void:
	var brief := TourBriefs.brief(index)
	run.brief_index = index
	run.state = TourRun.State.BRIEF
	run.score = 0
	run.seconds_left = brief.seconds * run.next_brief_seconds_mult
	run.next_brief_seconds_mult = 1.0
	_loudness = null
	_balance = null
	_timing = null
	if &"loudness" in brief.measures:
		_loudness = TourMeasure.Loudness.new()
		_loudness.start()
	if &"balance" in brief.measures:
		_balance = TourMeasure.Balance.new()
		_balance.start()
	if &"timing" in brief.measures:
		_timing = TourMeasure.Timing.new()
		_timing.start(TIMING_TRACK, DAW.state.position_seconds if DAW.state != null else 0.0)
	brief_started.emit(index)
	_publish()


func _on_measure_tick(delta: float) -> void:
	if _loudness != null:
		_loudness.sample(delta)
	if _balance != null:
		_balance.sample(delta)
	if _timing != null:
		_timing.sample(delta)
	run.seconds_left = maxf(run.seconds_left - delta, 0.0)
	if run.seconds_left <= 0.0:
		_finish_brief()


func _finish_brief() -> void:
	var brief := TourBriefs.brief(run.brief_index)
	var samples := {}
	if _loudness != null:
		samples["loudness"] = _loudness.result()
		_loudness = null
	if _balance != null:
		samples["balance"] = _balance.result()
		_balance.stop()
		_balance = null
	if _timing != null:
		samples["timing"] = _timing.result()
		_timing = null
	var verdict := brief.judge(samples, run.tempo_tolerance_mult)
	var passed := bool(verdict["passed"])
	var score := int(verdict["score"])
	run.score = score
	brief_ended.emit(passed, score, verdict["detail"])
	if not passed:
		_end_run(false)
		return
	if brief.is_boss:
		_end_run(true)
		return
	run.state = TourRun.State.DRAFTING
	var rng := RandomNumberGenerator.new()
	rng.seed = run.attempt_seed + run.brief_index + 1
	_draft = TourDeck.draw(rng, run.gear + run.curses)
	run.draft.assign(_draft.map(func(c: TourCard) -> StringName: return c.id))
	drafting_started.emit(_draft)
	_publish()


func _end_run(won: bool) -> void:
	if _balance != null:
		_balance.stop()
	_loudness = null
	_balance = null
	_timing = null
	_draft = []
	var backend := DAW.backend
	if backend is OfflineBackend and not _snapshot.is_empty():
		TourProject.restore(backend as OfflineBackend, _snapshot)
	_snapshot = {}
	unlocks.record_run(won)
	run = null
	Session.publish_tour({})
	run_ended.emit(won)


func _publish() -> void:
	if run != null:
		Session.publish_tour(run.to_dict())


func _on_tour_changed() -> void:
	if Session.is_authority():
		return
	run = TourRun.from_dict(Session.tour) if not Session.tour.is_empty() else null


func _on_tour_asked(verb: StringName, args: Array, _from: int) -> void:
	if not Session.is_authority():
		return
	if verb == &"draft_pick" and args.size() == 1:
		pick_draft(int(args[0]))


## Test-only, for `tools/screenshot.gd`'s `--tour` flag: reaches a run state deterministically,
## without waiting out a brief's timer, so a shot of the case or the HUD is reproducible. Host
## only, like every other mutation here; "intact" needs nothing from Tour at all, since the
## case starts chained and only a run under way changes that.
func force_state_for_shot(stage: StringName) -> void:
	if not Session.is_authority():
		return
	match stage:
		&"broken", &"brief":
			if run == null:
				start_run()
		&"draft":
			if run == null:
				start_run()
			# Not `_finish_brief()`: a screenshot has no audio to judge, and a judged brief might
			# simply fail. This skips straight to offering a draft, the way a passed brief would.
			if run != null and run.state == TourRun.State.BRIEF:
				_loudness = null
				_balance = null
				_timing = null
				run.state = TourRun.State.DRAFTING
				var rng := RandomNumberGenerator.new()
				rng.seed = run.attempt_seed + run.brief_index + 1
				_draft = TourDeck.draw(rng, run.gear + run.curses)
				run.draft.assign(_draft.map(func(c: TourCard) -> StringName: return c.id))
				drafting_started.emit(_draft)
				_publish()
