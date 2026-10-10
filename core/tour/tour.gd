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

## The track the dragging-keys flaw judges: TourProject.KEYS_TRACK, repeated here as a plain
## const because every throwaway project (`TourProject.song_for`) is built fresh with known
## numbering. _test_tour_song_has_a_playing_band asserts the two agree.
const TIMING_TRACK := 2
## The one lane every played part's notes land on: TourProject.STAGE_TRACK, same reasoning.
## _test_tour_song_has_a_stage_lane asserts the two agree.
const STAGE_TRACK := 1

## The host's project, captured the moment the run started, restored exactly when it ends.
var _snapshot: Dictionary = {}
## The count-in this process had going into the run, restored when it ends: a brief needs none
## (see `start_run`/`_end_run`), and a run is not the place to leave somebody's own setting changed.
var _saved_count_in_bars := 0
var _loudness: TourMeasure.Loudness = null
var _balance: TourMeasure.Balance = null
var _timing: TourMeasure.Timing = null
## The cards offered by the draft under way, by index, for `pick_draft` to apply.
var _draft: Array[TourCard] = []
## `run.fixed` as it was the last time it was published, so a tick that changes nothing does not
## cost a publish: a handful of RPCs a brief, not one every physics frame.
var _published_fixed: Array[bool] = []
## [hits, played, holders] as last published, the same reasoning for `_tick_parts`.
var _published_parts_state: Array = []


func _ready() -> void:
	unlocks = TourUnlocks.new()
	unlocks.load_saved()
	# Deferred: Session is also an autoload, and may not be in the tree yet.
	(func():
		Session.tour_changed.connect(_on_tour_changed)
		Session.tour_asked.connect(_on_tour_asked)
		Session.participant_left.connect(_on_participant_left)).call_deferred()


func _physics_process(delta: float) -> void:
	if run == null or not Session.is_authority() or run.state != TourRun.State.BRIEF:
		return
	if run.tuning:
		var backend := DAW.backend as GodotBackend
		if backend != null and backend.parts_ready():
			run.tuning = false
			DAW.seek(0.0)
			# Not transport_play(): a part is played onto the Stage lane, and a take only ever
			# lands while the transport records (HitRecorder/GuestMidi's `follow`).
			DAW.transport_record()
			_publish()
		return
	_on_measure_tick(delta)
	_tick_flaws()
	_tick_parts()
	if not run.flaws.is_empty() and not run.fixed.has(false) and not run.played.has(false):
		_finish_brief()
		return
	run.seconds_left = maxf(run.seconds_left - delta, 0.0)
	if run.seconds_left <= 0.0:
		_finish_brief()


## Whether a run can be started here right now: the built-in engine only (real loudness and
## spectrum measurement needs real audio), and only on the host.
func is_available() -> bool:
	return DAW.backend is GodotBackend and Session.is_authority()


## One bar at this run's song tempo, in seconds, while a brief needs its parts ticked live; 0.0
## the rest of the time. scenes/studio.gd sets this onto HitRecorder.roll_every and
## GuestMidi.roll_every so a running take is sent (and a fresh one begun) about every bar rather
## than only when recording stops -- the one opt-in change to either recorder's default
## behaviour (see their own doc comments). Reads the same on a guest as on the host: `run` here
## is rebuilt from `Session.tour` either way.
func take_roll_seconds() -> float:
	if run == null or run.state != TourRun.State.BRIEF:
		return 0.0
	var bpb := float(DAW.state.beats_per_bar) if DAW.state != null else 4.0
	return bpb * 60.0 / maxf(run.song_tempo, 1.0)


## Host only. Captures the real project, swaps in the first brief's throwaway one, and starts
## it. Refuses quietly when a run is already under way or the engine cannot support one.
func start_run() -> void:
	if run != null or not is_available():
		return
	var backend := DAW.backend as OfflineBackend
	_snapshot = TourProject.capture(backend)
	_saved_count_in_bars = DAW.state.count_in_bars if DAW.state != null else 0
	DAW.set_count_in(0)
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
	if card.is_curse:
		run.curses.append(card.id)
	else:
		run.gear.append(card.id)
	_draft = []
	run.draft = []
	_start_brief(run.brief_index + 1, card)


## Host only. Calls the run off early, same ending path as a loss.
func abandon_run() -> void:
	if run == null or not Session.is_authority():
		return
	_end_run(false)


## Loads brief `index`'s rescue song (drawn from `run.song_rng(index)`: tempo, then flaws, then
## each flaw's own choices, in that order, so a seed replays identically) and starts the brief
## tuning up -- the clock does not run until `_physics_process` sees the new tempo's parts are
## rendered. `card`, when given, is a just-picked draft card, applied once the song is in rather
## than before: it would otherwise be stamped on the project `_start_brief` is about to replace.
func _start_brief(index: int, card: TourCard = null) -> void:
	var brief := TourBriefs.brief(index)
	var rng := run.song_rng(index)
	var band_size := Session.participants.size()
	var song_tempo := TourFlaws.tempo_for(rng)
	var drawn := TourFlaws.draw(rng, TourFlaws.count_for(band_size, brief.is_boss))
	var backend := DAW.backend as OfflineBackend
	var problems := TourProject.load(TourProject.song_for(brief, song_tempo, drawn, rng), backend)
	if not problems.is_empty():
		push_warning("Tour: could not load brief %d's song: %s" % [index, problems])
		if not _snapshot.is_empty():
			TourProject.restore(backend, _snapshot)
			_snapshot = {}
		run = null
		Session.publish_tour({})
		return
	run.brief_index = index
	run.state = TourRun.State.BRIEF
	run.score = 0
	run.band_size = band_size
	run.song_tempo = song_tempo
	run.flaws.assign(drawn.map(func(f: TourFlaw) -> StringName: return f.id))
	run.fixed.clear()
	for _i in run.flaws.size():
		run.fixed.append(false)
	# The same `rng` stream, continuing right where the flaws' own draws left it, so a seed
	# replays identically all the way through: tempo, flaws, then parts and who holds them.
	var parts_drawn := TourParts.draw(rng, TourParts.count_for(band_size, brief.is_boss))
	var roster: Array[int] = []
	roster.assign(Session.participants.keys())
	run.parts.assign(parts_drawn.map(func(p: TourPart) -> StringName: return p.id))
	run.holders.assign(TourParts.assign(rng, parts_drawn, roster))
	run.hits.clear()
	run.played.clear()
	run.open_since.clear()
	for _i in run.parts.size():
		run.hits.append(0)
		run.played.append(false)
		run.open_since.append(0.0)
	run.tuning = true
	# Before the clock is set: a "shorter_clock" card writes `next_brief_seconds_mult`, and this
	# is the brief it means.
	if card != null:
		card.apply(run)
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
	_published_fixed = []
	_published_parts_state = []
	brief_started.emit(index)
	_publish()


