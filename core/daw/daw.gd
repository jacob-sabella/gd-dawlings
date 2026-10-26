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
	&"set_looping", &"set_tempo", &"save_project", &"seek", &"set_loop_range", &"undo", &"redo", &"undo_to",
	&"select_item", &"clear_item_selection", &"select_all_items", &"select_track_items", &"move_item", &"split_selected",
	&"delete_selected", &"ripple_delete_selected", &"glue_selected", &"nudge_selected", &"duplicate_selected", &"trim_item", &"ripple_move_item", &"ripple_trim_item", &"set_item_gain", &"process_item", &"set_item_fades", &"set_item_fade_shape", &"crossfade_items", &"set_item_muted", &"set_item_locked", &"set_item_reversed", &"set_item_lane", &"set_comp", &"set_item_controls", &"flatten_comp", &"freeze_track", &"thaw_track", &"copy_selected_to",
	&"transpose_item", &"shift_velocity", &"set_note_velocity", &"legato_item", &"staccato_item", &"even_velocity", &"move_note", &"place_note", &"set_note_end", &"insert_note", &"transpose_note", &"delete_note", &"retrograde_item", &"rename_item", &"humanise_item", &"quantize_item", &"groove_item", &"set_tempo_map", &"set_time_signature_map", &"set_automation", &"add_track", &"remove_track", &"move_track", &"duplicate_track", &"rename_track", &"set_track_colour", &"set_track_group", &"set_vca", &"add_fx", &"remove_fx",
	&"create_send", &"remove_send",
	&"set_send_volume", &"set_send_pan", &"set_send_pre_fader",
	&"set_metronome", &"set_count_in", &"set_count_in_play", &"set_pre_roll", &"set_punch", &"add_marker", &"edit_marker", &"remove_marker", &"add_region", &"remove_region", &"edit_region", &"set_track_monitor", &"set_track_input", &"set_track_automation_mode", &"render",
	&"insert_midi_take",
]

## Item edits that name an item, and how many arguments each takes.
const ITEM_EDITS := {&"trim_item": 4, &"ripple_move_item": 3, &"ripple_trim_item": 4, &"set_item_gain": 3, &"process_item": 4, &"set_item_fades": 4, &"set_item_fade_shape": 4, &"crossfade_items": 3, &"set_item_muted": 3, &"set_item_locked": 3, &"set_item_reversed": 3, &"set_item_lane": 3,
		&"transpose_item": 3, &"shift_velocity": 3, &"set_note_velocity": 4, &"legato_item": 2, &"staccato_item": 2, &"even_velocity": 2, &"move_note": 4, &"place_note": 5, &"set_note_end": 4, &"insert_note": 5, &"transpose_note": 4, &"delete_note": 3, &"retrograde_item": 2, &"humanise_item": 4, &"quantize_item": 5, &"groove_item": 6}

var backend: DAWBackend

## Reaper's own limits on a project tempo.
const TEMPO_MIN := 1.0
const TEMPO_MAX := 960.0


func _exit_tree() -> void:
	DemoSong.finish_renders()


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

## A grouped track's fader takes the rest of its group with it, each by the same decibels (as
## Reaper's groups and a desk's linked channels do): worked out here, from the cache, and sent as
## each track's own move, so a guest's drag is the same intents the host's would be. A track
## pulled all the way down pulls its group down with it.
func set_track_volume(index: int, taper: float) -> void:
	var mates := [] if group_free else group_mates(index)
	if mates.is_empty():
		_do(&"set_track_volume", [index, taper])
		return
	# From the faders' positions, which every peer has, not their decibels, which a guest may not.
	var by := taper_to_db(taper) - taper_to_db(state.track(index).volume)
	_do(&"set_track_volume", [index, taper])
	for j in mates:
		var db: float = taper_to_db(state.track(j).volume) + by
		_do(&"set_track_volume", [j, clampf(db_to_taper(db), 0.0, 1.0) if is_finite(db) and taper > 0.0 else 0.0])
func set_track_pan(index: int, pan: float) -> void: _do(&"set_track_pan", [index, pan])
## A grouped track's mute and solo are its group's.
func set_track_mute(index: int, muted: bool) -> void:
	for j in [index] + ([] if group_free else group_mates(index)):
		_do(&"set_track_mute", [j, muted])
	spend_group_free()
func set_track_solo(index: int, soloed: bool) -> void:
	for j in [index] + ([] if group_free else group_mates(index)):
		_do(&"set_track_solo", [j, soloed])
	spend_group_free()
## Armed from the desk (FREE on the TRACK page): the next fader move, mute or solo is the one
## track's alone, as a desk's group-override key is held for one move. A fader's release (or the
## next mute or solo) puts it back. Local to the desk; nothing on the wire.
var group_free := false
signal group_free_changed
func set_group_free(on: bool) -> void:
	if group_free != on:
		group_free = on
		group_free_changed.emit()
## One move spent: the group is the group again.
func spend_group_free() -> void:
	set_group_free(false)
