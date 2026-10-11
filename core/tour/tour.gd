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
## An instrument just fell out of the case (host only, like every signal here): for the studio
## to put the real item in the room. A guest learns the same from `Session.tour`'s `instruments`
## -- the host never hears its own `Session.tour_changed` (`publish_tour` only RPCs out), which
## is why this exists rather than everything riding that one signal.
signal instrument_spilled(id: StringName, kind: StringName, curse: StringName, bound_to: int)
## A chaos event's telegraph or strike, from THIS peer's own clock -- the one pair of signals
## here that is not host-only: every peer (host included) runs `_tick_chaos_shown()` off its own
## `brief_elapsed()`, so the room reacts (a flicker, a rattle, a sound) at the same moment on
## every machine, rather than only on the host and then again, late, wherever `Session.tour`'s
## publish happens to land. The strike's actual EFFECT (a mute, a fader on the floor) still rides
## ordinary desk replication; these are the presentation alone.
signal chaos_telegraphed(index: int)
signal chaos_struck(index: int)

## `null` when `Tour.run.state == IDLE` -- i.e. always `null` between runs. On the host this is
## the live run; on a guest it is a read-only copy rebuilt from `Session.tour` on every change.
var run: TourRun = null
## Where the run's HUD card ends, in pixels down the screen, while it is shown (TourHud keeps it
## current); 0.0 with no card up. The session panel's notices start below it rather than on it.
var hud_bottom := 0.0
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
## `run.event_state` as last published, the same reasoning for `_tick_chaos`.
var _published_chaos: Array[int] = []
## Per chaos event index, the furthest TourChaos.State this PEER has already shown (the
## telegraph's sound and rattle, the strike's own sound) -- `_tick_chaos_shown`'s, read by both
## host and guest off their own `brief_elapsed()`, so each plays once however the clock and
## `Session.tour`'s publishes interleave.
var _shown_chaos: Array[int] = []
## Which brief `_shown_chaos` belongs to (`attempt_seed:brief_index` -- see `_chaos_key`), not
## merely which events it drew: two briefs can honestly draw the very same single event, and a
## second brief must still get its own surprise, not inherit the first one's already-shown
## state just because the ids happened to match.
var _shown_for_key := ""
## A guest's anchor for `brief_elapsed()`: the host's last published (seconds_total - seconds_left)
## pair, re-anchored to this machine's own wall clock on every `Session.tour_changed` -- several
## a brief -- so a late joiner reads right from their first publish and nobody drifts between
## them.
var _anchor_elapsed := 0.0
var _anchor_usec := 0
## True while `_start_brief` is laying a brief out, so a `spill` it makes on the way (the first
## brief's seeding, a card's) waits for the one publish at its end.
var _laying_out := false


func _ready() -> void:
	unlocks = TourUnlocks.new()
	unlocks.load_saved()
	# Deferred: Session is also an autoload, and may not be in the tree yet.
	(func():
		Session.tour_changed.connect(_on_tour_changed)
		Session.tour_asked.connect(_on_tour_asked)
		Session.participant_left.connect(_on_participant_left)).call_deferred()


func _physics_process(delta: float) -> void:
	# Both host and guest: the telegraph and the strike's presentation play from THIS peer's own
	# clock, before the host-only half below even asks whose authority this is -- see
	# `chaos_telegraphed`/`chaos_struck`'s own doc.
	if run != null and run.state == TourRun.State.BRIEF and not run.tuning:
		_tick_chaos_shown()
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
	_tick_chaos()
	if not run.flaws.is_empty() and not run.fixed.has(false) and not run.played.has(false) \
			and not run.event_state.has(TourChaos.State.STRUCK):
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


## Host only. The next copy of `kind` falls out of the case -- its own id ("cowbell", then
## "cowbell2"), cursed on its sound only (`curse`, &"sour"/&"low") or marked for one peer alone
## (`curse` &"bound", `bound_to`). Appended to the run and said at once (`instrument_spilled`,
## for the studio; `_publish` for everyone else), so a card picked mid-brief spills right away
## rather than waiting on the next brief's own tick. Returns the id spilled, or &"" once `kind`
## is already out of copies (TourParts.COPIES) -- a card offering one it cannot deliver is a
## bug in `TourDeck`'s own gating, not something this is asked to paper over.
func spill(kind: StringName, curse := &"", bound_to := 0) -> StringName:
	if run == null or not Session.is_authority():
		return &""
	var n := TourParts.copies_of(kind, run.instruments)
	if n >= TourParts.COPIES:
		return &""
	var id := TourParts.instance_id(kind, n)
	run.instruments.append(id)
	run.instrument_curses.append(curse)
	run.instrument_bound.append(bound_to)
	instrument_spilled.emit(id, kind, curse, bound_to)
	# Not while a brief is still being laid out (`_start_brief` spills before it draws the parts,
	# and publishes once at its end): a guest told halfway would see the new flaws over the old
	# brief's parts for a frame.
	if not _laying_out:
		_publish()
	return id


