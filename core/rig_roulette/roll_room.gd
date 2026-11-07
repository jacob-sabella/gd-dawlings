class_name RollRoom
extends RefCounted

## The studio's Rig Roulette: the PRESET/SCREEN wheels on the setup wall (`RigRouletteStation`), the roll board on the control room wall, and rolling, remembering and undoing a roll
## (docs/architecture.md). Moved out of `scenes/studio.gd` without change of behaviour: the state (`roll_settings`,
## `roll_presets_path`, `rig_roulette_station`, the board) stays on the studio, which delegates to this for the calls other code makes.

## How much bigger the setup wall in the room is than the panel it was.
const SETUP_WALL_SCALE := 2.9

var _roll_shown := 0

## How many rolls back an undo can go.
const ROLL_HISTORY_MAX := 8

## What the project was before each roll, newest last: {file, original, prev_roll}.
var _roll_history: Array = []

var _history_swept := false

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


## The panel on the control room wall: works against whichever DAW backend is open, not gated to
## the built-in engine the way Tour is, so it is built unconditionally alongside the case.
func _build_rig_roulette_station() -> void:
	if not studio.roulette_enabled:
		return
	_build_roll_board()
	_stand_the_setup_wall()
	Session.roll_changed.connect(_on_session_roll_changed)
	Session.roll_setup_changed.connect(_on_session_roll_setup_changed)
	studio.venue_changed.connect(func(_id): _build_roll_board())
	studio.venue_changed.connect(func(_id): _stand_the_setup_wall())


## The setup wall (`RigRouletteStation`) stands in the Rig Roulette room and nowhere else: the
## venues have a door instead (`RouletteDoor`). It is a child of the venue, so it goes when the
## venue does; its wheels start from `roll_settings` and write back to it.
func _stand_the_setup_wall() -> void:
	studio.rig_roulette_station = null
	if studio.venue == null or not studio.venue_switch.in_roulette_room():
		return
	var wall := RigRouletteStation.new()
	wall.name = "SetupWall"
	if not Session.is_authority() and not Session.roll_setup.is_empty():
		studio.roll_settings = RollSettings.from_dict(Session.roll_setup)
	wall.read_only = not Session.is_authority()
	wall.count = studio.roll_settings.count
	wall.pool = studio.wall_pool(studio.roll_settings.pool)
	wall.key_locked = studio.roll_settings.key_locked
	wall.per_track_cap = studio.roll_settings.per_track_cap
	wall.no_repeats = studio.roll_settings.no_repeats
	wall.scales = int(studio.roll_settings.scales)
	wall.near_semitones = studio.roll_settings.near_semitones
	wall.replay_last = studio.roll_settings.replay_last
	wall.reroll_limit = studio.roll_settings.reroll_limit
	wall.chaos = studio.roll_settings.chaos
	wall.tempo_pick = studio.roll_settings.tempo_pick
	wall.weights = studio.roll_settings.weights.duplicate()
	wall.transform = studio.venue.rig_roulette_spot()
	# A wall for the whole room to read from the seat, not a panel to stand at.
	wall.scale = Vector3.ONE * SETUP_WALL_SCALE
	wall.roll_requested.connect(_on_rig_roulette_roll_requested)
	wall.changed.connect(func() -> void:
		if not Session.is_authority():
			# Only the host sets the roll: a guest's nudge is put back to the host's word.
			wall.apply_settings(studio.roll_settings)
			Session.notice.emit("Only %s can change the roll." % Session.name_of(1))
			return
		var s := wall.settings()
		studio.roll_settings.count = s.count
		studio.roll_settings.pool = s.pool
		studio.roll_settings.key_locked = s.key_locked
		studio.roll_settings.per_track_cap = s.per_track_cap
		studio.roll_settings.no_repeats = s.no_repeats
		studio.roll_settings.scales = s.scales
		studio.roll_settings.near_semitones = s.near_semitones
		studio.roll_settings.replay_last = s.replay_last
		studio.roll_settings.reroll_limit = s.reroll_limit
		studio.roll_settings.chaos = s.chaos
		studio.roll_settings.tempo_pick = s.tempo_pick
		studio.roll_settings.weights = s.weights
		Session.publish_roll_setup(studio.roll_settings.to_dict()))
	wall.preset_sources = _preset_choices
	wall.undo_requested.connect(undo_the_roll)
	wall.preset_chosen.connect(func(id: int) -> void: _on_preset_chosen(wall, id))
	wall.preset_save_requested.connect(func() -> void: _on_preset_save_requested(wall))
	wall.screen_sources = func() -> Array:
		var out := []
		var sources := board_sources()
		for i in sources.size():
			out.append([i, "SCREEN: " + studio.board_title(sources[i])])
		return out
	wall.screen_chosen.connect(func(i: int) -> void:
		var sources := board_sources()
		if i >= 0 and i < sources.size():
			choose_board_source(sources[i]))
	studio.venue.add_child(wall)
	wall.set_free_standing(true)
	studio.rig_roulette_station = wall
	if not Session.roll.is_empty():
		wall.show_result(Session.roll["tracks"], Session.roll["pedals"].size(), Session.roll["key"])
	if wall.screen_wheel != null:
		wall.screen_wheel.choice = maxi(board_sources().find(studio.board_source), 0)
		wall.screen_wheel.refresh()


