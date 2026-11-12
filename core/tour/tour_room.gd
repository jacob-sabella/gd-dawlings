class_name TourRoom
extends RefCounted

## What the room does for a Tour run: the chained case, the run starting and ending, the instruments the run spills
## and the chaos it telegraphs, strikes and lets fix (`core/tour/tour.gd` owns the run itself). Moved out of
## `scenes/studio.gd` without change of behaviour; the state stays on the studio, which delegates the calls other code makes.

## Up to three of the room's loose, unheld things, thrown in from the back of house at the desk:
## the room's own flight (ItemRoom.fly), so a guest sees exactly the same throw through the room
## state -- nothing new rides the wire. Seeded off the run, so a replay throws the same things at
## the same spots. Host only: the room is the host's.
const CROWD_PROPS: Array[StringName] = [&"duck", &"ball", &"toy", &"plane"]

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


## The case that starts a Tour run, chained in the back of house. The small hook the studio
## gives Tour (docs/architecture.md): everything past "it broke" or "the run is over" is
## core/tour/tour.gd's.
func _build_tour_case() -> void:
	if not Tour.enabled:
		return
	studio.tour_case = TourCase.new()
	studio.studio_set.add_child(studio.tour_case)
	studio.tour_case.transform = studio.venue_switch._venue_to_set(studio.venue.tour_case_spot())
	studio.tour_case.local_peer = func() -> int: return Session.local_peer_id
	if studio.items != null:
		studio.items.targets = [{"node": studio.tour_case, "radius": TourCase.STRIKE_RADIUS}]
	studio.tour_case.break_attempted.connect(_on_tour_case_struck)
	studio.tour_case.broken_open.connect(_on_tour_case_broken_open)
	Tour.run_started.connect(_on_tour_run_started)
	Tour.run_ended.connect(_on_tour_run_ended)
	Tour.brief_started.connect(_on_tour_brief_started)
	Tour.instrument_spilled.connect(_on_tour_instrument_spilled)
	Tour.chaos_telegraphed.connect(_on_tour_chaos_telegraphed)
	Tour.chaos_struck.connect(_on_tour_chaos_struck)
	Tour.flaw_fixed.connect(_on_tour_flaw_fixed)
	Tour.clock_low.connect(_on_tour_clock_low)
	Session.tour_changed.connect(_on_session_tour_changed)
	Session.participant_left.connect(_on_tour_participant_left)
	_sync_tour_roll()


## A thrown item has hit the case, broken or not (TourCase.break_attempted): told so only the
## host can start the tour, the same pattern `choose_venue` uses for the venue picker.
func _on_tour_case_struck() -> void:
	if not Session.is_authority():
		Session.notice.emit("Only %s can start the tour." % Session.name_of(1))


## The hit that broke the case: starts the run. `Tour.start_run()` is host-only and quiet about
## refusing (wrong engine, a run already under way, or simply not the host) -- nothing else
## here needs to check first.
func _on_tour_case_broken_open() -> void:
	if not Tour.is_available():
		Session.notice.emit("A tour needs the built-in engine: start dawlings with --built-in.")
		studio.tour_case.reset(Tour.unlocks.runs, Tour.unlocks.wins)
		return
	Tour.start_run()


## A run just started, on the host (`Tour.run_started`, which never fires on a guest -- see
## core/tour/tour.gd's class note): the case catches up broken, in case it is still chained --
## true after the normal five hits already burst it, but not after `start_run()` is reached some
## other way (tools/screenshot.gd's `--tour` flag, say). A no-op once it already is.
func _on_tour_run_started() -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	if studio.tour_case != null:
		studio.tour_case.sync_broken()
		if Tour.run != null:
			studio.tour_case.show_seed(Tour.run.attempt_seed)


## The run is over, won or lost: the case is chained again, its tally brought up to date, and the
## result told to the whole room (`Session.tell_room`, not `Session.notice.emit` -- this is
## host-only, unlike a chaos telegraph's every-peer-computes-it-itself pattern, so it has to
## reach a guest the same way a take's own placement notice does). Fires on the host the moment
## `Tour._end_run` runs -- never on a guest (see core/tour/tour.gd's class note) -- which is
## exactly why `tell_room` rather than `notice.emit` alone: a guest's own case still catches up
## from the emptied `Session.tour` (`_on_session_tour_changed`) below, but the result itself has
## no wire state of its own to read once the run is gone, only this one broadcast.
func _on_tour_run_ended(won: bool) -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	if studio.tour_case != null:
		studio.tour_case.reset(Tour.unlocks.runs, Tour.unlocks.wins)
		Foley.play(studio.tour_case, Foley.win_fanfare() if won else Foley.loss_sting())
	var line := "The gig's a hit. Reputation %d." % Tour.unlocks.reputation
	if not won:
		line = "That one got away. Lost a point -- Reputation %d." % Tour.unlocks.reputation
	Session.tell_room(line)
	# Back in the case: every instrument the run spilled stops existing here, the host's own
	# half of the reset (a guest's copies go with it too, off the emptied `Session.tour` --
	# `_sync_spilled`, through `_on_session_tour_changed` below).
	if studio.items != null:
		for id in studio.items.spawned_ids():
			studio.items.despawn(id)
		studio.player_host._publish_room_soon()
	_sync_tour_roll()
	# A run can end mid-`power_flicker`'s blackout (the boss brief lost with the lights still
	# out): never leave the room dark once there is no run left to light it back up for.
	studio.venue_look._relight()