## Host only. A curse spill (`sour_spill`/`low_spill`/`marked_spill`) picks its own kind --
## whichever still has copies left, drawn from this run's own seed so a replay spills the same
## thing -- rather than the card naming one, since the card does not know what the case still
## has to give. `curse` &"bound" also draws who it is marked for, the same way, from the
## roster sorted so the draw is not at the mercy of a Dictionary's order.
func spill_cursed(curse: StringName) -> StringName:
	if run == null or not Session.is_authority():
		return &""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run.attempt_seed, "spill", run.brief_index])
	var pool: Array[StringName] = TourParts.SPILL_KINDS.filter(
			func(k: StringName) -> bool: return TourParts.copies_of(k, run.instruments) < TourParts.COPIES)
	if pool.is_empty():
		return &""
	var kind: StringName = pool[rng.randi() % pool.size()]
	var bound_to := 0
	if curse == &"bound":
		var roster: Array[int] = []
		roster.assign(Session.participants.keys())
		roster.sort()
		if not roster.is_empty():
			bound_to = roster[rng.randi() % roster.size()]
	return spill(kind, curse, bound_to)


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
	# replays identically all the way through: tempo, flaws, first spill, then parts and who
	# holds them.
	_laying_out = true
	if index == 0:
		for kind in TourParts.first_spill(rng, band_size):
			spill(kind)
	# Before the parts draw, so a card just picked (an instrument among them) counts for this
	# brief's parts; before the clock too -- a "shorter_clock" card writes
	# `next_brief_seconds_mult`, and this is the brief it means.
	if card != null:
		card.apply(run)
	_laying_out = false
	var available: Array[StringName] = TourParts.ROOM + run.instruments
	var parts_drawn := TourParts.draw(rng, TourParts.count_for(band_size, brief.is_boss, available.size()), available)
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
	run.seconds_left = brief.seconds * run.next_brief_seconds_mult
	run.next_brief_seconds_mult = 1.0
	run.seconds_total = run.seconds_left
	_lay_out_chaos(index, brief, band_size, drawn)
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


## This brief's chaos events, drawn and timed from the run's own `chaos_rng` -- a stream of its
## own, never brief 0's, so a replay strikes the same things at the same moments regardless of
## how many flaws or parts that seed also drew. Order of draws inside the stream: how many, then
## which, then each one's own track (or `tempo_lurch`'s sign), then the schedule -- see
## TourChaos's own doc.
func _lay_out_chaos(index: int, brief: TourBrief, band_size: int, flaws: Array[TourFlaw]) -> void:
	var crng := run.chaos_rng(index)
	var n := TourChaos.count_for(band_size, index, brief.is_boss, crng)
	var drawn_events := TourChaos.draw(crng, n, run.flaws)
	var flaw_tracks: Array[String] = []
	flaw_tracks.assign(flaws.map(func(f: TourFlaw) -> String: return f.track))
	run.events.clear()
	run.event_track.clear()
	run.event_state.clear()
	for e in drawn_events:
		run.events.append(e.id)
		var slot := 0
		if e.wants_track:
			var excl := flaw_tracks.duplicate()
			excl.append_array(e.extra_track_excludes)
			slot = TourChaos.pick_track(crng, DAW.state, excl)
		elif e.id == &"tempo_lurch":
			slot = TourChaos.pick_sign(crng)
		run.event_track.append(slot)
		run.event_state.append(TourChaos.State.PENDING)
	run.event_at.assign(TourChaos.schedule(crng, run.events.size(), run.seconds_total))
	# The schedule may honestly come back with fewer than asked (a short clock, too little room
	# between FIRST_SECONDS and LAST_SECONDS) -- every array stays index-for-index with it.
	run.events.resize(run.event_at.size())
	run.event_track.resize(run.event_at.size())
	run.event_state.resize(run.event_at.size())
	_published_chaos = []
	_shown_chaos = []
	_shown_for_key = _chaos_key(run)


