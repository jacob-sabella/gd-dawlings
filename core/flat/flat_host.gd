class_name FlatHost
extends DawKitHost

## The game's mix, as dawkit's 2D interface (DawKitStudio) reads it and asks it.
##
## The interface draws a DawKitProject and asks for changes by track id in decibels and pan
## -1..1. This answers from the state cache (`DAW.state`), whichever backend fills it -- the
## built-in engine, Reaper, or a guest's copy of the host's -- and asks `DAW` for every change,
## so an edit made here is an edit made at the desk: one undo step, sent to the host from a
## guest, refused where the desk would refuse it. Like ProjectBridge it is the game adapting to
## dawkit, never the reverse.
##
## The project is built from the cache when the interface next reads it after a change, so a
## frame of fader moves is one rebuild, not one per move.

var _project: DawKitProject
var _stale := true


func _init() -> void:
	DAW.project_replaced.connect(_restructured)
	DAW.track_added.connect(func(_i: int): _restructured())
	DAW.tracks_renumbered.connect(func(_m: Dictionary): _restructured())
	DAW.bank_changed.connect(_restructured)
	DAW.connection_changed.connect(_restructured)
	DAW.project_named.connect(_transport)
	DAW.track_changed.connect(_on_track_changed)
	DAW.fx_changed.connect(func(i: int, _fx: int): _on_track_changed(i, &"fx"))
	DAW.master_changed.connect(func(_f: StringName): _stale = true; track_changed.emit(DawKitProject.MASTER_ID))
	DAW.transport_changed.connect(_transport)
	DAW.timeline_changed.connect(func(): _stale = true; clips_changed.emit())
	DAW.project_saved.connect(_on_saved)
	DAW.render_finished.connect(_on_rendered)
	# What the session says (a guest's edit refused, someone else's save) is the status line's too.
	Session.notice.connect(func(text: String): said.emit(text))


func project() -> DawKitProject:
	if _stale or _project == null:
		_stale = false
		_project = snapshot(DAW.state)
	return _project


## The cache as a project: enough to draw it (names, colours, folders, levels, clips and their
## notes, the song's tempo, meter, loop and markers). Not ProjectBridge.capture, which needs the
## built-in engine and keeps everything a file must; this is the same for every backend.
static func snapshot(s: MixState) -> DawKitProject:
	var p := DawKitProject.new()
	if s == null:
		return p
	p.title = DAW.project_title() if DAW.backend != null else ""
	p.tempo = s.tempo
	p.tempo_points = s.tempo_points.map(func(pt): return [float(pt[0]), float(pt[1]), DawKitTempoMap.shape_of(pt[2])])
	if not p.tempo_points.is_empty():
		p.tempo_points[0][1] = s.tempo
	p.time_signature = Vector2i(s.beats_per_bar, s.beat_unit)
	p.time_signature_points = s.time_signature_points.duplicate(true)
	p.length = s.project_length
	p.metronome = s.metronome
	p.loop_on = s.looping
	p.loop_start = s.loop_start
	p.loop_end = s.loop_end
	# In time order: the 2D view names them by their place.
	var times: Array = s.markers.keys()
	times.sort()
	for t in times:
		p.markers.append(DawKitMarker.new(float(t), str(s.markers[t])))
	for r in s.regions:
		p.regions.append(DawKitRegion.new(float(r[0]), float(r[1]), str(r[2])))
	p.regions.sort_custom(func(a: DawKitRegion, b: DawKitRegion): return a.start < b.start)
	p.master.volume_db = s.master.volume_db
	p.master.pan = s.master.pan * 2.0 - 1.0
	var folders: Array[String] = []
	for index in s.track_indices():
		var t: MixState.TrackState = s.tracks[index]
		var out := DawKitTrack.new(ProjectBridge.id_of(index), t.name)
		out.colour = t.colour
		out.parent = folders.back() if not folders.is_empty() else ""
		out.volume_db = t.volume_db
		out.pan = t.pan * 2.0 - 1.0
		out.mute = t.mute
		out.solo = t.solo
		out.armed = t.rec_arm
		out.group = t.group
		for it in t.items:
			out.clips.append(ProjectBridge.clip_of(it))
		for fx_index in t.plugins():
			out.effects.append(effect_of(t.fx[fx_index]))
		for slot in send_slots(s, t):
			var sd: MixState.SendState = t.sends[slot]
			var send := DawKitSend.new()
			send.target = ProjectBridge.id_of(sd.resolve(s))
			send.volume_db = DAW.taper_to_db(sd.volume) if DAW.backend != null else 0.0
			send.pan = sd.pan * 2.0 - 1.0
			send.pre_fader = sd.pre_fader
			send.key = sd.key
			out.sends.append(send)
		for target in t.automation:
			var named := lane_name(t, str(target))
			if not named.is_empty():
				out.automation.append(DawKitAutomation.new(named, (t.automation[target] as Array).duplicate(true)))
		p.tracks.append(out)
		if t.folder_depth > 0:
			folders.append(out.id)
		else:
			for _i in -t.folder_depth:
				if not folders.is_empty():
					folders.pop_back()
	return p