## Host only (see core/tour/tour.gd's class note): a new brief is in, which may have a different
## tempo (and so a different bar length) than the last -- `_sync_tour_roll` re-reads it.
func _on_tour_brief_started(_index: int) -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	_sync_tour_roll()


## A guest's half of the same reset: the host's word on the run (`Session.tour`) went empty --
## or just arrived, in which case this guest's own case catches up broken (TourCase.sync_broken),
## in case this guest's own hits never reached it (someone else's throws, a dropped one, lag):
## "every guest sees it break" rides the run's synced state, not a local count. The host skips
## this half -- its own case already broke, from its own authoritative hits, if a run is under
## way at all.
func _on_session_tour_changed() -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	_sync_tour_roll()
	_sync_spilled()
	if studio.tour_case == null:
		return
	if Session.tour.is_empty():
		studio.tour_case.reset(Tour.unlocks.runs, Tour.unlocks.wins)
		studio.venue_look._relight()
	elif not Session.is_authority():
		studio.tour_case.sync_broken()
		# Off `Session.tour` directly, not `Tour.run`: `Tour`'s own `Session.tour_changed`
		# connection is made with `call_deferred` (core/tour/tour.gd's `_ready`), so `Tour.run`
		# is not guaranteed to have caught up to this signal yet when this handler runs.
		studio.tour_case.show_seed(int(Session.tour.get("attempt_seed", 0)))


## The host's own word on an instrument hitting the floor (`Tour.instrument_spilled`, which
## never reaches this guest's `Session.tour_changed` -- see Tour's own class note): the real
## item, thrown the same way everyone else sees it land.
func _on_tour_instrument_spilled(id: StringName, kind: StringName, curse: StringName, bound_to: int) -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	_spill_instrument(id, kind, curse, bound_to)


## Makes `id` (a copy of `kind`) a real item in the room, cursed and marked as the card said,
## and tosses it out of the case's open lid; everyone else sees the same flight off the room
## (`ItemRoom.state` carries the launch) -- the host's own half of a spill; a guest's is
## `_sync_spilled`, off the same facts riding `Session.tour`.
func _spill_instrument(id: StringName, kind: StringName, curse: StringName, bound_to: int) -> void:
	if studio.items == null or studio.tour_case == null:
		return
	var n := studio.items.spawned_ids().size()
	var home := _spill_home(n)
	var item := studio.items.spawn(kind, id, home)
	if item == null:
		return
	_dress_spilled(item, id, kind, curse, bound_to)
	var mouth := studio.tour_case.transform * Vector3(0, TourCase.BODY_H + 0.15, TourCase.CASE_DEPTH * 0.5 + 0.06)
	var seed := Tour.run.attempt_seed if Tour.run != null else 0
	studio.items.spill(item, mouth, home.origin, hash([String(id), seed]))
	_announce_spill(item, curse)
	studio.player_host._publish_room_soon()


## The case's thump and the toast, on every machine an instrument falls out on: the host's as
## it throws (`_spill_instrument`), a guest's as it learns of it (`_sync_spilled`) -- a reward
## nobody is told about is one nobody goes looking for.
func _announce_spill(item: Item, curse: StringName) -> void:
	Foley.play(studio.tour_case, Foley.case_toss())
	var low := item.item_title().to_lower()
	match curse:
		&"sour":
			Session.notice.emit("A %s fell out of the case, tuned sour." % low)
		&"low":
			Session.notice.emit("A %s fell out of the case, an octave low." % low)
		&"bound":
			Session.notice.emit("A %s fell out of the case, marked for %s: only they can hold it." % [low, item.bound_name])
		_:
			Session.notice.emit("A %s fell out of the case." % low)


## `item`'s voice, curse and mark, whichever of a fresh spill (`_spill_instrument`) or one a
## guest is only now catching up with (`_sync_spilled`) is asking.
func _dress_spilled(item: Item, id: StringName, kind: StringName, curse: StringName, bound_to: int) -> void:
	if item is InstrumentItem:
		var instrument := item as InstrumentItem
		instrument.voice = 1 if id != kind else 0
		match curse:
			&"sour":
				instrument.curse_pitch = 0.917
			&"low":
				instrument.curse_pitch = 0.5
	item.bound_to = bound_to
	item.bound_name = Session.name_of(bound_to) if bound_to != 0 else ""


