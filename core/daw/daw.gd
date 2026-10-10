extends Node

## Autoload `DAW`. The single door every surface goes through, and the only thing in the project
## that knows which DAW is on the other side of it.
##
## A console calls `DAW.set_track_volume(3, 0.7)`. It does not know whether that becomes an OSC
## message to Reaper, a Live API call, or a change to a synthetic mix with nothing behind it; it
## does not know whether this participant owns the link or is a guest whose writes have to
## travel to whoever does. Both of those are decided here, and the surfaces are written once.
##
## TWO SEPARATE QUESTIONS, and the old code conflated them into one enum, which is how a session
## hosted on the stand-in mix came to replicate nothing at all:
##
##   WHICH DAW   `backend`. Reaper, the offline stand-in, and whatever comes next.
##   WHO OWNS IT `Session.is_authority()`. A guest has a backend too -- it holds the replicated
##               cache -- but its writes are intents sent to the host rather than commands.
##
## Swapping `backend` at runtime is supported and is the point: a participant can drop the link
## to Reaper and keep the room standing, because the surfaces are bound to this node and not to
## the thing behind it.

signal connection_changed()
## See DAWBackend.tracks_renumbered.
signal tracks_renumbered(map: Dictionary)

## The mix's own signals, relayed from whichever MixState is current. Connect to THESE, never to
## `DAW.state.<signal>`: the state belongs to the backend and is replaced with it -- joining a
## session, leaving one, dropping to the stand-in -- and a surface connected to the old one is
## left listening to a mix nobody is changing any more. That was not hypothetical: a guest
## falling back to its own mix kept the host's forty-track timeline on the stand, because the
## timeline was still subscribed to the host's replicated cache.
signal track_added(index: int)
signal track_changed(index: int, field: StringName)
signal transport_changed()
signal master_changed(field: StringName)
signal fx_changed(track_index: int, fx_index: int)
signal timeline_changed()
signal bank_changed()
signal project_replaced()
## See MixState.project_named.
signal project_named()
## The host saved the project here, by its own hand; what went wrong, empty when nothing did.
signal project_saved(said: PackedStringArray)
## See DAWBackend.render_finished.
signal render_finished(files: PackedStringArray, problems: PackedStringArray)
## A file `import_audio_files` was given is in, or could not be: {"error", "seconds", "name"},
## as `import_audio` answers.
signal audio_imported(path: String, result: Dictionary)
## The last of a batch of `import_audio_files` is done: the files that came in, the ones that did
## not, the track they went to, and whose they were ("" for this machine's own).
signal audio_import_done(brought: PackedStringArray, failed: PackedStringArray, track: int, who: String)

const RELAYED := [&"project_replaced", &"track_added", &"track_changed", &"transport_changed", &"master_changed",
		&"fx_changed", &"timeline_changed", &"bank_changed", &"project_named"]

## Every verb a surface may use, as data. The same list as the methods on DAWBackend -- it is
## here as well because a guest's intent names its verb, and a verb missing from this list is a
## verb that silently stops working for everyone who is not the host.
const COMMANDS := [
	&"set_track_volume", &"set_track_pan", &"set_track_mute", &"set_track_solo",
	&"set_track_rec_arm", &"set_master_volume", &"set_master_pan",
	&"set_fx_param", &"set_fx_enabled", &"read_fx_param_text", &"read_fx_params",
	&"set_fx_wet", &"step_fx_preset", &"move_fx", &"create_sidechain",
	&"set_track_bank",
	&"transport_play", &"transport_stop", &"transport_record",
	&"set_looping", &"set_tempo", &"save_project", &"seek", &"set_loop_range", &"undo", &"redo",
	&"select_item", &"clear_item_selection", &"move_item", &"split_selected",
	&"delete_selected", &"duplicate_selected", &"trim_item", &"set_item_gain", &"set_item_fades",
	&"transpose_item", &"quantize_item", &"set_tempo_map", &"set_time_signature_map", &"set_automation", &"add_track", &"remove_track", &"rename_track", &"set_track_colour",
	&"create_send", &"remove_send",
	&"set_send_volume", &"set_send_pan",
	&"set_metronome", &"set_count_in", &"set_count_in_play", &"set_pre_roll", &"set_punch", &"add_marker", &"edit_marker", &"remove_marker", &"set_track_monitor", &"set_track_input", &"set_track_automation_mode", &"render",
	&"insert_midi_take",
]

## Item edits that name an item, and how many arguments each takes.
const ITEM_EDITS := {&"trim_item": 4, &"set_item_gain": 3, &"set_item_fades": 4,
		&"transpose_item": 3, &"quantize_item": 4}