## A desk lane's name as dawkit names it: a send by the track it goes to, an effect by its place
## among the track's plugins. "" for one the 2D view does not show.
static func lane_name(t: MixState.TrackState, target: String) -> String:
	if target.begins_with("send:"):
		return "send:" + ProjectBridge.id_of(int(target.substr(5)))
	if target.begins_with("fx:") or target.begins_with("enable:"):
		var parts := target.split(":")
		var at := t.plugins().find(int(parts[1]))
		if at < 0:
			return ""
		return "%s:%d" % [parts[0], at] + (":" + parts[2] if parts.size() > 2 else "")
	return target


## And back: dawkit's name for a lane as the desk names it, or "" for none.
static func desk_lane(t: MixState.TrackState, target: String) -> String:
	match DawKitAutomation.kind_of(target):
		"volume", "pan", "mute":
			return target
		"send":
			var index := ProjectBridge.index_of(target.substr(5))
			return "send:%d" % index if index > 0 else ""
		"enable", "fx":
			var parts := target.split(":")
			var slots := t.plugins()
			var at := int(parts[1])
			if at < 0 or at >= slots.size():
				return ""
			return "%s:%d" % [parts[0], slots[at]] + (":" + parts[2] if parts.size() > 2 else "")
	return ""


## A plugin slot as an effect: its name, on or bypassed, wet, and its controls by number.
static func effect_of(f: MixState.FXState) -> DawKitEffect:
	var e := DawKitEffect.new()
	e.kind = f.type
	e.name = f.name
	e.enabled = f.enabled
	e.wet = f.wet
	e.preset = f.preset
	var count := 0
	for k in f.controls():
		count = maxi(count, int(k) + 1)
	for i in count:
		e.values.append(float(f.params.get(i, 0.0)))
		e.names.append(str(f.param_names.get(i, "")))
	return e


## A track's sends that go to a track, in order of their slots: the project's sends, by place.
static func send_slots(s: MixState, t: MixState.TrackState) -> Array:
	var slots: Array = t.sends.keys()
	slots.sort()
	return slots.filter(func(slot: int) -> bool: return (t.sends[slot] as MixState.SendState).resolve(s) > 0)


func can(edit: StringName) -> bool:
	match edit:
		ARM:
			return DAW.can(DAWBackend.Capability.RECORD_ARM)
		MOVE_CLIP, SELECT, EDIT_CLIPS, NOTES:
			return DAW.can(DAWBackend.Capability.TIMELINE)
		TRACK_ORDER:
			return DAW.can(DAWBackend.Capability.TRACK_ORDER)
		EFFECTS:
			return not DAW.state.fx_choices.is_empty() if DAW.state != null else false
		EFFECT_ORDER:
			return DAW.can(DAWBackend.Capability.FX_CHAIN)
		SENDS:
			return DAW.can(DAWBackend.Capability.ROUTING)
		MARKERS:
			return DAW.can(DAWBackend.Capability.MARKERS)
		FILES:
			return Session.is_authority() and DAW.can(DAWBackend.Capability.PROJECT_FILES)
		SAVE:
			return DAW.can(DAWBackend.Capability.PROJECT_SAVE)
		RENDER:
			return DAW.can(DAWBackend.Capability.RENDER)
	return edit in [VOLUME, PAN, MUTE, SOLO, TRANSPORT, RECORD, SEEK, LOOP, METRONOME, TEMPO, UNDO, TRACKS,
			LOOP_RANGE, TEMPO_MAP, COUNT_IN, AUTOMATION]


