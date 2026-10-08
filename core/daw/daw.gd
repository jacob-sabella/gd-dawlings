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

## Every verb a surface may use, as data. The same list as the methods on DAWBackend -- it is
## here as well because a guest's intent names its verb, and a verb missing from this list is a
## verb that silently stops working for everyone who is not the host.
const COMMANDS := [
	&"set_track_volume", &"set_track_pan", &"set_track_mute", &"set_track_solo",
	&"set_track_rec_arm", &"set_master_volume", &"set_master_pan",
	&"set_fx_param", &"set_fx_enabled",
	&"set_track_bank",
	&"transport_play", &"transport_stop", &"transport_record",
	&"set_looping", &"seek", &"set_loop_range", &"undo", &"redo",
	&"create_send", &"remove_send",
]

var backend: DAWBackend


func _ready() -> void:
	# An autoload that opened a socket on startup would make `godot --headless` in CI try to
	# talk to a DAW. Nothing happens until a scene asks for one.
	use(OfflineBackend.new(), false)


## Install a backend. `start` is false only when the caller wants the object in place without
## opening anything, which is what a fresh process wants: the studio has to be buildable before
## the command line has been read.
func use(new_backend: DAWBackend, start: bool = true, options: Dictionary = {}) -> bool:
	if backend:
		backend.close()
		backend.queue_free()
	backend = new_backend
	add_child(backend)
	backend.connection_changed.connect(func(): connection_changed.emit())
	backend.is_authority = Session.is_authority()
	var ok := backend.open(options) if start else true
	connection_changed.emit()
	return ok


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


func transport_play() -> void: _do(&"transport_play", [])
func transport_stop() -> void: _do(&"transport_stop", [])
func transport_record() -> void: _do(&"transport_record", [])
func set_looping(on: bool) -> void: _do(&"set_looping", [on])
func seek(seconds: float) -> void: _do(&"seek", [maxf(seconds, 0.0)])
func set_loop_range(start: float, end: float) -> void:
	_do(&"set_loop_range", [maxf(minf(start, end), 0.0), maxf(maxf(start, end), 0.0)])
func undo() -> void: _do(&"undo", [])
func redo() -> void: _do(&"redo", [])


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
	backend.callv(verb, args)