var backend: DAWBackend

## Reaper's own limits on a project tempo.
const TEMPO_MIN := 1.0
const TEMPO_MAX := 960.0


func _ready() -> void:
	set_process(false)
	# An autoload that opened a socket on startup would make `godot --headless` in CI try to
	# talk to a DAW. Nothing happens until a scene asks for one.
	use(OfflineBackend.new(), false)


## Install a backend. `start` is false only when the caller wants the object in place without
## opening anything, which is what a fresh process wants: the studio has to be buildable before
## the command line has been read.
func use(new_backend: DAWBackend, start: bool = true, options: Dictionary = {}) -> bool:
	if backend:
		_relay(backend.state, false)
		backend.close()
		backend.queue_free()
	backend = new_backend
	add_child(backend)
	_relay(backend.state, true)
	backend.connection_changed.connect(func(): connection_changed.emit())
	backend.tracks_renumbered.connect(func(map: Dictionary): tracks_renumbered.emit(map))
	backend.render_finished.connect(func(files: PackedStringArray, problems: PackedStringArray):
		render_finished.emit(files, problems))
	backend.is_authority = Session.is_authority()
	var ok := backend.open(options) if start else true
	connection_changed.emit()
	# Everything listening has been looking at a different mix until now; tell it all at once
	# rather than leave each part to notice when its own corner next happens to change.
	bank_changed.emit()
	transport_changed.emit()
	timeline_changed.emit()
	master_changed.emit(&"")
	return ok


func _relay(from: MixState, on: bool) -> void:
	if from == null:
		return
	for sig in RELAYED:
		var out := Signal(self, sig)
		var source := Signal(from, sig)
		if on and not source.is_connected(out.emit):
			source.connect(out.emit)
		elif not on and source.is_connected(out.emit):
			source.disconnect(out.emit)


## The mix cache. Reads go straight to it from every surface -- a meter polling two floats a
## frame must not pay for a function call per read.
var state: MixState:
	get: return backend.state


func is_live() -> bool:
	return backend != null and backend.is_live()


## See DAWBackend.catching_up.
func catching_up() -> bool:
	return backend != null and backend.catching_up()


func summary() -> String:
	if backend == null:
		return "no backend"
	if not Session.is_authority():
		return "guest: replicated from the host"
	return backend.summary()


func can(capability: StringName) -> bool:
	# A guest cannot be asked -- its backend holds a replicated cache and has no link of its
	# own -- so the answer is the host's, and until that is replicated the honest answer is yes:
	# the intent travels, and the host refuses it if it must.
	if not Session.is_authority():
		return true
	return backend != null and backend.can(capability)


func taper_to_db(taper: float) -> float:
	return backend.taper_to_db(taper)


func db_to_taper(db: float) -> float:
	return backend.db_to_taper(db)


# --- commands -----------------------------------------------------------------------------
#
# One line each, and the uniformity is the feature: a guest's write and a host's write differ
# in exactly one place, here, rather than in fourteen controls.

func set_track_volume(index: int, taper: float) -> void: _do(&"set_track_volume", [index, taper])
func set_track_pan(index: int, pan: float) -> void: _do(&"set_track_pan", [index, pan])
func set_track_mute(index: int, muted: bool) -> void: _do(&"set_track_mute", [index, muted])
func set_track_solo(index: int, soloed: bool) -> void: _do(&"set_track_solo", [index, soloed])
func set_track_rec_arm(index: int, armed: bool) -> void: _do(&"set_track_rec_arm", [index, armed])

func set_track_bank(offset: int) -> void: _do(&"set_track_bank", [offset])

func set_master_volume(taper: float) -> void: _do(&"set_master_volume", [taper])
func set_master_pan(pan: float) -> void: _do(&"set_master_pan", [pan])

func set_fx_param(track_index: int, fx_index: int, param: int, value: float) -> void:
	_do(&"set_fx_param", [track_index, fx_index, param, value])


func set_fx_enabled(track_index: int, fx_index: int, enabled: bool) -> void:
	_do(&"set_fx_enabled", [track_index, fx_index, enabled])


func set_fx_wet(track_index: int, fx_index: int, wet: float) -> void:
	_do(&"set_fx_wet", [track_index, fx_index, clampf(wet, 0.0, 1.0)])


func step_fx_preset(track_index: int, fx_index: int, direction: int) -> void:
	_do(&"step_fx_preset", [track_index, fx_index, signi(direction)])


## Fire and forget, unlike a send: whatever holds the plugin finds it again by watching the
## chain, because on a guest there is no answer to wait for.
func move_fx(from_track: int, fx_index: int, to_track: int, to_fx: int, copy := false) -> void:
	_do(&"move_fx", [from_track, fx_index, to_track, maxi(to_fx, 0), copy])