## A half-ring 0.85m in front of the case, one spot per copy the case can ever spill
## (TourParts.SPILL_KINDS.size() * TourParts.COPIES, six today), so no two land on the same spot.
func _spill_home(n: int) -> Transform3D:
	var spots := TourParts.SPILL_KINDS.size() * TourParts.COPIES
	var a := lerpf(-1.2, 1.2, float(n) / float(maxi(spots - 1, 1)))
	return studio.tour_case.transform * Transform3D(Basis(Vector3.UP, PI + a), Vector3(sin(a) * 0.85, 0, cos(a) * 0.85))


## This guest's half of `Session.tour`'s `instruments`: spawn whatever is missing, despawn
## whatever is no longer wanted (the run ended), and bring every spill's mark up to date (a
## leaver's unbinding lands here too). Idempotent on the host as well, though the host's own
## spawns already happened off `Tour.instrument_spilled` -- this only ever finds them already
## there.
func _sync_spilled() -> void:
	if studio.items == null:
		return
	var run := TourRun.from_dict(Session.tour) if not Session.tour.is_empty() else null
	var want: Array[StringName] = []
	if run != null:
		want = run.instruments
	for id in studio.items.spawned_ids():
		if not (id in want):
			studio.items.despawn(id)
	if run == null:
		return
	var spawned_any := false
	for i in run.instruments.size():
		var id: StringName = run.instruments[i]
		var item: Item = studio.items.items.get(id)
		if item == null:
			var kind := TourParts.kind_of(id)
			item = studio.items.spawn(kind, id, _spill_home(studio.items.spawned_ids().size()))
			if item == null:
				continue
			_dress_spilled(item, id, kind, run.instrument_curses[i], run.instrument_bound[i])
			# The host already said so as it threw; this is a guest hearing it land.
			if not Session.is_authority() and studio.tour_case != null:
				_announce_spill(item, run.instrument_curses[i])
			spawned_any = true
		else:
			var bound: int = run.instrument_bound[i]
			item.bound_to = bound
			item.bound_name = Session.name_of(bound) if bound != 0 else ""
	if spawned_any:
		studio.room_rows.apply_room(Session.room, false)


## A hand here was refused an item it is not marked for (ItemRoom.refused, Item.may_hold): the
## same toast a claimed fader gives a second hand.
func _on_item_refused(item: Item, _why: String) -> void:
	Session.notice.emit("Only %s can hold the %s." % [item.bound_name, item.item_title().to_lower()])


## A personal copy was just spawned and bound (ItemRoom.personal_taken): whose it is, which
## stays out of item_room.gd the way `local_peer` does, for the same reason
## (`core/items/item_room.gd`'s own `PERSONAL_KINDS` note).
func _on_item_personal_taken(item: Item) -> void:
	item.bound_name = Session.name_of(item.bound_to) if item.bound_to != 0 else ""


## A peer left the session: any instrument marked for them is nobody's to be marked for any
## more. `Tour._on_participant_left` clears the run's own record (`run.instrument_bound`); this
## clears the real item's here on the host, so a hand can take it up at once rather than it
## staying a brick until the next spill or sync happens to touch it. A personal copy is not
## something anyone else could take up anyway (its id names only the one peer it was ever for),
## so it is retired instead of left bound to someone no longer in the room.
func _on_tour_participant_left(peer_id: int) -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	if studio.items == null or not Session.is_authority():
		return
	for id in studio.items.spawned_ids():
		var item: Item = studio.items.items.get(id)
		if item == null or item.bound_to != peer_id:
			continue
		if studio.items.is_personal_copy(id):
			studio.items.despawn(id)
		else:
			item.bound_to = 0
			item.bound_name = ""


## A running take is sent (and a fresh one begun) about every bar while a brief needs its parts
## ticked live, rather than only when recording stops (Tour.take_roll_seconds). Read from
## `Tour.run`, correct on both sides (live on the host, rebuilt from `Session.tour` on a guest),
## so this one sync point covers Tour's own signals and `Session.tour_changed` alike.
func _sync_tour_roll() -> void:
	var seconds := Tour.take_roll_seconds()
	if studio.hit_recorder != null:
		studio.hit_recorder.roll_every = seconds
	if Session.guest_midi != null:
		Session.guest_midi.roll_every = seconds