func position() -> float:
	return DAW.state.position_seconds if DAW.state != null else 0.0


func is_playing() -> bool:
	return DAW.state != null and DAW.state.playing


func is_recording() -> bool:
	return DAW.state != null and DAW.state.recording


func meter(id: String) -> Vector2:
	var s := DAW.state
	if s == null:
		return Vector2.ZERO
	if id == DawKitProject.MASTER_ID:
		return Vector2(s.master.vu_l, s.master.vu_r)
	var t: MixState.TrackState = s.tracks.get(ProjectBridge.index_of(id))
	return Vector2(t.vu_l, t.vu_r) if t != null else Vector2.ZERO


func clip_peaks(id: String, clip_index: int) -> PackedByteArray:
	var t: MixState.TrackState = DAW.state.tracks.get(ProjectBridge.index_of(id)) if DAW.state != null else null
	if t == null or clip_index < 0 or clip_index >= t.items.size():
		return PackedByteArray()
	return (t.items[clip_index] as MixState.ItemState).peaks


func undo_name() -> String:
	var s := DAW.state
	if s == null or s.undo_depth <= 0 or s.undo_depth > s.undo_names.size():
		return ""
	return str(s.undo_names[s.undo_depth - 1])


func set_volume(id: String, db: float) -> void:
	var taper := DAW.db_to_taper(db)
	if id == DawKitProject.MASTER_ID:
		DAW.set_master_volume(taper)
	else:
		DAW.set_track_volume(ProjectBridge.index_of(id), taper)


func set_pan(id: String, pan: float) -> void:
	var p := clampf((pan + 1.0) * 0.5, 0.0, 1.0)
	if id == DawKitProject.MASTER_ID:
		DAW.set_master_pan(p)
	else:
		DAW.set_track_pan(ProjectBridge.index_of(id), p)


func set_mute(id: String, on: bool) -> void:
	if id != DawKitProject.MASTER_ID:
		DAW.set_track_mute(ProjectBridge.index_of(id), on)


func set_solo(id: String, on: bool) -> void:
	if id != DawKitProject.MASTER_ID:
		DAW.set_track_solo(ProjectBridge.index_of(id), on)


func set_armed(id: String, on: bool) -> void:
	if id != DawKitProject.MASTER_ID:
		DAW.set_track_rec_arm(ProjectBridge.index_of(id), on)


func play() -> void:
	DAW.transport_play()


func stop() -> void:
	DAW.transport_stop()


func record() -> void:
	DAW.transport_record()


func seek(seconds: float) -> void:
	DAW.seek(seconds)


func set_looping(on: bool) -> void:
	DAW.set_looping(on)


func set_metronome(on: bool) -> void:
	DAW.set_metronome(on)


func set_tempo(bpm: float) -> void:
	DAW.set_tempo(bpm)


func move_clip(id: String, clip_index: int, start: float, to_id := "") -> void:
	var to := ProjectBridge.index_of(to_id) if not to_id.is_empty() else 0
	DAW.move_item(ProjectBridge.index_of(id), clip_index, start, to)


func add_track(after_id := "", name := "") -> void:
	var at := ProjectBridge.index_of(after_id) + 1 if not after_id.is_empty() else DAW.state.track_indices().size() + 1
	DAW.add_track(at, name)


func remove_track(id: String) -> void:
	DAW.remove_track(ProjectBridge.index_of(id))


func duplicate_track(id: String) -> void:
	DAW.duplicate_track(ProjectBridge.index_of(id))


func rename_track(id: String, name: String) -> void:
	DAW.rename_track(ProjectBridge.index_of(id), name)


func set_track_colour(id: String, colour: Color) -> void:
	DAW.set_track_colour(ProjectBridge.index_of(id), colour)


func move_track(id: String, position: int, parent_id: String) -> void:
	DAW.move_track(ProjectBridge.index_of(id), position + 1, ProjectBridge.index_of(parent_id))


func effect_choices() -> Array:
	return DAW.state.fx_choices.duplicate() if DAW.state != null else []


func add_effect(id: String, choice: String, at := -1) -> void:
	var slot := _fx_slot(id, at) if at >= 0 else -1
	DAW.add_fx(ProjectBridge.index_of(id), choice, slot)


func remove_effect(id: String, index: int) -> void:
	var slot := _fx_slot(id, index)
	if slot >= 0:
		DAW.remove_fx(ProjectBridge.index_of(id), slot)