func create_sidechain(from_track: int, to_track: int) -> bool:
	if not Session.is_authority():
		Session.send_intent(&"create_sidechain", [from_track, to_track])
		return false
	return backend.create_sidechain(from_track, to_track)


## A send is named by its track and its 1-based place in that track's sends, as on the wire.
func set_send_volume(track_index: int, send_index: int, taper: float) -> void:
	_do(&"set_send_volume", [track_index, send_index, clampf(taper, 0.0, 1.0)])


func set_send_pan(track_index: int, send_index: int, pan: float) -> void:
	_do(&"set_send_pan", [track_index, send_index, clampf(pan, 0.0, 1.0)])


## Through `_do` although it changes nothing: only the host can reach Reaper, and the answer
## replicates to everyone like any other value.
## The most parameters one read_fx_params may name.
const READ_PARAMS_MAX := 32


func read_fx_param_text(track_index: int, fx_index: int, param: int) -> void:
	_do(&"read_fx_param_text", [track_index, fx_index, param])


## Ask for some of a plugin's parameters -- value, name and words -- or, with none named, for the
## list of every real parameter it has. Through `_do` for the same reason as the text.
func read_fx_params(track_index: int, fx_index: int, params: Array = []) -> void:
	_do(&"read_fx_params", [track_index, fx_index, params])


## The plugin's own window, as its maker drew it, live and workable -- or null. The host's own
## verb and not an intent: the window is on the host's desktop, and a guest has nothing to show.
## Whoever opens it closes it (PluginWindow.close), which closes it in the DAW too.
func open_plugin_window(track_index: int, fx_index: int) -> PluginWindow:
	if not shows_plugin_windows():
		return null
	return backend.open_plugin_window(track_index, fx_index)


## Whether a plugin's own window can be shown here: only on the host, and only by a DAW that can.
func shows_plugin_windows() -> bool:
	return Session.is_authority() and backend != null \
			and backend.can(DAWBackend.Capability.PLUGIN_WINDOW)


func transport_play() -> void: _do(&"transport_play", [])
func transport_stop() -> void: _do(&"transport_stop", [])
func transport_record() -> void: _do(&"transport_record", [])
func set_looping(on: bool) -> void: _do(&"set_looping", [on])
func set_metronome(on: bool) -> void: _do(&"set_metronome", [on])
## Bars of click before recording starts, 0 for none; counted in only while the click is on.
func set_count_in(bars: int) -> void: _do(&"set_count_in", [bars])
## The count-in before playback as well as recording (MixState.count_in_play).
func set_count_in_play(on: bool) -> void: _do(&"set_count_in_play", [on])
## Pre-roll: the song under the count-in (MixState.pre_roll).
func set_pre_roll(on: bool) -> void: _do(&"set_pre_roll", [on])
## Punching in and out: a recording takes only inside the loop range.
func set_punch(on: bool) -> void: _do(&"set_punch", [on])
## Input monitoring for one track: MONITOR_OFF, MONITOR_ON or MONITOR_AUTO, Reaper's own numbers.
const MONITOR_OFF := 0
const MONITOR_ON := 1
const MONITOR_AUTO := 2
## What a track records from: one of `state.inputs` by id, or "" for whatever the recorder is set to.
func set_track_input(index: int, input: String) -> void: _do(&"set_track_input", [index, input])
func set_track_monitor(index: int, mode: int) -> void:
	_do(&"set_track_monitor", [index, clampi(mode, MONITOR_OFF, MONITOR_AUTO)])
## How a track's controls meet their automation (MixState.TrackState.automation_mode). Track 0
## is the master's fader and pan.
const AUTOMATION_READ := 0
const AUTOMATION_TOUCH := 2
const AUTOMATION_LATCH := 4
func set_track_automation_mode(index: int, mode: int) -> void:
	_do(&"set_track_automation_mode", [index, MixWire.automation_mode_of(mode)])
## Clamped to what Reaper itself accepts. A guest's intent is clamped again on the host, by
## the same function, because it arrives here rather than at the backend.
func set_tempo(bpm: float) -> void: _do(&"set_tempo", [clampf(bpm, TEMPO_MIN, TEMPO_MAX)])
## Writes the song to WAVs beside the project, as the host's DAW renders: see DAWBackend.render.
## Anyone in a session may ask; the files are the host's.
func render(stems: bool) -> void:
	_do(&"render", [stems])
## Saves the project where it is. Anyone in a session may press save; nobody but the host
## chooses where, so a guest's save carries no path (and one that did is not believed).
func save_project() -> void:
	if Session.is_authority():
		project_saved.emit(backend.save_project(""))
		return
	Session.send_intent(&"save_project", [""])