## How many track groups there are to put a track in.
const GROUPS := 4
## The other tracks in `index`'s group, in order; none for a track in no group.
func group_mates(index: int) -> Array:
	if state == null or not state.tracks.has(index) or state.track(index).group == 0:
		return []
	var group := state.track(index).group
	return state.track_indices().filter(func(j): return j != index and state.track(j).group == group)
## A track into a group, 1 to GROUPS, or out of any with 0. One undo step.
## The plugins' latency per track and what lining them up would take (LatencyReport).
func latency_report() -> Array:
	return LatencyReport.build(state, backend.fx_latency)


## A group's VCA trim in dB: its tracks all follow, with the faders where they are.
func set_vca(group: int, db: float) -> void:
	_do(&"set_vca", [clampi(group, 1, GROUPS), clampf(db, -60.0, 12.0)])
func set_track_group(index: int, group: int) -> void:
	_do(&"set_track_group", [index, clampi(group, 0, GROUPS)])
## Every soloed (or muted) track let go, each through its own `set_track_solo` / `set_track_mute`,
## so a guest's press is the same intents a guest's taps would be and each is its own undo step.
func clear_solos() -> void:
	for index in state.track_indices():
		if state.track(index).solo:
			set_track_solo(index, false)
func clear_mutes() -> void:
	for index in state.track_indices():
		if state.track(index).mute:
			set_track_mute(index, false)
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


## A plugin from `state.fx_choices` (by id) into a track's chain, before slot `at`, or at the end
## for -1.
func add_fx(track_index: int, plugin: String, at := -1) -> void:
	_do(&"add_fx", [track_index, plugin, at])


func remove_fx(track_index: int, fx_index: int) -> void:
	_do(&"remove_fx", [track_index, fx_index])


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


## Before the track's fader and pan, or after them (the default).
func set_send_pre_fader(track_index: int, send_index: int, pre: bool) -> void:
	_do(&"set_send_pre_fader", [track_index, send_index, 1.0 if pre else 0.0])


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


## Whether the DAW's own plugins' windows (ReaEQ, not a third party's) can be worked here, not
## only shown. See DAWBackend.works_own_plugin_windows.
func works_own_plugin_windows() -> bool:
	return backend != null and backend.works_own_plugin_windows()


## Whether this plugin has a window of its own to show (DAWBackend.has_plugin_window).
func has_plugin_window(track_index: int, fx_index: int) -> bool:
	return backend != null and backend.has_plugin_window(track_index, fx_index)


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
## `bits` is the files' depth: 16 or 24 (integer, dithered) or 32 (float). See RENDER_BITS.
## `rate` is the files' sample rate, one of RENDER_RATES.
## `flac` writes FLAC files instead (16 or 24 bits; 32 is written as 24) where the engine can.
func render(stems: bool, bits := RENDER_BITS_DEFAULT, normalise := false, rate := RENDER_RATE_DEFAULT,
		flac := false) -> void:
	_do(&"render", [stems, bits if bits in RENDER_BITS else RENDER_BITS_DEFAULT, normalise,
			rate if rate in RENDER_RATES else RENDER_RATE_DEFAULT, flac])
const RENDER_BITS: Array[int] = [16, 24, 32]
const RENDER_BITS_DEFAULT := 24
const RENDER_RATES: Array[int] = [44100, 48000, 96000]
const RENDER_RATE_DEFAULT := 48000
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


## The instrument plugin a track plays its notes through, on this machine (DawKitPlugin), or null
## where the track has none or the DAW hosts its own.
func track_instrument(track_index: int) -> Object:
	return backend.track_instrument(track_index) if backend != null else null


func project_file() -> String: return backend.project_path if Session.is_authority() else ""


## Crash recovery, the host's: the autosave copy an earlier run left newer than the project (see
## OfflineBackend.recoverable), "" for none, for a guest, and for a DAW that keeps its own.
func recoverable_copy() -> String:
	if not Session.is_authority() or backend == null or not backend.has_method(&"recoverable"):
		return ""
	return backend.call(&"recoverable")


## The autosave copies kept, newest first: [] for a guest and for a DAW that keeps its own.
func autosave_copies() -> PackedStringArray:
	if not Session.is_authority() or backend == null or not backend.has_method(&"autosave_history"):
		return PackedStringArray()
	return backend.call(&"autosave_history")


## Opens that copy in the project's place, unsaved. Host only: it replaces the project.
func recover_autosave(generation := 0) -> PackedStringArray:
	if recoverable_copy().is_empty():
		return PackedStringArray(["no newer copy is kept"])
	return backend.call(&"recover", generation)


## When the host's autosave last kept a copy (Time.get_ticks_msec), -1 for never, and for a guest
## or a DAW that keeps its own.
func autosaved_at_msec() -> int:
	var at = backend.get(&"autosaved_at_msec") if Session.is_authority() and backend != null else null
	return int(at) if at != null else -1


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


func new_project(tracks := 4) -> PackedStringArray:
	if not Session.is_authority():
		return PackedStringArray(["only the host starts a project"])
	return backend.new_project(tracks)


## Host only: keeps the project's layout, without its content, as a template (ProjectFiles).
func save_template(template_name: String) -> PackedStringArray:
	if not Session.is_authority():
		return PackedStringArray(["only the host keeps templates"])
	return backend.save_template(template_name)