## A chaos event's telegraph, on EVERY peer, from their own clock (Tour.chaos_telegraphed is the
## one signal pair here that is not host-only -- see Tour's own class note): the room says so
## before it happens, so getting hit by one is never a surprise from nowhere. `crowd_throws`
## warns with a rumble from the back of house, where the crowd actually is; everything else
## warns from the case itself, the run's own corner of the room.
func _on_tour_chaos_telegraphed(index: int) -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	var run := Tour.run
	if run == null or index < 0 or index >= run.events.size():
		return
	var event := TourChaos.by_id(run.events[index])
	if event == null or studio.tour_case == null:
		return
	studio.venue_look._flicker_lights()
	studio.tour_case.rattle()
	if event.id == &"crowd_throws":
		_play_at(_crowd_house_point(), Foley.crowd_rumble(0))
	else:
		Foley.play(studio.tour_case, Foley.chaos_warning())
	var track: int = run.event_track[index] if index < run.event_track.size() else 0
	Session.notice.emit(event.telegraph_for(run, track))


## The strike itself, on every peer: the sound everywhere, and whichever of the events here has
## a presentation of its own on top of the desk's own verb landing through ordinary replication
## (every other event's strike is nothing but a DAW verb, already shown by the strip it moved).
func _on_tour_chaos_struck(index: int) -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	var run := Tour.run
	if run == null or index < 0 or index >= run.events.size():
		return
	var id: StringName = run.events[index]
	if studio.tour_case != null:
		Foley.play(studio.tour_case, Foley.chaos_strike())
	match id:
		&"power_flicker":
			studio.venue_look._lights_out(Tour.take_roll_seconds() * TourChaos.LIGHTS_OUT_BARS)
		&"crowd_throws":
			if Session.is_authority():
				_throw_crowd_things(index)


## A flaw just turned fixed, on every peer from their own copy of `run.fixed` (Tour.flaw_fixed is
## not host-only -- see Tour's own class note by `chaos_telegraphed`): the crowd cheers from the
## back of house, the band's own job landing somewhere the room can hear it, on top of the HUD's
## line already flipping to ACCENT the same tick.
func _on_tour_flaw_fixed(index: int) -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	_play_at(_crowd_house_point(), Foley.crowd_cheer(index % 3))


## The clock running out, on every peer from their own `brief_elapsed()` (Tour.clock_low is not
## host-only, the same reasoning as the chaos telegraph): the lid rattles for the whole of the
## brief's last `Tour.CLOCK_LOW_SECONDS` rather than a telegraph's short jitter -- the room living
## through the final stretch with the band, not just warning them it is coming.
func _on_tour_clock_low() -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	if studio.tour_case != null:
		studio.tour_case.rattle(Tour.CLOCK_LOW_SECONDS)
	Session.notice.emit("Ten seconds. Finish it.")


## Where the crowd is, in the frame the gear's floor plan is measured in: the back of house's
## centre, a little short of its far wall -- `crowd_throws`'s rumble comes from here, and so does
## the throw itself.
func _crowd_house_point() -> Vector3:
	if studio.venue == null:
		return Vector3.ZERO
	var rect := studio.venue.back_of_house()
	return Vector3(rect.position.x + rect.size.x * 0.5, 1.5, rect.end.y - 0.4)


## A one-shot emitter at an arbitrary point, for a sound that is not coming from any gear already
## standing there -- `crowd_rumble`, from the house rather than the case. Freed shortly after:
## long enough for the clip to finish, short enough not to litter the set over a busy run.
##
## `not is_inside_tree()`: several tests `remove_child` a studio without freeing it once they are
## done, leaving its signal connections (`Tour.flaw_fixed` among them, which now fires on every
## flaw a test's own brief happens to clear) live on a node with no `SceneTree` of its own --
## `get_tree()` would be null on exactly that node, same reasoning `_walk_to_seat` already needed
## this guard for.
func _play_at(point: Vector3, stream: AudioStream, volume_db := 0.0) -> void:
	if studio.studio_set == null or not studio.is_inside_tree():
		return
	var marker := Node3D.new()
	marker.position = point
	studio.studio_set.add_child(marker)
	Foley.play(marker, stream, volume_db)
	studio.get_tree().create_timer(1.5).timeout.connect(marker.queue_free)


func _throw_crowd_things(event_index: int) -> void:
	if studio.items == null or Tour.run == null:
		return
	var from := _crowd_house_point()
	var thrown := 0
	for kind in CROWD_PROPS:
		if thrown >= 3:
			break
		var item: Item = studio.items.items.get(kind)
		if item == null or item.carried_by != null or Session.holds.has(kind):
			continue
		if item.state != Item.State.HOME and item.state != Item.State.LOOSE:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([Tour.run.attempt_seed, event_index, thrown])
		var to := Vector3(rng.randf_range(-1.0, 1.0), 1.0, studio.TIMELINE_Z + 0.5)
		var spin := Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
		studio.items.fly(item, from, ItemRoom.lob(from, to, 6.0), spin, 1)
		thrown += 1
	if thrown > 0:
		studio.player_host._publish_room_soon()