## The project's name, and the file it was last saved to or opened from (empty for neither,
## and for a DAW that keeps its own files).
## What the project is called. A guest has it from the host, "" until the host says.
func project_title() -> String:
	if not Session.is_authority():
		return state.project_title if state != null else ""
	var title = backend.get(&"project_title")
	if title != null:
		return str(title)
	# A DAW with its own files says what its project is called (MixState.project_title).
	return state.project_title if state != null and not state.project_title.is_empty() else "Untitled"


## Where keys played into a track are heard through it: see DAWBackend.monitor_bus.
func monitor_bus(track_index: int) -> StringName:
	return backend.monitor_bus(track_index) if backend != null else &""


func project_file() -> String: return backend.project_path if Session.is_authority() else ""


## The name of the project's file, without its folder: for anyone, the host's file on a guest.
func project_file_name() -> String:
	if Session.is_authority() and not backend.project_path.is_empty():
		return backend.project_path.get_file()
	return state.project_file if state != null else ""


## Host only: these name a file on this machine, which no guest may do.
func save_project_as(path: String) -> PackedStringArray:
	if not Session.is_authority():
		return PackedStringArray(["only the host chooses where the project is saved"])
	return backend.save_project(path)


func open_project(path: String) -> PackedStringArray:
	if not Session.is_authority():
		return PackedStringArray(["only the host opens a project"])
	return backend.open_project(path)


func new_project() -> PackedStringArray:
	if not Session.is_authority():
		return PackedStringArray(["only the host starts a project"])
	return backend.new_project()


func seek(seconds: float) -> void: _do(&"seek", [maxf(seconds, 0.0)])
func set_loop_range(start: float, end: float) -> void:
	_do(&"set_loop_range", [maxf(minf(start, end), 0.0), maxf(maxf(start, end), 0.0)])
func undo() -> void: _do(&"undo", [])
func redo() -> void: _do(&"redo", [])
func select_item(track_index: int, item_index: int, additive := false) -> void:
	_do(&"select_item", [track_index, item_index, additive])
func clear_item_selection() -> void: _do(&"clear_item_selection", [])
func move_item(track_index: int, item_index: int, start: float) -> void:
	_do(&"move_item", [track_index, item_index, maxf(start, 0.0)])
func split_selected(seconds: float) -> void: _do(&"split_selected", [maxf(seconds, 0.0)])
func delete_selected() -> void: _do(&"delete_selected", [])
func duplicate_selected() -> void: _do(&"duplicate_selected", [])
func trim_item(track_index: int, item_index: int, start: float, end: float) -> void:
	_do(&"trim_item", [track_index, item_index, maxf(minf(start, end), 0.0), maxf(start, end)])
func set_item_gain(track_index: int, item_index: int, db: float) -> void:
	_do(&"set_item_gain", [track_index, item_index,
			clampf(db, DAWBackend.ITEM_GAIN_MIN, DAWBackend.ITEM_GAIN_MAX)])
func set_item_fades(track_index: int, item_index: int, fade_in: float, fade_out: float) -> void:
	_do(&"set_item_fades", [track_index, item_index, maxf(fade_in, 0.0), maxf(fade_out, 0.0)])
## Longest track name sent anywhere, for the same reason as MARKER_NAME_MAX.
const TRACK_NAME_MAX := 64
func add_track(at: int, track_name := "") -> void:
	_do(&"add_track", [maxi(at, 1), track_name.left(TRACK_NAME_MAX)])
func remove_track(index: int) -> void: _do(&"remove_track", [index])
func rename_track(index: int, track_name: String) -> void:
	_do(&"rename_track", [index, track_name.left(TRACK_NAME_MAX)])
## A track's colour, as its chip shows it and Reaper keeps it. Opaque, and within 0-1.
func set_track_colour(index: int, colour: Color) -> void:
	_do(&"set_track_colour", [index, _opaque(colour)])


static func _opaque(c: Color) -> Color:
	return Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0), 1.0)
## `points` as MixState.TrackState.automation's: [seconds, value, shape]. Empty takes the lane away.
## Track 0 is the master, whose volume and pan can be automated.
func set_automation(track_index: int, target: String, points: Array) -> void:
	var flat := MixWire.pack_automation(points)
	if Session.is_authority():
		apply_intent(&"set_automation", [track_index, target, flat])
	else:
		Session.send_intent(&"set_automation", [track_index, target, flat])