## `attempt_seed:brief_index` -- a brief's own identity, for `_shown_chaos` to key off instead of
## the events it drew (two briefs can honestly draw the very same one event).
func _chaos_key(r: TourRun) -> String:
	return "%d:%d" % [r.attempt_seed, r.brief_index]


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


## Seconds of this brief's clock gone by: the one number every peer agrees on to within a
## publish's lateness, so "telegraph 2 s before the strike" lands at the same moment on every
## machine. On the host it is exact (`seconds_total - seconds_left`, both live); on a guest it is
## the host's last published pair, re-anchored to this machine's own wall clock on every
## `Session.tour_changed` (`_anchor_elapsed`/`_anchor_usec`, set in `_on_tour_changed`) -- a late
## joiner is right from their first publish, and nobody drifts between publishes. 0.0 outside a
## brief, or while still tuning (the clock has not started).
func brief_elapsed() -> float:
	if run == null or run.state != TourRun.State.BRIEF or run.tuning:
		return 0.0
	if Session.is_authority():
		return run.seconds_total - run.seconds_left
	return _anchor_elapsed + float(Time.get_ticks_usec() - _anchor_usec) / 1_000_000.0


## Host only: the live state machine. PENDING -> TELEGRAPHED at `event_at[i] -
## TourChaos.TELEGRAPH_SECONDS`, -> STRUCK at `event_at[i]` (the one place a strike's own DAW
## verbs run) -- then re-judged every tick exactly as a flaw is, RECOVERED once the event's own
## test passes and back to STRUCK if the band breaks it again. Publishes only on a change, the
## same reasoning as `_tick_flaws`/`_tick_parts`.
func _tick_chaos() -> void:
	if run.events.is_empty():
		return
	var elapsed := brief_elapsed()
	for i in run.events.size():
		var event := TourChaos.by_id(run.events[i])
		if event == null:
			continue
		var at: float = run.event_at[i] if i < run.event_at.size() else INF
		var track: int = run.event_track[i] if i < run.event_track.size() else 0
		match run.event_state[i]:
			TourChaos.State.PENDING:
				if elapsed >= at - TourChaos.TELEGRAPH_SECONDS:
					run.event_state[i] = TourChaos.State.TELEGRAPHED
			TourChaos.State.TELEGRAPHED:
				if elapsed >= at:
					event.strike(run, track)
					run.event_state[i] = TourChaos.State.STRUCK
			TourChaos.State.STRUCK:
				if event.recovered(DAW.state, run, track):
					run.event_state[i] = TourChaos.State.RECOVERED
			TourChaos.State.RECOVERED:
				if not event.recovered(DAW.state, run, track):
					run.event_state[i] = TourChaos.State.STRUCK
	if run.event_state != _published_chaos:
		_published_chaos = run.event_state.duplicate()
		_publish()


## Both host and guest, off THIS peer's own `brief_elapsed()`: plays the telegraph's and the
## strike's presentation (the lights, the rattle, the sounds -- wired in scenes/studio.gd) the
## moment this peer's own clock crosses each threshold, whichever of the clock or the wire
## (`run.event_state`, for a joiner or a long hitch) is further along. Each plays once, however
## the clock and the host's publishes interleave.
func _tick_chaos_shown() -> void:
	if run.events.is_empty():
		return
	var key := _chaos_key(run)
	if key != _shown_for_key:
		_shown_for_key = key
		_shown_chaos = []
	while _shown_chaos.size() < run.events.size():
		_shown_chaos.append(TourChaos.State.PENDING)
	var elapsed := brief_elapsed()
	for i in run.events.size():
		var at: float = run.event_at[i] if i < run.event_at.size() else INF
		var clock_state := TourChaos.State.PENDING
		if elapsed >= at:
			clock_state = TourChaos.State.STRUCK
		elif elapsed >= at - TourChaos.TELEGRAPH_SECONDS:
			clock_state = TourChaos.State.TELEGRAPHED
		var wire: int = run.event_state[i] if i < run.event_state.size() else TourChaos.State.PENDING
		var target: int = maxi(clock_state, wire)
		var shown: int = _shown_chaos[i]
		if target <= shown:
			continue
		if shown < TourChaos.State.TELEGRAPHED and target >= TourChaos.State.TELEGRAPHED:
			chaos_telegraphed.emit(i)
		if shown < TourChaos.State.STRUCK and target >= TourChaos.State.STRUCK:
			chaos_struck.emit(i)
		_shown_chaos[i] = target