## The PRESET wheel's list: a resting word, the ones that ship, the saved slots.
func _preset_choices() -> Array:
	var out := [[0, "PRESETS"]]
	var built := RollPresets.built_in()
	for i in built.size():
		out.append([1 + i, "LOAD: " + built[i][0]])
	var slots := RollPresets.saved(studio.roll_presets_path)
	for i in slots.size():
		out.append([1 + built.size() + i, "LOAD MINE %d: %s" % [i + 1, "EMPTY" if slots[i].is_empty() else RollPresets.name_of(slots[i])]])
	return out


## A preset was picked: the host's settings become it (seed apart), told to the room.
func _on_preset_chosen(wall: RigRouletteStation, id: int) -> void:
	if id == 0:
		return
	if not Session.is_authority():
		Session.notice.emit("Only %s can change the roll." % Session.name_of(1))
		wall.apply_settings(studio.roll_settings)
		return
	var built := RollPresets.built_in()
	var d: Dictionary = {}
	if id <= built.size():
		d = built[id - 1][1]
	else:
		var slots := RollPresets.saved(studio.roll_presets_path)
		var slot := id - 1 - built.size()
		if slot >= 0 and slot < slots.size():
			d = slots[slot]
	if d.is_empty():
		Session.notice.emit("That slot is empty: set the wheels and press SAVE.")
		return
	var loaded := RollSettings.from_dict(d)
	loaded.seed_value = studio.roll_settings.seed_value
	studio.roll_settings = loaded
	wall.apply_settings(studio.roll_settings)
	Session.publish_roll_setup(studio.roll_settings.to_dict())


func _on_preset_save_requested(wall: RigRouletteStation) -> void:
	if not Session.is_authority():
		Session.notice.emit("Only %s can save a preset." % Session.name_of(1))
		return
	var at := RollPresets.save(studio.roll_settings, studio.roll_presets_path)
	wall.preset_wheel.refresh()
	Session.notice.emit("Saved as mine %d: %s." % [at + 1, RollPresets.name_of(studio.roll_settings.to_dict())])