func move_effect(id: String, index: int, to_id: String, to_index: int) -> void:
	var slot := _fx_slot(id, index)
	var to := to_id if not to_id.is_empty() else id
	var to_t: MixState.TrackState = DAW.state.tracks.get(ProjectBridge.index_of(to)) if DAW.state != null else null
	if slot < 0 or to_t == null:
		return
	# The desk counts the place with the effect still in it, and takes the place before which it
	# goes; past the end is the end.
	var before := maxi(to_index, 0)
	if to == id and before > index:
		before += 1
	var slots := to_t.plugins()
	var to_slot: int = slots[before] if before < slots.size() else (int(slots.back()) + 1 if not slots.is_empty() else 0)
	DAW.move_fx(ProjectBridge.index_of(id), slot, ProjectBridge.index_of(to), to_slot)


func set_effect_enabled(id: String, index: int, on: bool) -> void:
	var slot := _fx_slot(id, index)
	if slot >= 0:
		DAW.set_fx_enabled(ProjectBridge.index_of(id), slot, on)


func set_effect_wet(id: String, index: int, wet: float) -> void:
	var slot := _fx_slot(id, index)
	if slot >= 0:
		DAW.set_fx_wet(ProjectBridge.index_of(id), slot, wet)


func set_effect_value(id: String, index: int, param: int, value: float) -> void:
	var slot := _fx_slot(id, index)
	if slot >= 0:
		DAW.set_fx_param(ProjectBridge.index_of(id), slot, param, clampf(value, 0.0, 1.0))


func effect_value_text(id: String, index: int, param: int) -> String:
	var f := _fx(id, index)
	if f == null or not f.param_text.has(param):
		return ""
	# The words only while they still describe where the control is.
	if f.param_text_at.has(param) and not is_equal_approx(float(f.param_text_at[param]), float(f.params.get(param, 0.0))):
		return ""
	return str(f.param_text[param])


func watch_effect(id: String, index: int) -> void:
	var slot := _fx_slot(id, index)
	var f := _fx(id, index)
	if slot >= 0 and f != null and f.param_list.is_empty() and not (DAW.backend is OfflineBackend):
		DAW.read_fx_params(ProjectBridge.index_of(id), slot)


func add_send(id: String, to_id: String) -> void:
	if to_id != id:
		DAW.create_send(ProjectBridge.index_of(id), ProjectBridge.index_of(to_id))


func remove_send(id: String, send_index: int) -> void:
	var slot := _send_slot(id, send_index)
	if slot > 0:
		DAW.remove_send(ProjectBridge.index_of(id), slot)


func set_send_level(id: String, send_index: int, db: float) -> void:
	var slot := _send_slot(id, send_index)
	if slot > 0:
		DAW.set_send_volume(ProjectBridge.index_of(id), slot, DAW.db_to_taper(db))


func set_send_pan(id: String, send_index: int, pan: float) -> void:
	var slot := _send_slot(id, send_index)
	if slot > 0:
		DAW.set_send_pan(ProjectBridge.index_of(id), slot, clampf((pan + 1.0) * 0.5, 0.0, 1.0))


func set_send_pre_fader(id: String, send_index: int, pre: bool) -> void:
	var slot := _send_slot(id, send_index)
	if slot > 0:
		DAW.set_send_pre_fader(ProjectBridge.index_of(id), slot, pre)


## The desk's plugin slot an effect is in, or -1.
func _fx_slot(id: String, index: int) -> int:
	var t: MixState.TrackState = DAW.state.tracks.get(ProjectBridge.index_of(id)) if DAW.state != null else null
	if t == null:
		return -1
	var slots := t.plugins()
	return slots[index] if index >= 0 and index < slots.size() else -1


func _fx(id: String, index: int) -> MixState.FXState:
	var slot := _fx_slot(id, index)
	return DAW.state.tracks[ProjectBridge.index_of(id)].fx[slot] if slot >= 0 else null


## The desk's send slot (from 1) a send is in, or 0.
func _send_slot(id: String, send_index: int) -> int:
	var t: MixState.TrackState = DAW.state.tracks.get(ProjectBridge.index_of(id)) if DAW.state != null else null
	if t == null:
		return 0
	var slots := send_slots(DAW.state, t)
	return slots[send_index] if send_index >= 0 and send_index < slots.size() else 0