## `points` as MixState.time_signature_points: [beat, numerator, denominator], the first at beat
## 0 and the song's own signature. Sent flat, as the tempo map is.
func set_time_signature_map(points: Array) -> void:
	var flat := MixWire.pack_meter_points(points)
	if Session.is_authority():
		apply_intent(&"set_time_signature_map", [flat])
	else:
		Session.send_intent(&"set_time_signature_map", [flat])
## `points` as MixState.tempo_points: [beat, bpm, ramps], the first at beat 0. Sent flat so a
## guest's intent is checked the same way whatever sent it.
func set_tempo_map(points: Array) -> void:
	var flat := MixWire.pack_tempo_points(points)
	if Session.is_authority():
		apply_intent(&"set_tempo_map", [flat])
	else:
		Session.send_intent(&"set_tempo_map", [flat])
func transpose_item(track_index: int, item_index: int, semitones: int) -> void:
	_do(&"transpose_item", [track_index, item_index,
			clampi(semitones, -DAWBackend.TRANSPOSE_MAX, DAWBackend.TRANSPOSE_MAX)])
func quantize_item(track_index: int, item_index: int, grid_beats: float, strength := 1.0) -> void:
	_do(&"quantize_item", [track_index, item_index,
			clampf(grid_beats, DAWBackend.QUANTIZE_GRID_MIN, DAWBackend.QUANTIZE_GRID_MAX),
			clampf(strength, 0.0, 1.0)])
## Longest marker name sent anywhere. Reaper takes more, but nothing here can show more, and a
## guest's intent should not be able to hand the host a megabyte of name.
const MARKER_NAME_MAX := 64
func add_marker(seconds: float, marker_name: String) -> void:
	_do(&"add_marker", [maxf(seconds, 0.0), marker_name.left(MARKER_NAME_MAX)])
## The marker at `at` renamed, or moved to `to`, or both.
func edit_marker(at: float, to: float, marker_name: String) -> void:
	_do(&"edit_marker", [at, maxf(to, 0.0), marker_name.left(MARKER_NAME_MAX)])
func remove_marker(at: float) -> void:
	_do(&"remove_marker", [at])
## A take of notes onto a track, placed by song position: notes are [on, off, pitch, velocity,
## channel] rows in seconds. Cleaned here and cleaned again on the host, since a guest's take
## arrives there as peer input. See MidiTake.
func insert_midi_take(track_index: int, start: float, end: float, notes: Array,
		take_name := "") -> void:
	var args := MidiTake.clean_args([track_index, start, end, notes, take_name])
	if not args.is_empty():
		_do(&"insert_midi_take", args)


## Routing is the one command whose answer a surface needs immediately -- the patchbay has to
## know whether to draw the cable -- so it is not fire-and-forget. A guest cannot get a real
## answer back across the wire yet, and says so by returning false rather than drawing a cable
## that may not exist.
func create_send(from_track: int, to_track: int) -> bool:
	if not Session.is_authority():
		Session.send_intent(&"create_send", [from_track, to_track])
		return false
	return backend.create_send(from_track, to_track)


func remove_send(from_track: int, send_index: int) -> bool:
	if not Session.is_authority():
		Session.send_intent(&"remove_send", [from_track, send_index])
		return false
	return backend.remove_send(from_track, send_index)


func _do(verb: StringName, args: Array) -> void:
	if Session.is_authority():
		backend.callv(verb, args)
		return
	Session.send_intent(verb, args)