## For TourHud: the furthest state this peer has shown event `index` -- the clock-local
## `_shown_chaos`, or the wire's own `run.event_state`, whichever is further along.
func chaos_shown(index: int) -> int:
	if run == null or index < 0 or index >= run.events.size():
		return TourChaos.State.PENDING
	var wire: int = run.event_state[index] if index < run.event_state.size() else TourChaos.State.PENDING
	var shown: int = _shown_chaos[index] if index < _shown_chaos.size() else TourChaos.State.PENDING
	return maxi(shown, wire)


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
	# Only when this brief actually drew a chaos event: a brief that never had one (brief 0,
	# always; any other, by the odds) is scored exactly as it was before this feature existed.
	if not run.events.is_empty():
		var open_n: int = run.event_state.filter(func(s: int) -> bool: return s == TourChaos.State.STRUCK).size()
		samples["chaos"] = {"open": open_n, "total": run.events.size()}
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
	_draft = TourDeck.draw(rng, run.gear + run.curses, run.band_size, run.instruments)
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
	# Re-anchored every time, not just on a new brief: several publishes happen a brief (a flaw
	# fixed, a part landed), and each is a fresher, more accurate "where the host's clock really
	# is right now" than the last.
	if run != null:
		_anchor_elapsed = run.seconds_total - run.seconds_left
		_anchor_usec = Time.get_ticks_usec()
	var key := _chaos_key(run) if run != null else ""
	if key != _shown_for_key:
		_shown_for_key = key
		_shown_chaos = []


func _on_tour_asked(verb: StringName, args: Array, _from: int) -> void:
	if not Session.is_authority():
		return
	if verb == &"draft_pick" and args.size() == 1:
		pick_draft(int(args[0]))


## `peer_id` left the room: mid-brief, every part they held goes open, for `_tick_parts` to
## hand on once the grace has run out; and whatever state the run is in, an instrument marked
## for them is unmarked -- a marked instrument nobody can hold is a brick, not a job, and a
## leaver during the draft would otherwise leave one behind. Host only, like every other
## mutation of `run`.
func _on_participant_left(peer_id: int) -> void:
	if run == null or not Session.is_authority():
		return
	if run.state == TourRun.State.BRIEF:
		TourParts.open(run, peer_id)
	for i in run.instrument_bound.size():
		if run.instrument_bound[i] == peer_id:
			run.instrument_bound[i] = 0
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
				_draft = TourDeck.draw(rng, run.gear + run.curses, run.band_size, run.instruments)
				run.draft.assign(_draft.map(func(c: TourCard) -> StringName: return c.id))
				drafting_started.emit(_draft)
				_publish()
		&"chaos":
			if run == null:
				start_run()
			if run != null and run.brief_index == 0:
				# Never on brief 0 in real play, so the shot is honest about what a band actually sees.
				_start_brief(1)
			if run == null:
				return
			var brief := TourBriefs.brief(run.brief_index)
			run.tuning = false
			run.seconds_total = brief.seconds
			run.seconds_left = run.seconds_total - 20.0
			run.events = [&"power_flicker", &"crowd_throws"]
			run.event_track = [TourChaos.pick_track(run.chaos_rng(run.brief_index), DAW.state, []),
					TourProject.BAND.find("Strings") + 1]
			run.event_at = [19.0, 21.5]
			run.event_state = [TourChaos.State.PENDING, TourChaos.State.PENDING]
			# Twice, as two physics frames would: the state machine advances one step a tick
			# (PENDING -> TELEGRAPHED -> STRUCK), so the first call telegraphs both (20 s is
			# already past each one's TELEGRAPH_SECONDS) and the second strikes event 0 (20 >=
			# its own 19) while event 1 (at 21.5) is still only telegraphed. One line ends up XX,
			# the other !!.
			_tick_chaos()
			_tick_chaos()
			# TourHud only rebuilds its chaos lines off this signal (the host never hears its own
			# `Session.tour_changed`, and `_process`'s per-frame refresh updates existing labels,
			# it does not add or remove them) -- without it the card would still be showing
			# whatever `_start_brief(1)` actually drew, not the two forced here.
			brief_started.emit(run.brief_index)
			_publish()
