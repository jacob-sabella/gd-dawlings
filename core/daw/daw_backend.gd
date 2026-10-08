class_name DAWBackend
extends Node

## One DAW, behind one vocabulary.
##
## WHY THIS EXISTS. Everything above this line -- the console, the rack, the patchbay, the tape
## deck -- is a piece of hardware that knows about tracks, levels, plugins and a transport. None
## of that is a Reaper concept. Reaper's share of it is an OSC address space, a fader taper, a
## pattern file, and a ReaScript bridge for the things OSC cannot express, and all four are
## facts about Reaper rather than about mixing. They belong in one file, which is a subclass of
## this one, so that adding Live or Bitwig means writing a sibling rather than auditing every
## surface for the word "Reaper".
##
## THE CONTRACT, in three parts:
##
##   STATE      a backend keeps `state` up to date. It is a MixState and nothing more; a DAW
##              with concepts this model lacks either maps them in or does without.
##   COMMANDS   the verbs below. A backend translates each into whatever its DAW understands.
##              The vocabulary is deliberately small and deliberately a MIXER's: there is no
##              `send_osc` here and there never should be.
##   CAPABILITY a backend says what it cannot do. Not every control protocol can create a send
##              or rename a track, and a surface that offers a gesture the DAW will refuse is
##              worse than one that greys it out. See `can()`.
##
## WHAT IS NOT A BACKEND'S BUSINESS: who is hosting the session, whether this participant is a
## guest, where the surfaces are, or what medium anyone is wearing. A guest's writes are routed
## before they reach here -- see core/daw/daw.gd.

signal connection_changed()

## Replication tick. 20Hz, deliberately slower than a typical meter stream: the buffers below
## are keyed, so a faster-arriving value overwrites the pending one and the tick rate becomes
## the rate limit for free.
const REPLICATION_HZ := 20.0

## Things a backend may or may not be able to do. Asked by surfaces before they offer a gesture.
const Capability := {
	## Create and remove routing between tracks. Reaper needs a ReaScript bridge for this
	## because OSC cannot express it; a DAW whose protocol can do it natively says true and a
	## DAW whose protocol genuinely cannot says false, and the patchbay reads the answer rather
	## than finding out when the drop silently does nothing.
	ROUTING = &"routing",
	## Arm tracks for recording.
	RECORD_ARM = &"record_arm",
	## Move the visible bank of tracks. True only when the backend has both a way to ask for a
	## different slice and a way to know how big the project is -- a bank button that can page
	## forward but cannot say whether there is anything there is worse than no button.
	TRACK_BANKING = &"track_banking",
	## Report the arrangement: where the items on each track start and how long they are. A
	## backend that says false is saying "I cannot see the timeline", which the timeline
	## surface draws differently from "the timeline is empty" -- the first is a limitation to
	## state and the second is a project to start working in.
	TIMELINE = &"timeline",
	## Report plugin parameter names rather than just indices.
	FX_PARAM_NAMES = &"fx_param_names",
}

var state := MixState.new()

## Pending replication, keyed so repeats collapse. Split in two because the two halves need
## opposite delivery guarantees, and sending both the same way is wrong either way:
##
##   DURABLE   names, levels, mute/solo, plugin parameters. Sent RELIABLY. These are
##             edge-triggered -- a value is only resent when it changes -- so a dropped packet
##             loses that change permanently.
##   VOLATILE  meters and the playhead. Sent UNRELIABLY. These are level-triggered and arrive
##             again in 50ms regardless; spending retransmits on a meter reading that is stale
##             before it lands is how the durable half ends up late.
##
## Here rather than in a subclass because the split is a property of the DATA, not of the DAW.
var _repl_durable: Dictionary = {}
var _repl_volatile: Dictionary = {}
var _repl_accumulator := 0.0
## False on a participant receiving state from someone else, which must never replicate it on.
var is_authority := true


# --- lifecycle ----------------------------------------------------------------------------

## Open whatever this backend talks over. `options` is backend-specific and documented by the
## subclass; a backend that needs nothing ignores it.
func open(_options: Dictionary = {}) -> bool:
	return true


func close() -> void:
	pass


## Is there a DAW on the other end and has it said anything. Distinct from "did open() succeed":
## an OSC socket opens fine with nothing listening, which is the single most common way this
## project looks broken.
func is_live() -> bool:
	return false


## One line for the corner readout. Every failure mode of this project looks identical from the
## inside -- a silent port, a wrong bank size, an idle DAW -- so this says which one it is.
func summary() -> String:
	return "no backend"


## What this backend can and cannot do. Default is "everything", because a backend that forgets
## to declare a limitation should fail loudly at the point of use rather than quietly disable a
## feature nobody then investigates.
func can(_capability: StringName) -> bool:
	return true