## An intent that arrived from a guest. Checked against the vocabulary rather than called
## blindly: this is a trusted-LAN model, but trusting a peer to move a fader is not the same as
## letting it name any method on this object.
func apply_intent(verb: StringName, args: Array) -> void:
	if verb not in COMMANDS:
		push_warning("DAW: refused an intent for unknown verb '%s'." % verb)
		return
	if verb == &"save_project":
		args = [""]
	if verb == &"set_tempo" and args.size() == 1:
		args = [clampf(float(args[0]), TEMPO_MIN, TEMPO_MAX)]
	if verb == &"add_marker":
		if args.size() != 2:
			push_warning("DAW: refused a malformed add_marker intent %s." % [args])
			return
		args = [maxf(float(args[0]), 0.0), str(args[1]).left(MARKER_NAME_MAX)]
	if verb == &"edit_marker":
		if args.size() != 3 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(args[1]) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(args[0])) or not is_finite(float(args[1])):
			push_warning("DAW: refused a malformed edit_marker intent %s." % [args])
			return
		args = [float(args[0]), maxf(float(args[1]), 0.0), str(args[2]).left(MARKER_NAME_MAX)]
	if verb == &"remove_marker":
		if args.size() != 1 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(args[0])):
			push_warning("DAW: refused a malformed remove_marker intent %s." % [args])
			return
		args = [float(args[0])]
	if verb == &"set_track_input":
		if args.size() != 2 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or int(args[0]) < 1 \
				or typeof(args[1]) != TYPE_STRING or (args[1] != "" and not state.inputs.any(func(p): return p[0] == args[1])):
			push_warning("DAW: refused a malformed set_track_input intent %s." % [args])
			return
		args = [int(args[0]), str(args[1])]
	if verb == &"set_track_monitor":
		if args.size() != 2 or int(args[0]) < 1:
			push_warning("DAW: refused a malformed set_track_monitor intent %s." % [args])
			return
		args = [int(args[0]), clampi(int(args[1]), MONITOR_OFF, MONITOR_AUTO)]
	if verb == &"render":
		args = [MixWire._as_bool(args) if not args.is_empty() else false]
	if verb == &"set_track_automation_mode":
		if args.size() != 2 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or int(args[0]) < 0:
			push_warning("DAW: refused a malformed set_track_automation_mode intent %s." % [args])
			return
		args = [int(args[0]), MixWire.automation_mode_of(args[1])]
	if verb == &"set_count_in":
		if args.size() != 1 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(args[0])):
			push_warning("DAW: refused a malformed set_count_in intent %s." % [args])
			return
		args = [clampi(int(args[0]), 0, MixState.COUNT_IN_MAX)]
	if verb == &"set_count_in_play" or verb == &"set_pre_roll":
		if args.size() != 1:
			push_warning("DAW: refused a malformed %s intent %s." % [verb, args])
			return
		args = [MixWire._as_bool([args[0]])]
	if verb == &"set_punch":
		if args.size() != 1:
			push_warning("DAW: refused a malformed set_punch intent %s." % [args])
			return
		args = [MixWire._as_bool([args[0]])]
	if verb == &"set_metronome":
		if args.size() != 1:
			push_warning("DAW: refused a malformed set_metronome intent %s." % [args])
			return
		args = [MixWire._as_bool([args[0]])]
	if verb in ITEM_EDITS:
		# Peer input: a track, an item, then finite numbers, or nothing at all.
		var want: int = ITEM_EDITS[verb]
		if args.size() != want or int(args[0]) < 1 or int(args[1]) < 0 \
				or args.slice(2).any(func(v): return not is_finite(float(v))):
			push_warning("DAW: refused a malformed %s intent %s." % [verb, args])
			return
		var clean: Array = [int(args[0]), int(args[1])]
		for v in args.slice(2):
			clean.append(float(v))
		if verb == &"set_item_gain":
			clean[2] = clampf(clean[2], DAWBackend.ITEM_GAIN_MIN, DAWBackend.ITEM_GAIN_MAX)
		if verb == &"transpose_item":
			clean[2] = clampi(int(clean[2]), -DAWBackend.TRANSPOSE_MAX, DAWBackend.TRANSPOSE_MAX)
		if verb == &"quantize_item":
			clean[2] = clampf(clean[2], DAWBackend.QUANTIZE_GRID_MIN, DAWBackend.QUANTIZE_GRID_MAX)
			clean[3] = clampf(clean[3], 0.0, 1.0)
		args = clean
	if verb in [&"delete_selected", &"duplicate_selected"]:
		args = []
	if verb == &"set_automation":
		# Peer input: a track, a target that names a control, and flat points.
		if args.size() != 3 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or int(args[0]) < 0 \
				or typeof(args[1]) not in [TYPE_STRING, TYPE_STRING_NAME] or not (args[2] is Array) \
				or (int(args[0]) == 0 and str(args[1]) not in MixWire.MASTER_LANES):
			push_warning("DAW: refused a malformed set_automation intent.")
			return
		var points := MixWire.unpack_automation(str(args[1]), args[2])
		if points.is_empty() and not (args[2] as Array).is_empty():
			push_warning("DAW: refused a malformed set_automation intent.")
			return
		args = [int(args[0]), str(args[1]), points]
	if verb == &"set_tempo_map":
		# Peer input: flat [beat, bpm, shape] triples, each a later beat, from beat 0.
		if args.size() != 1 or not (args[0] is Array):
			push_warning("DAW: refused a malformed set_tempo_map intent.")
			return
		var points := MixWire.unpack_tempo_points(args[0])
		if points.is_empty() and not (args[0] as Array).is_empty():
			push_warning("DAW: refused a malformed set_tempo_map intent.")
			return
		args = [points]
	if verb == &"set_time_signature_map":
		# Peer input: flat [beat, numerator, denominator] triples, each a later beat, from beat 0.
		if args.size() != 1 or not (args[0] is Array):
			push_warning("DAW: refused a malformed set_time_signature_map intent.")
			return
		var meter_points := MixWire.unpack_meter_points(args[0])
		if meter_points.is_empty():
			push_warning("DAW: refused a malformed set_time_signature_map intent.")
			return
		args = [meter_points]
	if verb in [&"add_track", &"rename_track"]:
		# Peer input: a track number and a name.
		if args.size() != 2 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or int(args[0]) < 1:
			push_warning("DAW: refused a malformed %s intent %s." % [verb, args])
			return
		args = [int(args[0]), str(args[1]).left(TRACK_NAME_MAX)]
	if verb == &"set_track_colour":
		# Peer input: a track number and a colour.
		if args.size() != 2 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or int(args[0]) < 1 \
				or typeof(args[1]) != TYPE_COLOR:
			push_warning("DAW: refused a malformed set_track_colour intent %s." % [args])
			return
		args = [int(args[0]), _opaque(args[1])]
	if verb == &"remove_track":
		if args.size() != 1 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or int(args[0]) < 1:
			push_warning("DAW: refused a malformed remove_track intent %s." % [args])
			return
		args = [int(args[0])]
	if verb in [&"set_send_volume", &"set_send_pan"]:
		# Peer input. A send is a track and a 1-based slot; anything else names nothing, and a
		# level outside the taper is a fader past its end stop.
		if args.size() != 3 or int(args[0]) < 1 or int(args[1]) < 1:
			push_warning("DAW: refused a malformed %s intent %s." % [verb, args])
			return
		args = [int(args[0]), int(args[1]), clampf(float(args[2]), 0.0, 1.0)]
	if verb == &"set_fx_wet":
		if args.size() != 3 or int(args[0]) < 1 or int(args[1]) < 0:
			push_warning("DAW: refused a malformed set_fx_wet intent %s." % [args])
			return
		args = [int(args[0]), int(args[1]), clampf(float(args[2]), 0.0, 1.0)]
	if verb == &"step_fx_preset":
		if args.size() != 3 or int(args[0]) < 1 or int(args[1]) < 0:
			push_warning("DAW: refused a malformed step_fx_preset intent %s." % [args])
			return
		args = [int(args[0]), int(args[1]), signi(int(args[2]))]
	if verb == &"read_fx_params":
		# A page of a tablet at most: a peer asking for a thousand reads is asking for a stall.
		if args.size() != 3 or int(args[0]) < 1 or int(args[1]) < 0 or not args[2] is Array \
				or (args[2] as Array).size() > READ_PARAMS_MAX \
				or (args[2] as Array).any(func(a): return not (a is float or a is int) or int(a) < 0):
			push_warning("DAW: refused a malformed read_fx_params intent %s." % [args])
			return
		args = [int(args[0]), int(args[1]), (args[2] as Array).map(func(a): return int(a))]
	if verb == &"move_fx":
		if args.size() != 5 or int(args[0]) < 1 or int(args[1]) < 0 or int(args[2]) < 1:
			push_warning("DAW: refused a malformed move_fx intent %s." % [args])
			return
		args = [int(args[0]), int(args[1]), int(args[2]), maxi(int(args[3]), 0),
				MixWire._as_bool([args[4]])]
	if verb == &"insert_midi_take":
		if not midi_take_refusal(args).is_empty():
			return
		args = MidiTake.clean_args(args)
	backend.callv(verb, args)