## Host only: a new unsaved project laid out as the template.
func new_project_from_template(template_name: String) -> PackedStringArray:
	if not Session.is_authority():
		return PackedStringArray(["only the host starts a project"])
	return backend.new_project_from_template(template_name)


## Host only: whether the open project has changes no save has kept.
func has_unsaved_changes() -> bool:
	return Session.is_authority() and backend.has_unsaved_changes()


## Host only: the project as it stands counts as saved, for a change that is the starting
## point of the project rather than an edit to it.
func mark_clean() -> void:
	if Session.is_authority():
		backend.mark_clean()


func seek(seconds: float) -> void: _do(&"seek", [maxf(seconds, 0.0)])
func set_loop_range(start: float, end: float) -> void:
	_do(&"set_loop_range", [maxf(minf(start, end), 0.0), maxf(maxf(start, end), 0.0)])
## The loop set round the selected items, from the first one's start to the last one's end, and
## looping switched on. Two ordinary intents, so a guest's press needs nothing new on the wire.
## False when nothing is selected.
func loop_selected_items() -> bool:
	var from := INF
	var to := -INF
	for pick in state.selected_items():
		var it := state.item(pick[0], pick[1])
		if it != null:
			from = minf(from, it.start)
			to = maxf(to, it.end())
	if from == INF or to - from < DAWBackend.MIN_ITEM_SECONDS:
		return false
	set_loop_range(from, to)
	if not state.looping:
		set_looping(true)
	return true
func undo() -> void: _do(&"undo", [])
func redo() -> void: _do(&"redo", [])
## Back or forward through history to `depth` steps done: the history list's jump.
func undo_to(depth: int) -> void: _do(&"undo_to", [maxi(depth, 0)])
func select_item(track_index: int, item_index: int, additive := false) -> void:
	_do(&"select_item", [track_index, item_index, additive])
func clear_item_selection() -> void: _do(&"clear_item_selection", [])
func select_all_items() -> void: _do(&"select_all_items", [])
## Every item on one track selected, and nothing else.
func select_track_items(track_index: int) -> void: _do(&"select_track_items", [track_index])
## `to_track`: onto another track as well (0, the one it is on).
func move_item(track_index: int, item_index: int, start: float, to_track := 0) -> void:
	_do(&"move_item", [track_index, item_index, maxf(start, 0.0), maxi(to_track, 0)])
func copy_selected_to(seconds: float) -> void: _do(&"copy_selected_to", [maxf(seconds, 0.0)])
## The selection moved by `amount` of `unit` (see DAWBackend.nudge_selected).
func nudge_selected(amount: float, unit: int) -> void: _do(&"nudge_selected", [amount, unit])
func split_selected(seconds: float) -> void: _do(&"split_selected", [maxf(seconds, 0.0)])
func delete_selected() -> void: _do(&"delete_selected", [])
## Delete the selection and close the gap it leaves on each track: what comes after moves back
## by what was taken out before it (Reaper's ripple per track). One undo step.
func ripple_delete_selected() -> void: _do(&"ripple_delete_selected", [])
## On each track, the selected items made one (DAWBackend.glue_picks: MIDI, or cuts of one file
## that follow on). One undo step.
func glue_selected() -> void: _do(&"glue_selected", [])
func duplicate_selected() -> void: _do(&"duplicate_selected", [])
func trim_item(track_index: int, item_index: int, start: float, end: float) -> void:
	_do(&"trim_item", [track_index, item_index, maxf(minf(start, end), 0.0), maxf(start, end)])
## Ripple editing: the item moved or trimmed, and every later unlocked item on its track carried
## along by as much (see DAWBackend.ripple_move_item). One undo step each.
func ripple_move_item(track_index: int, item_index: int, start: float) -> void:
	_do(&"ripple_move_item", [track_index, item_index, maxf(start, 0.0)])
func ripple_trim_item(track_index: int, item_index: int, start: float, end: float) -> void:
	_do(&"ripple_trim_item", [track_index, item_index, maxf(minf(start, end), 0.0), maxf(start, end)])
func set_item_gain(track_index: int, item_index: int, db: float) -> void:
	_do(&"set_item_gain", [track_index, item_index,
			clampf(db, DAWBackend.ITEM_GAIN_MIN, DAWBackend.ITEM_GAIN_MAX)])
## An audio item's sound stretched (`DAWBackend.PROCESS_STRETCH`, `amount` the new length over the old,
## pitch kept) or pitch-shifted (`PROCESS_PITCH`, semitones, length kept) into a new file. One undo step.
func process_item(track_index: int, item_index: int, kind: int, amount: float) -> void:
	_do(&"process_item", [track_index, item_index, clampi(kind, 0, 1), _clean_process(kind, amount)])
static func _clean_process(kind: int, amount: float) -> float:
	if not is_finite(amount):
		return 1.0 if kind == DAWBackend.PROCESS_STRETCH else 0.0
	if kind == DAWBackend.PROCESS_STRETCH:
		return clampf(amount, DAWBackend.STRETCH_MIN, DAWBackend.STRETCH_MAX)
	return clampf(amount, -DAWBackend.PITCH_SHIFT_MAX, DAWBackend.PITCH_SHIFT_MAX)