## Samples whichever of Loudness/Balance/Timing this brief lists in `measures` -- none do today
## (see briefs.gd), but a future calibrated brief can still ask for one.
func _on_measure_tick(delta: float) -> void:
	if _loudness != null:
		_loudness.sample(delta)
	if _balance != null:
		_balance.sample(delta)
	if _timing != null:
		_timing.sample(delta)


## Reads every one of this brief's flaws off the live desk and publishes only when the answer
## actually changed, so the band's HUD ticks a line the moment it is fixed without a run
## spamming `Session.publish_tour` every physics frame.
func _tick_flaws() -> void:
	for i in run.flaws.size():
		run.fixed[i] = TourFlaws.by_id(run.flaws[i]).fixed(DAW.state, run)
	if run.fixed != _published_fixed:
		_published_fixed = run.fixed.duplicate()
		_publish()


## Reads each part's notes off the Stage lane (TourMeasure.Rhythm), ticks `run.hits`/`run.played`,
## and hands an open part on once its grace has run out (TourParts.PART_GRACE) -- an open part
## still judges in the meantime, since anyone can pick the instrument up. Publishes only when
## hits, played or holders actually changed, the same reasoning as `_tick_flaws`.
func _tick_parts() -> void:
	for i in run.parts.size():
		var part := TourParts.by_id(run.parts[i])
		if part == null:
			continue
		var rhythm := TourMeasure.Rhythm.new()
		rhythm.start(STAGE_TRACK, 0.0, part)
		var r := rhythm.result()
		run.hits[i] = int(r.get("on", 0))
		run.played[i] = part.played(r)
	var ready: Array[bool] = []
	var any_ready := false
	for i in run.holders.size():
		var past_grace: bool = run.holders[i] == 0 and i < run.open_since.size() \
				and run.open_since[i] - run.seconds_left >= TourParts.PART_GRACE
		ready.append(past_grace)
		any_ready = any_ready or past_grace
	if any_ready:
		var roster: Array[int] = []
		roster.assign(Session.participants.keys())
		TourParts.reassign(run, roster, ready)
	var state := [run.hits.duplicate(), run.played.duplicate(), run.holders.duplicate()]
	if state != _published_parts_state:
		_published_parts_state = state
		_publish()


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
	var fixed_n: int = run.fixed.filter(func(f: bool) -> bool: return f).size()
	samples["flaws"] = {"fixed": fixed_n, "total": run.flaws.size(),
			"seconds_left_frac": run.seconds_left / brief.seconds}
	var played_n: int = run.played.filter(func(p: bool) -> bool: return p).size()
	samples["parts"] = {"played": played_n, "total": run.played.size()}
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
	if backend is OfflineBackend:
		DAW.transport_stop()
		DAW.set_count_in(_saved_count_in_bars)
		if not _snapshot.is_empty():
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


## `peer_id` left the room mid-brief: every part they held goes open, for `_tick_parts` to hand
## on once the grace has run out. Host only, like every other mutation of `run`.
func _on_participant_left(peer_id: int) -> void:
	if run == null or not Session.is_authority() or run.state != TourRun.State.BRIEF:
		return
	TourParts.open(run, peer_id)
	_publish()


## Test-only, for `tools/screenshot.gd`'s `--tour` flag: reaches a run state deterministically,
## without waiting out a brief's timer, so a shot of the case or the HUD is reproducible. Host
## only, like every other mutation here; "intact" needs nothing from Tour at all, since the
## case starts chained and only a run under way changes that. "brief" (and "broken") show the
## real rescue song mid-tuning or mid-brief -- its flaw lines and, while the new tempo's ten
## parts are still on the workers, "SOUNDCHECK" (see TourHud); band size and flaw count still
## come from `Session.participants.size()`, so a solo shot shows one line.
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
			# Not `_finish_brief()`: a screenshot has no song playing to judge, and a judged
			# brief might simply fail. This skips straight to offering a draft, the way a passed
			# brief would.
			if run != null and run.state == TourRun.State.BRIEF:
				_loudness = null
				_balance = null
				_timing = null
				run.tuning = false
				run.state = TourRun.State.DRAFTING
				var rng := RandomNumberGenerator.new()
				rng.seed = run.attempt_seed + run.brief_index + 1
				_draft = TourDeck.draw(rng, run.gear + run.curses)
				run.draft.assign(_draft.map(func(c: TourCard) -> StringName: return c.id))
				drafting_started.emit(_draft)
				_publish()