## A recorded file onto a track, by song position. The host's own verb and not an intent: a
## guest's audio reaches the host through Session as sound, and the host decides the file. Not
## in COMMANDS, so apply_intent refuses it from any peer. See AudioTake.
func insert_audio_take(track_index: int, start: float, source: String, length: float,
		peaks: PackedByteArray, take_name := "") -> void:
	if not Session.is_authority():
		push_warning("DAW: only the host places an audio take.")
		return
	if not audio_take_refusal(track_index, length).is_empty():
		return
	backend.insert_audio_take(track_index, maxf(start, 0.0), source.get_file(), length, peaks,
			MidiTake.clean_name(take_name))


## A sound file on this machine onto a track at `start`, as an item. Host only: the file and
## the project are both here. {"error": why not, or "", "seconds", "name": the take's file}.
func import_audio(path: String, track_index: int, start: float) -> Dictionary:
	if not Session.is_authority():
		return {"error": "only the host brings in files: the project is on their machine"}
	var refusal := audio_take_refusal(track_index, 1.0)
	if not refusal.is_empty():
		return {"error": refusal}
	var name := _import_name(path)
	var done := DawKitAudioFile.bring_in(path, ProjectSettings.globalize_path(AudioTake.DIR.path_join(name)))
	if not str(done.get("error", "")).is_empty():
		return {"error": done["error"]}
	insert_audio_take(track_index, start, name, done["seconds"], done["peaks"], path.get_file().get_basename())
	return {"error": "", "seconds": done["seconds"], "name": name}