## Gain so the item's loudest moment is at full scale, through `set_item_gain`: the same edit, the
## same step to undo, the same intent from a guest. Nothing for an item with no sound to measure.
func normalise_item(track_index: int, item_index: int) -> void:
	var item := state.item(track_index, item_index)
	var peak := item.sound_peak() if item != null else 0.0
	if peak > 0.0:
		set_item_gain(track_index, item_index, -linear_to_db(peak))
func set_item_fades(track_index: int, item_index: int, fade_in: float, fade_out: float) -> void:
	_do(&"set_item_fades", [track_index, item_index, maxf(fade_in, 0.0), maxf(fade_out, 0.0)])
## How an item's fade in and fade out run (see DAWBackend.set_item_fade_shape).
func set_item_fade_shape(track_index: int, item_index: int, in_shape: int, out_shape: int) -> void:
	_do(&"set_item_fade_shape", [track_index, item_index, DawKitClip.clean_shape(in_shape),
			DawKitClip.clean_shape(out_shape)])
## Two items of one track that overlap, faded into each other over the overlap: the earlier one
## out, the later one in, both equal-power so the sound holds its loudness through the middle --
## one edit (DAWBackend.crossfade_items). False when they are not two items of one track, do not
## overlap, or either is locked.
func crossfade_items(track_index: int, first: int, second: int) -> bool:
	var a := state.item(track_index, first)
	var b := state.item(track_index, second)
	if a == null or b == null or first == second:
		return false
	if b.start < a.start:
		var swap := a
		a = b
		b = swap
	var overlap := minf(a.end(), b.end()) - b.start
	if overlap < DAWBackend.MIN_ITEM_SECONDS or a.locked or b.locked:
		return false
	_do(&"crossfade_items", [track_index, first, second])
	return true
func set_item_muted(track_index: int, item_index: int, muted: bool) -> void:
	_do(&"set_item_muted", [track_index, item_index, 1.0 if muted else 0.0])


## An audio item played backwards, or forwards again (MixState.ItemState.reversed). One undo step.
func set_item_reversed(track_index: int, item_index: int, reversed: bool) -> void:
	_do(&"set_item_reversed", [track_index, item_index, 1.0 if reversed else 0.0])


## Lock an item against edits, or unlock it (MixState.ItemState.locked). One undo step.
func set_item_locked(track_index: int, item_index: int, locked: bool) -> void:
	_do(&"set_item_locked", [track_index, item_index, 1.0 if locked else 0.0])


## Put an item on take lane `lane` (0 the first; MixState.ItemState.lane). One undo step.
func set_item_lane(track_index: int, item_index: int, lane: int) -> void:
	_do(&"set_item_lane", [track_index, item_index, float(lane)])


## Make take lane `lane` the one that sounds on a track from `from` to `to` seconds
## (MixState.TrackState.comp). One undo step.
func set_comp(track_index: int, from: float, to: float, lane: int) -> void:
	_do(&"set_comp", [track_index, from, to, float(lane)])


## A MIDI item's lane of controller `kind` (DawKitClip: a CC number, PITCH_BEND or AFTERTOUCH) on
## `channel` made `points`, [seconds from the item's start, value] pairs; empty takes the lane away.
## One undo step.
func set_item_controls(track_index: int, item_index: int, kind: int, channel: int, points: Array) -> void:
	var flat: Array = []
	for p in points:
		flat.append_array([float(p[0]), float(p[1])])
	_do(&"set_item_controls", [track_index, item_index, kind, channel, flat])


## The comp made plain: each item cut to what the comp plays of it, all on the first lane. One
## undo step.
func flatten_comp(track_index: int) -> void:
	_do(&"flatten_comp", [track_index])


## Freeze a track to a file of its sound (DAWBackend.freeze_track); it takes the song's length.
func freeze_track(track_index: int) -> void:
	_do(&"freeze_track", [track_index])


## Put a frozen track back as it was.
func thaw_track(track_index: int) -> void:
	_do(&"thaw_track", [track_index])


## What a locked item refuses: anything that names it and would change where it is or what it
## sounds like. Its mute, its lock, and being selected or copied are still its to have. Checked
## by the host, for its own edits and a guest's, so a guest's stale view cannot move one.
const LOCKED_REFUSES := [&"move_item", &"trim_item", &"ripple_move_item", &"ripple_trim_item", &"set_item_gain", &"process_item", &"set_item_fades", &"set_item_fade_shape",
		&"transpose_item", &"shift_velocity", &"set_note_velocity", &"legato_item", &"staccato_item", &"even_velocity", &"move_note", &"place_note", &"set_note_end", &"insert_note", &"transpose_note", &"delete_note", &"retrograde_item", &"humanise_item", &"quantize_item", &"groove_item", &"set_item_reversed", &"set_item_lane", &"set_item_controls"]


func locked_against(verb: StringName, args: Array) -> bool:
	if verb not in LOCKED_REFUSES or args.size() < 2:
		return false
	var item := state.item(int(args[0]), int(args[1]))
	return item != null and item.locked
