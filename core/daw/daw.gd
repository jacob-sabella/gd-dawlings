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

const RELAYED := [&"track_added", &"track_changed", &"transport_changed", &"master_changed",
		&"fx_changed", &"timeline_changed", &"bank_changed"]

## Every verb a surface may use, as data. The same list as the methods on DAWBackend -- it is
## here as well because a guest's intent names its verb, and a verb missing from this list is a
## verb that silently stops working for everyone who is not the host.
const COMMANDS := [
	&"set_track_volume", &"set_track_pan", &"set_track_mute", &"set_track_solo",
	&"set_track_rec_arm", &"set_master_volume", &"set_master_pan",
	&"set_fx_param", &"set_fx_enabled", &"read_fx_param_text",
	&"set_track_bank",
	&"transport_play", &"transport_stop", &"transport_record",
	&"set_looping", &"set_tempo", &"seek", &"set_loop_range", &"undo", &"redo",
	&"select_item", &"clear_item_selection", &"move_item", &"split_selected",
	&"create_send", &"remove_send",
	&"set_send_volume", &"set_send_pan",
	&"set_metronome", &"add_marker",
]

var backend: DAWBackend

## Reaper's own limits on a project tempo.
const TEMPO_MIN := 1.0
const TEMPO_MAX := 960.0


func _ready() -> void:
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


## A send is named by its track and its 1-based place in that track's sends, as on the wire.
func set_send_volume(track_index: int, send_index: int, taper: float) -> void:
	_do(&"set_send_volume", [track_index, send_index, clampf(taper, 0.0, 1.0)])


func set_send_pan(track_index: int, send_index: int, pan: float) -> void:
	_do(&"set_send_pan", [track_index, send_index, clampf(pan, 0.0, 1.0)])


## Through `_do` although it changes nothing: only the host can reach Reaper, and the answer
## replicates to everyone like any other value.
func read_fx_param_text(track_index: int, fx_index: int, param: int) -> void:
	_do(&"read_fx_param_text", [track_index, fx_index, param])


func transport_play() -> void: _do(&"transport_play", [])
func transport_stop() -> void: _do(&"transport_stop", [])
func transport_record() -> void: _do(&"transport_record", [])
func set_looping(on: bool) -> void: _do(&"set_looping", [on])
func set_metronome(on: bool) -> void: _do(&"set_metronome", [on])
## Clamped to what Reaper itself accepts. A guest's intent is clamped again on the host, by
## the same function, because it arrives here rather than at the backend.
func set_tempo(bpm: float) -> void: _do(&"set_tempo", [clampf(bpm, TEMPO_MIN, TEMPO_MAX)])
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
## Longest marker name sent anywhere. Reaper takes more, but nothing here can show more, and a
## guest's intent should not be able to hand the host a megabyte of name.
const MARKER_NAME_MAX := 64
func add_marker(seconds: float, marker_name: String) -> void:
	_do(&"add_marker", [maxf(seconds, 0.0), marker_name.left(MARKER_NAME_MAX)])


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
	if verb == &"set_tempo" and args.size() == 1:
		args = [clampf(float(args[0]), TEMPO_MIN, TEMPO_MAX)]
	if verb == &"add_marker":
		if args.size() != 2:
			push_warning("DAW: refused a malformed add_marker intent %s." % [args])
			return
		args = [maxf(float(args[0]), 0.0), str(args[1]).left(MARKER_NAME_MAX)]
	if verb == &"set_metronome":
		if args.size() != 1:
			push_warning("DAW: refused a malformed set_metronome intent %s." % [args])
			return
		args = [MixWire._as_bool([args[0]])]
	if verb in [&"set_send_volume", &"set_send_pan"]:
		# Peer input. A send is a track and a 1-based slot; anything else names nothing, and a
		# level outside the taper is a fader past its end stop.
		if args.size() != 3 or int(args[0]) < 1 or int(args[1]) < 1:
			push_warning("DAW: refused a malformed %s intent %s." % [verb, args])
			return
		args = [int(args[0]), int(args[1]), clampf(float(args[2]), 0.0, 1.0)]
	backend.callv(verb, args)