## The board the roll is written up on, built again for each venue: how it is drawn and whether
## it stands on its own posts are the venue's to say.
func _build_roll_board() -> void:
	if studio.roll_board != null:
		studio.studio_set.remove_child(studio.roll_board)
		studio.roll_board.queue_free()
	studio.roll_board = RollBoard.new()
	studio.roll_board.landed.connect(_on_roll_result_landed)
	studio.roll_board.chalky = studio.venue.roll_board_chalky()
	studio.roll_board.free_standing = studio.venue.back_wall_gear_stands()
	studio.roll_board.transform = studio.venue.roll_board_spot()
	studio.roll_board.rich = studio.venue_switch.rich_rendering()
	studio.roll_board.environment_from = studio.world_env.environment if studio.world_env != null else null
	studio.studio_set.add_child(studio.roll_board)
	_on_session_roll_changed()
	_show_board(studio.board_source)


## Everything the big board can show, the write-up first.
func board_sources() -> Array[StringName]:
	var out: Array[StringName] = [&""]
	if studio.mount != null:
		for id in studio.mount.mounted_ids():
			out.append(id)
	return out


## Someone here chose what the big board shows: done at once, and the room asked (or told, by
## the host) so every screen in it shows the same.
func choose_board_source(source: StringName) -> void:
	if source == studio.board_source or not board_sources().has(source):
		return
	if Session.is_authority():
		_show_board(source)
		studio.room_rows._publish_room()
	else:
		studio.room_rows._predict(&"board_source", [source])
		_show_board(source)


func _show_board(source: StringName) -> void:
	if not board_sources().has(source):
		source = &""
	studio.board_source = source
	if studio.roll_board != null:
		studio.roll_board.show_source(studio.mount.surface(source) if source != &"" else null, studio.board_title(source))
	if studio.rig_roulette_station != null and studio.rig_roulette_station.screen_wheel != null:
		studio.rig_roulette_station.screen_wheel.choice = board_sources().find(source)
		studio.rig_roulette_station.screen_wheel.refresh()


## The host's word on the roll's settings reached this guest: kept, and shown on the wall.
func _on_session_roll_setup_changed() -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	if Session.is_authority():
		return
	studio.roll_settings = RollSettings.from_dict(Session.roll_setup)
	if studio.rig_roulette_station != null:
		studio.rig_roulette_station.apply_settings(studio.roll_settings)


## A result landed on the board: a thud, higher each time, and the wheel on the floor spun up.
func _on_roll_result_landed(step: int, of: int) -> void:
	Foley.play(studio.roll_board, Foley.board_thud(step), -6.0, 0.8 + 0.5 * float(step) / float(of))
	if studio.venue.has_method("pulse"):
		studio.venue.pulse(1.0 if step < of else 0.4)


## `Session.roll` changed (the host's own roll, or word of it reaching a guest): the board and
## the panel's own line say what it was.
func _on_session_roll_changed() -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	# A roll not seen yet lands part by part; the same one sent again (a guest admitted late) is
	# simply written up.
	var n: int = Session.roll.get("n", 0)
	var fresh := n != 0 and n != _roll_shown
	_roll_shown = n
	studio.roll_board.show_roll(Session.roll, fresh)
	if fresh and studio.venue.has_method("pulse"):
		studio.venue.pulse(1.0)
	if not Session.roll.is_empty() and studio.rig_roulette_station != null:
		studio.rig_roulette_station.show_result(Session.roll["tracks"], Session.roll["pedals"].size(), Session.roll["key"])


## RigRouletteStation.roll_requested: told so only the host can roll, the same pattern
## `choose_venue` and `_on_tour_case_struck` both use.
func _on_rig_roulette_roll_requested() -> void:
	if not studio.roulette_enabled:
		return
	if not Session.is_authority():
		Session.notice.emit("Only %s can roll the rig." % Session.name_of(1))
		return
	_roll_rig()