## Longest track name sent anywhere, for the same reason as MARKER_NAME_MAX.
const TRACK_NAME_MAX := 64
func add_track(at: int, track_name := "") -> void:
	_do(&"add_track", [maxi(at, 1), track_name.left(TRACK_NAME_MAX)])
func remove_track(index: int) -> void: _do(&"remove_track", [index])
## Track `index` (and what is in it) to be track `to`, inside folder `parent` (0 for none): see
## DAWBackend.move_track.
func move_track(index: int, to: int, parent: int) -> void:
	_do(&"move_track", [index, maxi(to, 1), maxi(parent, 0)])
## A copy of the track right after it (see DAWBackend.duplicate_track).
func duplicate_track(index: int) -> void: _do(&"duplicate_track", [index])
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
func shift_velocity(track_index: int, item_index: int, by: int) -> void:
	_do(&"shift_velocity", [track_index, item_index,
			clampi(by, -DAWBackend.VELOCITY_SHIFT_MAX, DAWBackend.VELOCITY_SHIFT_MAX)])
## One note of a MIDI item set to a velocity (1-127), named by its place in the item's notes.
func set_note_velocity(track_index: int, item_index: int, note_index: int, velocity: int) -> void:
	_do(&"set_note_velocity", [track_index, item_index, note_index, clampi(velocity, 1, 127)])
## Every note of a MIDI item held until the next one starts.
func legato_item(track_index: int, item_index: int) -> void:
	_do(&"legato_item", [track_index, item_index])


## An item given a name (its take's name in Reaper). One undo step; a locked item may be named.
func rename_item(track_index: int, item_index: int, item_name: String) -> void:
	_do(&"rename_item", [track_index, item_index, item_name.left(MARKER_NAME_MAX)])


## One note of a MIDI item moved `by` seconds, earlier or later, keeping its length and staying
## inside the item.
func move_note(track_index: int, item_index: int, note_index: int, by: float) -> void:
	_do(&"move_note", [track_index, item_index, note_index, by])


## One note of a MIDI item moved `by` seconds and `semitones` at once, as dragging it in a piano
## roll does: one undo step, where move_note then transpose_note would be two.
func place_note(track_index: int, item_index: int, note_index: int, by: float, semitones: int) -> void:
	_do(&"place_note", [track_index, item_index, note_index, by, clampi(semitones, -DAWBackend.TRANSPOSE_MAX, DAWBackend.TRANSPOSE_MAX)])


## One note of a MIDI item made to end `off` seconds after the item's start: cut short, or held
## longer, never past the item's end nor to before it has begun.
func set_note_end(track_index: int, item_index: int, note_index: int, off: float) -> void:
	_do(&"set_note_end", [track_index, item_index, note_index, off])


## A note put into a MIDI item from `on` to `off` seconds after its start, at a pitch, at the usual
## velocity. Kept inside the item; a full item takes no more.
func insert_note(track_index: int, item_index: int, on: float, off: float, pitch: int) -> void:
	_do(&"insert_note", [track_index, item_index, on, off, clampi(pitch, 0, 127)])


## One note of a MIDI item moved up or down by semitones, kept within the MIDI range.
func transpose_note(track_index: int, item_index: int, note_index: int, semitones: int) -> void:
	_do(&"transpose_note", [track_index, item_index, note_index, clampi(semitones, -DAWBackend.TRANSPOSE_MAX, DAWBackend.TRANSPOSE_MAX)])


## One note of a MIDI item taken out (by its place in the item's notes).
func delete_note(track_index: int, item_index: int, note_index: int) -> void:
	_do(&"delete_note", [track_index, item_index, note_index])


## The notes of a MIDI item played backwards: the last first, each keeping its length.
func retrograde_item(track_index: int, item_index: int) -> void:
	_do(&"retrograde_item", [track_index, item_index])


## Every note of a MIDI item given the item's average velocity.
func even_velocity(track_index: int, item_index: int) -> void:
	_do(&"even_velocity", [track_index, item_index])


## Every note of a MIDI item cut to half its length.
func staccato_item(track_index: int, item_index: int) -> void:
	_do(&"staccato_item", [track_index, item_index])
func humanise_item(track_index: int, item_index: int, seconds: float, velocity: int) -> void:
	_do(&"humanise_item", [track_index, item_index,
			clampf(seconds, 0.0, DAWBackend.HUMANISE_SECONDS_MAX),
			clampi(velocity, 0, DAWBackend.HUMANISE_VELOCITY_MAX)])
func transpose_item(track_index: int, item_index: int, semitones: int) -> void:
	_do(&"transpose_item", [track_index, item_index,
			clampi(semitones, -DAWBackend.TRANSPOSE_MAX, DAWBackend.TRANSPOSE_MAX)])
## `swing` from 0, straight, to 1, every off-beat a third of a step late (DAWBackend.swung_grid_beat).
func quantize_item(track_index: int, item_index: int, grid_beats: float, strength := 1.0,
		swing := 0.0) -> void:
	_do(&"quantize_item", [track_index, item_index,
			clampf(grid_beats, DAWBackend.QUANTIZE_GRID_MIN, DAWBackend.QUANTIZE_GRID_MAX),
			clampf(strength, 0.0, 1.0), clampf(swing, 0.0, DAWBackend.SWING_MAX)])