func is_selected(id: String, clip_index: int) -> bool:
	var item := DAW.state.item(ProjectBridge.index_of(id), clip_index) if DAW.state != null else null
	return item != null and item.selected


func select_clip(id: String, clip_index: int, additive := false) -> void:
	DAW.select_item(ProjectBridge.index_of(id), clip_index, additive)


func clear_selection() -> void:
	DAW.clear_item_selection()


func split_selection(seconds: float) -> void:
	DAW.split_selected(seconds)


func delete_selection() -> void:
	DAW.delete_selected()


func duplicate_selection() -> void:
	DAW.duplicate_selected()


func trim_clip(id: String, clip_index: int, start: float, end: float) -> void:
	DAW.trim_item(ProjectBridge.index_of(id), clip_index, start, end)


func set_clip_fades(id: String, clip_index: int, fade_in: float, fade_out: float) -> void:
	DAW.set_item_fades(ProjectBridge.index_of(id), clip_index, fade_in, fade_out)


func set_clip_gain(id: String, clip_index: int, db: float) -> void:
	DAW.set_item_gain(ProjectBridge.index_of(id), clip_index, db)


func set_clip_muted(id: String, clip_index: int, muted: bool) -> void:
	DAW.set_item_muted(ProjectBridge.index_of(id), clip_index, muted)


func insert_note(id: String, clip_index: int, on: float, off: float, pitch: int) -> void:
	DAW.insert_note(ProjectBridge.index_of(id), clip_index, on, off, pitch)


func delete_note(id: String, clip_index: int, note: int) -> void:
	DAW.delete_note(ProjectBridge.index_of(id), clip_index, note)


## The desk moves a note by so many seconds and by so many semitones, as two edits: the pitch
## first, since that leaves the note where it is among the others, then the time.
func move_note(id: String, clip_index: int, note: int, on: float, pitch: int) -> void:
	var track := ProjectBridge.index_of(id)
	var item := DAW.state.item(track, clip_index) if DAW.state != null else null
	var at := note * MidiTake.NOTE_WIDTH
	if item == null or note < 0 or at + MidiTake.NOTE_WIDTH > item.notes.size():
		return
	var by := clampi(pitch, 0, 127) - int(item.notes[at + 2])
	if by != 0:
		DAW.transpose_note(track, clip_index, note, by)
	if not is_equal_approx(on, item.notes[at]):
		DAW.move_note(track, clip_index, note, on - float(item.notes[at]))


func set_note_end(id: String, clip_index: int, note: int, off: float) -> void:
	DAW.set_note_end(ProjectBridge.index_of(id), clip_index, note, off)


func set_note_velocity(id: String, clip_index: int, note: int, velocity: int) -> void:
	DAW.set_note_velocity(ProjectBridge.index_of(id), clip_index, note, velocity)


func quantize_clip(id: String, clip_index: int, grid_beats: float) -> void:
	DAW.quantize_item(ProjectBridge.index_of(id), clip_index, grid_beats)


## Where the files opened and saved lately are listed, for the 2D view's FILE menu.
const RECENT_FILE := "user://recent_projects.cfg"
const RECENT_MAX := 8


func project_file() -> String:
	var path := DAW.project_file() if DAW.backend != null else ""
	return path if not path.is_empty() else (DAW.project_file_name() if DAW.backend != null else "")


func is_dirty() -> bool:
	return DAW.backend != null and DAW.has_unsaved_changes()


func recent_files() -> PackedStringArray:
	var cfg := ConfigFile.new()
	if cfg.load(RECENT_FILE) != OK:
		return PackedStringArray()
	var listed: PackedStringArray = cfg.get_value("recent", "files", PackedStringArray())
	return PackedStringArray(Array(listed).filter(func(path: String) -> bool: return FileAccess.file_exists(path)))


## Puts `path` first among the recent files.
static func remember(path: String) -> void:
	if path.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.load(RECENT_FILE)
	var listed := Array(cfg.get_value("recent", "files", PackedStringArray()))
	listed.erase(path)
	listed.push_front(path)
	cfg.set_value("recent", "files", PackedStringArray(listed.slice(0, RECENT_MAX)))
	cfg.save(RECENT_FILE)