# --- commands -----------------------------------------------------------------------------
#
# The whole vocabulary. A surface may call nothing else, and `DAW.COMMANDS` below is this list
# again as data -- keep them together or a guest's intents will silently stop working for a verb
# that was added to one and not the other.

func set_track_volume(_index: int, _taper: float) -> void: pass
func set_track_pan(_index: int, _pan: float) -> void: pass
func set_track_mute(_index: int, _muted: bool) -> void: pass
func set_track_solo(_index: int, _soloed: bool) -> void: pass
func set_track_rec_arm(_index: int, _armed: bool) -> void: pass

func set_master_volume(_taper: float) -> void: pass
func set_master_pan(_pan: float) -> void: pass

func set_fx_param(_track_index: int, _fx_index: int, _param: int, _value: float) -> void: pass
func set_fx_enabled(_track_index: int, _fx_index: int, _enabled: bool) -> void: pass

## Show the slice of the project starting at `offset` tracks in. A no-op on a backend that
## answers false to Capability.TRACK_BANKING.
func set_track_bank(_offset: int) -> void: pass

func transport_play() -> void: pass
func transport_stop() -> void: pass
func transport_record() -> void: pass
## Playback wraps round the loop range, or does not.
func set_looping(_on: bool) -> void: pass
## Move the playhead. Seconds from the project start.
func seek(_seconds: float) -> void: pass
## The loop range / time selection, in seconds.
func set_loop_range(_start: float, _end: float) -> void: pass
func undo() -> void: pass
func redo() -> void: pass

## Return false when the routing change could not be made, so a surface can decline the gesture
## rather than draw a cable that is not there.
func create_send(_from_track: int, _to_track: int) -> bool: return false
func remove_send(_from_track: int, _send_index: int) -> bool: return false


# --- fader law ----------------------------------------------------------------------------

## Normalised fader position to dB, for labelling a cap that is being dragged right now.
##
## The default is Reaper's own taper, measured (see FaderLaw); a backend whose DAW differs
## overrides both. Prefer a dB value the DAW actually sent over calling this.
func taper_to_db(taper: float) -> float:
	return FaderLaw.to_db(taper)


func db_to_taper(db: float) -> float:
	return FaderLaw.to_taper(db)


# --- replication --------------------------------------------------------------------------
#
# The wire format of a snapshot and of a replicated entry is BACKEND-DEFINED: entries are
# [key, args] pairs in whatever vocabulary that backend parses. Both ends of a session therefore
# have to be running the same backend, which is already true for the far better reason that they
# are looking at the same DAW.

## Everything a freshly joined participant needs to draw the session, as [key, args] entries in
## the same vocabulary as the live stream. Same vocabulary on purpose: a receiver then has
## exactly one code path for "state arrived", and a field added to the parser is replicated the
## day it is parsed rather than the day someone remembers to add it to a serialiser.
func snapshot() -> Array:
	return []


## State arriving from the session host. Deliberately not routed through the outbound path or
## any echo guard -- this is authority speaking, and a receiver has nothing of its own to
## protect against.
func apply_replicated(_batch: Array) -> void:
	pass


## Called by a subclass for every inbound change, BEFORE it is parsed. Before, not after,
## because a message this build does not yet understand is still one a guest should receive:
## the guest runs the same parser, so a surface added there and not here would otherwise be
## starved of data by its own host.
func record_for_replication(key: String, args: Array) -> void:
	if not is_authority:
		return
	if is_volatile(key):
		_repl_volatile[key] = args
	else:
		_repl_durable[key] = args


## Meters and the playhead. Everything else is durable. Overridable, since a backend whose keys
## look nothing like these has to answer for its own.
##
## The playhead test is for `/time` EXACTLY and `/time/...`, not for the prefix. `/timeline/...`
## carries the arrangement, which is edge-triggered structure -- classified volatile it would be
## sent unreliably, dropped by the first lossy frame, and never resent, so a guest would show a
## project with no items in it and nothing would report an error.
func is_volatile(key: String) -> bool:
	return key.contains("/vu") or key == "/time" or key.begins_with("/time/") \
			or key == "/beat/str"


func tick_replication(delta: float) -> void:
	_repl_accumulator += delta
	if _repl_accumulator < 1.0 / REPLICATION_HZ:
		return
	_repl_accumulator = 0.0
	if _repl_durable.is_empty() and _repl_volatile.is_empty():
		return
	if Session.participants.size() <= 1:
		# Solo, or hosting with nobody connected. Cleared rather than left to grow into a
		# backlog that would land in one burst the moment someone joins.
		_repl_durable.clear()
		_repl_volatile.clear()
		return
	Session.broadcast_state(_repl_durable.duplicate(), _repl_volatile.duplicate())
	_repl_durable.clear()
	_repl_volatile.clear()