## The roll itself, host-only by the time this runs (`_on_rig_roulette_roll_requested`'s own
## gate): refused while the open project has changes no save has kept, since it starts a NEW
## project. The roll is worked out by `RigRoll` from the panel's settings (fresh randomness
## unless a seed is set -- nothing to do with a Tour run's own seed); this starts the project and
## puts the effects on. The key is only named, never applied: the project is empty, so there is
## no note to move. The rolled project is the starting point, not an edit, so it counts as saved
## and can be rolled again untouched.
func _roll_rig() -> void:
	if DAW.has_unsaved_changes():
		Session.notice.emit("Save the project first: a roll starts a new one.")
		return
	var limit := studio.roll_settings.reroll_limit
	if limit >= 0 and studio._rolls_this_visit > limit:
		Session.notice.emit("No re-rolls left: write the song with this one.")
		return
	# Every roll runs off a seed of its own, so the board can say it and the band can replay it.
	var settings := RollSettings.from_dict(studio.roll_settings.to_dict())
	settings.seed_value = RigRoll.seed_for(settings, int(Session.roll.get("seed", 0)))
	var rng := RigRoll.rng_for(settings)
	var tracks := RigRoll.track_count(rng)
	var before := _remember_before_roll()
	var refused := DAW.new_project(tracks)
	if not refused.is_empty():
		_forget(before)
		Session.notice.emit("Could not start the new project: %s" % "; ".join(refused))
		return

	var indices: Array = []
	for i in DAW.state.track_indices():
		indices.append(i)
	var plan := RigRoll.plan(settings, rng, indices, _rig_roulette_pool(settings), str(Session.roll.get("key", "")))
	# The project is empty, so a new tempo has no item to leave behind in time.
	var tempo: int = plan["tempo"]
	if tempo > 0:
		DAW.set_tempo(float(tempo))
	var landed := 0
	var pedals: Array = []
	for p in plan["pedals"]:
		DAW.add_fx(int(p["track"]), str(p["plugin"]), -1)
		landed += 1
		var added: MixState.FXState = DAW.state.track(int(p["track"])).fx.values()[-1]
		_throw_the_knobs(int(p["track"]), added, rng, settings.chaos)
		pedals.append({"track": DAW.state.track(int(p["track"])).display_name(), "fx": added.name})
	var key: String = plan["key"]
	DAW.mark_clean()
	studio._rolls_this_visit += 1
	# The board is for the write-up now, whatever it was showing.
	_show_board(&"")
	studio.room_rows._publish_room()

	if not before.is_empty():
		_roll_history.append(before)
		while _roll_history.size() > ROLL_HISTORY_MAX:
			_forget(_roll_history.pop_front())
	Session.publish_roll({"by": Session.name_of(Session.local_peer_id), "n": Session.roll.get("n", 0) + 1, "past": _past_rolls(),
			"tracks": tracks, "key": key, "pedals": pedals, "seed": settings.seed_value, "chaos": settings.chaos, "tempo": tempo,
			"left": -1 if limit < 0 else limit - studio._rolls_this_visit + 1})
	var msg := "%s rolled a new project: %d tracks, %d pedal%s" % [Session.name_of(Session.local_peer_id), tracks,
			landed, "" if landed == 1 else "s"]
	if not key.is_empty():
		msg += ", key of %s" % key
	if tempo > 0:
		msg += ", %d BPM" % tempo
	Session.tell_room(msg + ".")


## A landed pedal's knobs thrown by the chaos, off the roll's own generator so a replay throws them
## the same. The pedal's parameters as the engine reports them; a DAW that has not listed any (Reaper
## gives only the current bank) is left alone.
func _throw_the_knobs(track: int, fx: MixState.FXState, rng: RandomNumberGenerator, chaos: int) -> void:
	if chaos <= 0:
		return
	var params := fx.params.keys()
	params.sort()
	for param in params:
		DAW.set_fx_param(track, fx.index, int(param), RigRoll.knob(rng, float(fx.params[param]), chaos))