func project_folder() -> String:
	var dir := ProjectSettings.globalize_path(ProjectFiles.DEFAULT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func file_extension() -> String:
	return ProjectFiles.EXTENSION


func new_project() -> void:
	_say_how(DAW.new_project(), "New project.")


func open_project(path: String) -> void:
	var said_back := DAW.open_project(path)
	if DAW.project_file() == path:
		remember(path)
		_say_how(said_back, "Opened %s." % path.get_file(), true)
	else:
		_say_how(said_back, "")


func save_project() -> void:
	DAW.save_project()


func save_project_as(path: String) -> void:
	if path.get_extension().to_lower() != ProjectFiles.EXTENSION:
		path += "." + ProjectFiles.EXTENSION
	_on_saved(DAW.save_project_as(path))


func render(stems: bool) -> void:
	DAW.render(stems)
	said.emit("Rendering %s..." % ("a file a track" if stems else "the mix"))


## Says how a project verb went: `done` if nothing went wrong, the desk's words if it did (as
## a warning when it was done all the same, `anyway`).
func _say_how(problems: PackedStringArray, done: String, anyway := false) -> void:
	if problems.is_empty():
		said.emit(done)
	elif anyway:
		said.emit(done + " " + "; ".join(problems))
	else:
		said.emit("Could not: " + "; ".join(problems))


func _on_saved(problems: PackedStringArray) -> void:
	var path := DAW.project_file() if DAW.backend != null else ""
	if problems.is_empty() or DAW.backend == null or not DAW.has_unsaved_changes():
		remember(path)
		said.emit("Saved %s." % path.get_file() if not path.is_empty() else "Saved.")
	else:
		said.emit("Could not save: " + "; ".join(problems))
	_transport()


func _on_rendered(files: PackedStringArray, problems: PackedStringArray) -> void:
	if files.is_empty():
		said.emit("The render did not finish: " + "; ".join(problems))
		return
	said.emit("Rendered %d file%s to %s." % [files.size(), "" if files.size() == 1 else "s", files[0].get_base_dir()]
			+ ("" if problems.is_empty() else " " + "; ".join(problems)))


func set_automation(id: String, target: String, points: Array) -> void:
	var index := ProjectBridge.index_of(id)
	var t: MixState.TrackState = DAW.state.tracks.get(index) if DAW.state != null else null
	var lane := desk_lane(t, target) if t != null else ""
	if not lane.is_empty():
		DAW.set_automation(index, lane, points)


func set_loop_range(start: float, end: float) -> void:
	DAW.set_loop_range(start, end)


func count_in() -> int:
	return DAW.state.count_in_bars if DAW.state != null else 0


func set_count_in(bars: int) -> void:
	DAW.set_count_in(bars)


## The desk names markers and regions by where they are, the 2D view by their place in order.
func add_marker(seconds: float, called := "") -> void:
	DAW.add_marker(seconds, called)


func edit_marker(index: int, seconds: float, called: String) -> void:
	var m := _marker(index)
	if m != null:
		DAW.edit_marker(m.time, seconds, called)


func remove_marker(index: int) -> void:
	var m := _marker(index)
	if m != null:
		DAW.remove_marker(m.time)


func add_region(start: float, end: float, called := "") -> void:
	DAW.add_region(minf(start, end), maxf(start, end), called)


func edit_region(index: int, start: float, end: float, called: String) -> void:
	var r := _region(index)
	if r != null:
		DAW.edit_region(r.start, minf(start, end), maxf(start, end), called)


func remove_region(index: int) -> void:
	var r := _region(index)
	if r != null:
		DAW.remove_region(r.start)


func set_tempo_points(points: Array) -> void:
	DAW.set_tempo_map(points)


func set_meter_points(points: Array) -> void:
	DAW.set_time_signature_map(points)


func _marker(index: int) -> DawKitMarker:
	var p := project()
	return p.markers[index] if p != null and index >= 0 and index < p.markers.size() else null


func _region(index: int) -> DawKitRegion:
	var p := project()
	return p.regions[index] if p != null and index >= 0 and index < p.regions.size() else null


func undo() -> void:
	DAW.undo()


func redo() -> void:
	DAW.redo()


func _restructured() -> void:
	_stale = true
	project_changed.emit()


func _transport() -> void:
	_stale = true
	transport_changed.emit()


func _on_track_changed(index: int, _field: StringName) -> void:
	_stale = true
	track_changed.emit(ProjectBridge.id_of(index))