## Sound files onto a track one after another from `start`, read and written on a worker thread
## so the room keeps moving while a long file is decoded. Each is placed, one undo step, when it
## is in (`audio_imported`), and `audio_import_done` follows the last. Batches queue behind each
## other. Host only; `who` names a guest whose files they are (FileSend). Answers why not, or "".
func import_audio_files(paths: PackedStringArray, track_index: int, start: float, who := "") -> String:
	if not Session.is_authority():
		return "only the host brings in files: the project is on their machine"
	var refusal := audio_take_refusal(track_index, 1.0)
	if not refusal.is_empty():
		return refusal
	if paths.is_empty():
		return ""
	_imports.append({"paths": Array(paths), "track": track_index, "at": maxf(start, 0.0),
			"brought": [], "failed": [], "who": who})
	set_process(true)
	return ""


## Whether files are still being brought in.
func importing() -> bool:
	return not _imports.is_empty()


## Batches waiting or under way, the first the one being read.
var _imports: Array = []
## The worker reading the first batch's first file: [task id, its result (filled by the worker),
## the name it is written under], or [] between files.
var _import_job: Array = []


func _process(_delta: float) -> void:
	if _imports.is_empty():
		set_process(false)
		return
	var batch: Dictionary = _imports[0]
	if _import_job.is_empty():
		var path: String = batch["paths"][0]
		var name := _import_name(path)
		var result := {}
		var dest := ProjectSettings.globalize_path(AudioTake.DIR.path_join(name))
		var task := WorkerThreadPool.add_task(func(): result.merge(DawKitAudioFile.bring_in(path, dest)),
				false, "bring in %s" % path.get_file())
		_import_job = [task, result, name]
		return
	if not WorkerThreadPool.is_task_completed(_import_job[0]):
		return
	WorkerThreadPool.wait_for_task_completion(_import_job[0])
	var done: Dictionary = _import_job[1]
	var name: String = _import_job[2]
	_import_job = []
	var path: String = batch["paths"].pop_front()
	var track: int = batch["track"]
	var why := str(done.get("error", ""))
	if why.is_empty():
		why = audio_take_refusal(track, float(done["seconds"]))
		if not why.is_empty():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioTake.DIR.path_join(name)))
	var answer := {"error": why}
	if why.is_empty() and Session.is_authority():
		insert_audio_take(track, batch["at"], name, done["seconds"], done["peaks"], path.get_file().get_basename())
		batch["at"] += float(done["seconds"])
		answer = {"error": "", "seconds": done["seconds"], "name": name}
		(batch["brought"] as Array).append(path)
	else:
		if why.is_empty():
			answer["error"] = "only the host brings in files: the project is on their machine"
		(batch["failed"] as Array).append(path)
	audio_imported.emit(path, answer)
	if (batch["paths"] as Array).is_empty():
		_imports.pop_front()
		audio_import_done.emit(PackedStringArray(batch["brought"]), PackedStringArray(batch["failed"]), track, batch["who"])


## A name among the takes for a file brought in, apart from any already there or in the project.
func _import_name(path: String) -> String:
	var media = backend.get(&"media")
	return AudioImport.file_name_for(path, func(n: String) -> bool:
		return FileAccess.file_exists(AudioTake.DIR.path_join(n)) or (media is Dictionary and media.has(n)) \
				or (not _import_job.is_empty() and _import_job[2] == n))


## Why a recorded take cannot be placed, in words for the person who played it, or "".
func audio_take_refusal(track_index: int, length: float) -> String:
	if backend == null or not backend.can(DAWBackend.Capability.AUDIO_TAKES):
		return "This DAW cannot take audio yet: in Reaper, load the dawlings bridge script."
	if not state.tracks.has(track_index):
		return "There is no track %d to record onto." % track_index
	if length <= 0.0:
		return "The take had no sound in it."
	return ""


## Why a take from a peer cannot be placed, in words for the person who played it, or "".
func midi_take_refusal(args: Array) -> String:
	var cleaned := MidiTake.clean_args(args)
	if cleaned.is_empty():
		return "The take could not be read."
	if backend == null or not backend.can(DAWBackend.Capability.MIDI_TAKES):
		return "This DAW cannot take MIDI yet: in Reaper, load the dawlings bridge script."
	if not state.tracks.has(cleaned[0]):
		return "There is no track %d to record onto." % cleaned[0]
	if (cleaned[3] as Array).is_empty():
		return "The take had no notes in it."
	return ""