## The notes of a MIDI item pulled onto the feel of another's: its timing against a straight grid of
## `grid_beats`, slot by slot over a bar (or a beat, for a short feel), applied to this one's notes.
func groove_item(track_index: int, item_index: int, from_track: int, from_item: int, grid_beats: float,
		strength := 1.0) -> void:
	_do(&"groove_item", [track_index, item_index, from_track, from_item,
			clampf(grid_beats, DAWBackend.QUANTIZE_GRID_MIN, DAWBackend.QUANTIZE_GRID_MAX), clampf(strength, 0.0, 1.0)])
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
## A named span from `start` to `end` seconds. One undo step.
func add_region(start: float, end: float, region_name: String) -> void:
	_do(&"add_region", [maxf(start, 0.0), maxf(end, 0.0), region_name.left(MARKER_NAME_MAX)])
## The region that starts at `at`, to a millisecond.
func remove_region(at: float) -> void:
	_do(&"remove_region", [at])
## The region that starts at `at` moved, resized or renamed. One undo step.
func edit_region(at: float, start: float, end: float, region_name: String) -> void:
	_do(&"edit_region", [at, maxf(start, 0.0), maxf(end, 0.0), region_name.left(MARKER_NAME_MAX)])
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
		if locked_against(verb, args):
			return
		_call(verb, args)
		return
	Session.send_intent(verb, args)


## The backend does it, knowing what to call it in the history list.
func _call(verb: StringName, args: Array) -> void:
	backend.acting = step_name(verb, args)
	backend.callv(verb, args)
	backend.acting = ""


## What an edit is called in the history list: the verb in words, and the track it is on when it
## names one ("Kick: move item").
const NAMED_BY_TRACK := [&"move_item", &"add_fx", &"remove_fx", &"move_fx", &"create_send", &"remove_send",
		&"create_sidechain", &"set_automation", &"rename_track", &"duplicate_track", &"remove_track", &"move_track", &"set_track_group"]