## The project as it stands, kept aside before a roll replaces it, so an undo can bring it back.
## Only the built-in engine and its stand-in own project files; against Reaper there is nothing
## to keep, so a roll there cannot be undone (and the wall says so when asked).
func _remember_before_roll() -> Dictionary:
	if not DAW.backend is OfflineBackend:
		return {}
	if not _history_swept:
		# What an earlier run left (a quit, a crash) is no history of this one.
		_history_swept = true
		for f in DirAccess.get_files_at("user://roll_history"):
			DirAccess.remove_absolute("user://roll_history".path_join(f))
	var file := "user://roll_history/before_%d_%d.%s" % [Time.get_ticks_msec(), _roll_history.size(), ProjectFiles.EXTENSION]
	if not ProjectFiles.save(DAW.backend, file, true).is_empty() and not FileAccess.file_exists(file):
		return {}
	return {"file": file, "original": DAW.backend.project_path, "prev_roll": Session.roll.duplicate(true)}


func _forget(entry: Dictionary) -> void:
	if not entry.is_empty():
		DirAccess.remove_absolute(entry["file"])


## The rolls before the one on the board, newest first, a few of them.
func _past_rolls() -> Array:
	var out := []
	for i in range(_roll_history.size() - 1, -1, -1):
		var prev: Dictionary = _roll_history[i]["prev_roll"]
		if not prev.is_empty():
			out.append(studio.roll_summary(prev))
		if out.size() >= 3:
			break
	return out


## Host: put the project back as it was before the last roll. Refused with changes no save has
## kept, as a roll is, since it replaces the project.
func undo_the_roll() -> void:
	if not Session.is_authority():
		Session.notice.emit("Only %s can undo a roll." % Session.name_of(1))
		return
	if _roll_history.is_empty():
		Session.notice.emit("Nothing to undo." if DAW.backend is OfflineBackend else "This engine cannot undo a roll.")
		return
	if DAW.has_unsaved_changes():
		Session.notice.emit("Save the project first: undoing a roll replaces it.")
		return
	var entry: Dictionary = _roll_history.back()
	var refused := DAW.open_project(entry["file"])
	if not refused.is_empty():
		Session.notice.emit("Could not bring it back: %s" % "; ".join(refused))
		return
	_roll_history.pop_back()
	# It is the project it was, not the file it was kept in.
	DAW.backend.project_path = entry["original"]
	DAW.backend.name_project()
	DAW.backend.mark_clean()
	_forget(entry)
	studio._rolls_this_visit = maxi(studio._rolls_this_visit - 1, 0)
	var prev: Dictionary = entry["prev_roll"].duplicate(true)
	if not prev.is_empty():
		prev["past"] = _past_rolls()
	_roll_shown = int(prev.get("n", 0))
	studio.room_rows._publish_room()
	Session.publish_roll(prev)
	Session.tell_room("%s undid the roll." % Session.name_of(Session.local_peer_id))


## The effects a roll may land: CHARACTER draws only the character kinds out of
## `DAW.state.fx_choices`; EVERYTHING, or any pool against a live Reaper list (no kind metadata to
## filter by), is the whole thing.
func _rig_roulette_pool(settings: RollSettings) -> Array:
	return RigRoll.pool_of(settings, DAW.state.fx_choices, not DAW.backend is ReaperBackend)


static func wall_pool(pool: RollSettings.Pool) -> RigRouletteStation.Pool:
	return int(pool) as RigRouletteStation.Pool


## The roll board's heading for a roll `source`: ROLL for none, FX RACK, TAPE DECK, else the name in capitals.
static func board_title(source: StringName) -> String:
	match source:
		&"": return "ROLL"
		&"rack": return "FX RACK"
		&"tape_deck": return "TAPE DECK"
	return String(source).replace("_", " ").to_upper()


## A roll in a few words, for the board's list of the ones before.
static func roll_summary(roll: Dictionary) -> String:
	var key: String = roll.get("key", "")
	return "#%d  %d tracks, %d pedal%s%s" % [roll.get("n", 0), roll.get("tracks", 0), (roll.get("pedals", []) as Array).size(),
			"" if (roll.get("pedals", []) as Array).size() == 1 else "s", (", " + key) if not key.is_empty() else ""]