func step_name(verb: StringName, args: Array) -> String:
	var words := String(verb).trim_prefix("set_").replace("_", " ")
	var by_track := verb in ITEM_EDITS or verb in NAMED_BY_TRACK or String(verb).begins_with("set_track") \
			or String(verb).begins_with("set_fx") or String(verb).begins_with("set_send")
	if by_track and not args.is_empty() and typeof(args[0]) in [TYPE_INT, TYPE_FLOAT] \
			and state != null and state.tracks.has(int(args[0])):
		return "%s: %s" % [state.track(int(args[0])).display_name(), words.trim_prefix("track ")]
	return words


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
	if verb == &"add_region":
		if args.size() != 3 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(args[1]) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(args[0])) or not is_finite(float(args[1])) \
				or float(args[1]) - maxf(float(args[0]), 0.0) < DAWBackend.MIN_ITEM_SECONDS:
			push_warning("DAW: refused a malformed add_region intent %s." % [args])
			return
		args = [maxf(float(args[0]), 0.0), float(args[1]), str(args[2]).left(MARKER_NAME_MAX)]
	if verb == &"edit_region":
		if args.size() != 4 or args.slice(0, 3).any(func(v): return typeof(v) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(v))) \
				or float(args[2]) - maxf(float(args[1]), 0.0) < DAWBackend.MIN_ITEM_SECONDS:
			push_warning("DAW: refused a malformed edit_region intent %s." % [args])
			return
		args = [float(args[0]), maxf(float(args[1]), 0.0), float(args[2]), str(args[3]).left(MARKER_NAME_MAX)]
	if verb == &"remove_region":
		if args.size() != 1 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(args[0])):
			push_warning("DAW: refused a malformed remove_region intent %s." % [args])
			return
		args = [float(args[0])]
	if verb == &"edit_marker":
		if args.size() != 3 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(args[1]) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(args[0])) or not is_finite(float(args[1])):
			push_warning("DAW: refused a malformed edit_marker intent %s." % [args])
			return
		args = [float(args[0]), maxf(float(args[1]), 0.0), str(args[2]).left(MARKER_NAME_MAX)]
	if verb == &"rename_item":
		if args.size() != 3 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(args[1]) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(args[0])) or not is_finite(float(args[1])) \
				or typeof(args[2]) not in [TYPE_STRING, TYPE_STRING_NAME]:
			push_warning("DAW: refused a malformed rename_item intent %s." % [args])
			return
		args = [int(args[0]), int(args[1]), str(args[2]).left(MARKER_NAME_MAX)]
	if verb == &"select_track_items":
		if args.size() != 1 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(args[0])):
			push_warning("DAW: refused a malformed select_track_items intent %s." % [args])
			return
		args = [int(args[0])]
	if verb == &"move_item":
		if args.size() not in [3, 4] or args.any(func(a): return typeof(a) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(a))):
			push_warning("DAW: refused a malformed move_item intent %s." % [args])
			return
		args = [int(args[0]), int(args[1]), maxf(float(args[2]), 0.0), maxi(int(args[3]) if args.size() == 4 else 0, 0)]
	if verb == &"flatten_comp":
		if args.size() != 1 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(args[0])) or int(args[0]) < 1:
			push_warning("DAW: refused a malformed flatten_comp intent %s." % [args])
			return
		args = [int(args[0])]
	if verb == &"freeze_track" or verb == &"thaw_track":
		if args.size() != 1 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(args[0])) or int(args[0]) < 1:
			push_warning("DAW: refused a malformed %s intent %s." % [verb, args])
			return
		args = [int(args[0])]
	if verb == &"set_comp":
		if args.size() != 4 or int(args[0]) < 1 or args.any(func(a): return typeof(a) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(a))):
			push_warning("DAW: refused a malformed set_comp intent %s." % [args])
			return
		args = [int(args[0]), maxf(float(args[1]), 0.0), float(args[2]), float(clampi(int(args[3]), 0, MixWire.LANES_MAX))]
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
		# Peer input: a depth that is not one of the three is the usual one, not refused -- a
		# render asked for is still a render.
		var bits := int(args[1]) if args.size() > 1 and typeof(args[1]) in [TYPE_INT, TYPE_FLOAT] \
				and is_finite(float(args[1])) else RENDER_BITS_DEFAULT
		var rate := int(args[3]) if args.size() > 3 and typeof(args[3]) in [TYPE_INT, TYPE_FLOAT] \
				and is_finite(float(args[3])) else RENDER_RATE_DEFAULT
		args = [MixWire._as_bool([args[0]]) if not args.is_empty() else false,
				bits if bits in RENDER_BITS else RENDER_BITS_DEFAULT,
				MixWire._as_bool([args[2]]) if args.size() > 2 else false,
				rate if rate in RENDER_RATES else RENDER_RATE_DEFAULT,
				MixWire._as_bool([args[4]]) if args.size() > 4 else false]
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
		if verb in [&"set_item_muted", &"set_item_locked", &"set_item_reversed"]:
			clean[2] = 1.0 if clean[2] > 0.5 else 0.0
		if verb == &"set_item_lane":
			clean[2] = float(clampi(int(clean[2]), 0, MixWire.LANES_MAX))
		if verb == &"set_item_fade_shape":
			clean[2] = DawKitClip.clean_shape(clean[2])
			clean[3] = DawKitClip.clean_shape(clean[3])
		if verb == &"set_item_gain":
			clean[2] = clampf(clean[2], DAWBackend.ITEM_GAIN_MIN, DAWBackend.ITEM_GAIN_MAX)
		if verb == &"process_item":
			clean[2] = clampi(int(clean[2]), 0, 1)
			clean[3] = _clean_process(int(clean[2]), clean[3])
		if verb == &"shift_velocity":
			clean[2] = clampi(int(clean[2]), -DAWBackend.VELOCITY_SHIFT_MAX, DAWBackend.VELOCITY_SHIFT_MAX)
		if verb == &"move_note":
			clean[2] = clampi(int(clean[2]), -1, MidiTake.MAX_NOTES)
			clean[3] = clampf(clean[3], -DAWBackend.NOTE_MOVE_MAX, DAWBackend.NOTE_MOVE_MAX)
		if verb == &"place_note":
			clean[2] = clampi(int(clean[2]), -1, MidiTake.MAX_NOTES)
			clean[3] = clampf(clean[3], -DAWBackend.NOTE_MOVE_MAX, DAWBackend.NOTE_MOVE_MAX)
			clean[4] = clampi(int(clean[4]), -DAWBackend.TRANSPOSE_MAX, DAWBackend.TRANSPOSE_MAX)
		if verb == &"set_note_end":
			clean[2] = clampi(int(clean[2]), -1, MidiTake.MAX_NOTES)
			clean[3] = maxf(clean[3], 0.0)
		if verb == &"insert_note":
			clean[2] = maxf(clean[2], 0.0)
			clean[3] = maxf(clean[3], clean[2] + MidiTake.MIN_NOTE)
			clean[4] = clampi(int(clean[4]), 0, 127)
		if verb == &"transpose_note":
			clean[2] = clampi(int(clean[2]), -1, MidiTake.MAX_NOTES)
			clean[3] = clampi(int(clean[3]), -DAWBackend.TRANSPOSE_MAX, DAWBackend.TRANSPOSE_MAX)
		if verb == &"delete_note":
			clean[2] = clampi(int(clean[2]), -1, MidiTake.MAX_NOTES)
		if verb == &"set_note_velocity":
			clean[2] = clampi(int(clean[2]), -1, MidiTake.MAX_NOTES)
			clean[3] = clampi(int(clean[3]), 1, 127)
		if verb == &"humanise_item":
			clean[2] = clampf(clean[2], 0.0, DAWBackend.HUMANISE_SECONDS_MAX)
			clean[3] = clampi(int(clean[3]), 0, DAWBackend.HUMANISE_VELOCITY_MAX)
		if verb == &"transpose_item":
			clean[2] = clampi(int(clean[2]), -DAWBackend.TRANSPOSE_MAX, DAWBackend.TRANSPOSE_MAX)
		if verb == &"groove_item":
			clean[2] = int(clean[2])
			clean[3] = int(clean[3])
			clean[4] = clampf(clean[4], DAWBackend.QUANTIZE_GRID_MIN, DAWBackend.QUANTIZE_GRID_MAX)
			clean[5] = clampf(clean[5], 0.0, 1.0)
		if verb == &"quantize_item":
			clean[2] = clampf(clean[2], DAWBackend.QUANTIZE_GRID_MIN, DAWBackend.QUANTIZE_GRID_MAX)
			clean[3] = clampf(clean[3], 0.0, 1.0)
			clean[4] = clampf(clean[4], 0.0, DAWBackend.SWING_MAX)
		args = clean
	if verb == &"nudge_selected":
		if args.size() != 2 or args.any(func(a): return typeof(a) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(a))) \
				or int(args[1]) not in [DAWBackend.NUDGE_SECONDS, DAWBackend.NUDGE_BEATS, DAWBackend.NUDGE_BARS]:
			push_warning("DAW: refused a malformed nudge_selected intent %s." % [args])
			return
		args = [float(args[0]), int(args[1])]
	if verb == &"copy_selected_to":
		if args.size() != 1 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(args[0])):
			push_warning("DAW: refused a malformed copy_selected_to intent %s." % [args])
			return
		args = [maxf(float(args[0]), 0.0)]
	if verb in [&"delete_selected", &"duplicate_selected", &"select_all_items", &"glue_selected"]:
		args = []
	if verb == &"set_item_controls":
		# Peer input: a track, an item, a kind, a channel, and flat [time, value] pairs.
		if args.size() != 5 or not (args[4] is Array) or args.slice(0, 4).any(func(v): return typeof(v) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(v))) \
				or int(args[0]) < 1 or int(args[1]) < 0 or int(args[2]) < 0 or int(args[2]) > DawKitClip.AFTERTOUCH \
				or int(args[3]) < 0 or int(args[3]) > 15 or (args[4] as Array).size() % 2 != 0 \
				or (args[4] as Array).size() > MixWire.CONTROLS_MAX * 2 \
				or (args[4] as Array).any(func(v): return typeof(v) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(v))):
			push_warning("DAW: refused a malformed set_item_controls intent.")
			return
		args = [int(args[0]), int(args[1]), int(args[2]), int(args[3]), (args[4] as Array).map(func(v): return float(v))]
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
	if verb == &"add_fx":
		# Peer input: a track, one of the plugins this DAW offers, and a slot.
		if args.size() != 3 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or int(args[0]) < 1 \
				or typeof(args[1]) != TYPE_STRING or not state.fx_choices.any(func(p): return p[0] == args[1]) \
				or typeof(args[2]) not in [TYPE_INT, TYPE_FLOAT]:
			push_warning("DAW: refused a malformed add_fx intent %s." % [args])
			return
		args = [int(args[0]), str(args[1]), maxi(int(args[2]), -1)]
	if verb == &"remove_fx":
		if args.size() != 2 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or int(args[0]) < 1 \
				or typeof(args[1]) not in [TYPE_INT, TYPE_FLOAT]:
			push_warning("DAW: refused a malformed remove_fx intent %s." % [args])
			return
		args = [int(args[0]), int(args[1])]
	if verb == &"set_track_colour":
		# Peer input: a track number and a colour.
		if args.size() != 2 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or int(args[0]) < 1 \
				or typeof(args[1]) != TYPE_COLOR:
			push_warning("DAW: refused a malformed set_track_colour intent %s." % [args])
			return
		args = [int(args[0]), _opaque(args[1])]
	if verb == &"set_track_group":
		if args.size() != 2 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or int(args[0]) < 1 \
				or typeof(args[1]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(args[1])):
			push_warning("DAW: refused a malformed set_track_group intent %s." % [args])
			return
		args = [int(args[0]), clampi(int(args[1]), 0, GROUPS)]
	if verb == &"set_vca":
		if args.size() != 2 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or int(args[0]) < 1 \
				or typeof(args[1]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(args[1])):
			push_warning("DAW: refused a malformed set_vca intent %s." % [args])
			return
		args = [clampi(int(args[0]), 1, GROUPS), clampf(float(args[1]), -60.0, 12.0)]
	if verb == &"move_track":
		if args.size() != 3 or args.any(func(a) -> bool: return typeof(a) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(a))) \
				or int(args[0]) < 1:
			push_warning("DAW: refused a malformed move_track intent %s." % [args])
			return
		args = [int(args[0]), maxi(int(args[1]), 1), maxi(int(args[2]), 0)]
	if verb in [&"remove_track", &"duplicate_track"]:
		if args.size() != 1 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or int(args[0]) < 1:
			push_warning("DAW: refused a malformed %s intent %s." % [verb, args])
			return
		args = [int(args[0])]
	if verb in [&"set_send_volume", &"set_send_pan", &"set_send_pre_fader"]:
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
	if verb == &"undo_to":
		if args.size() != 1 or typeof(args[0]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(args[0])):
			push_warning("DAW: refused a malformed undo_to intent %s." % [args])
			return
		args = [maxi(int(args[0]), 0)]
	if locked_against(verb, args):
		return
	_call(verb, args)


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
