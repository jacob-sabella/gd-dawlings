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
	## Drop a marker on the arrangement. Reaper's OSC can go to a marker but not make one.
	MARKERS = &"markers",
	## Put a take of MIDI notes on a track at a song position. Reaper needs the ReaScript bridge
	## for it; OSC has no message that creates an item.
	MIDI_TAKES = &"midi_takes",
	## Put a recorded audio file on a track at a song position. Reaper needs the bridge for it,
	## for the same reason.
	AUDIO_TAKES = &"audio_takes",
	## Rearrange a plugin chain: move or copy a plugin to another slot or another track. Reaper
	## needs the bridge; OSC can turn a plugin's knobs but cannot pick it up.
	FX_CHAIN = &"fx_chain",
	## Step through a plugin's presets by name. Only a DAW that knows a plugin's presets can.
	FX_PRESETS = &"fx_presets",
	## Show a plugin's own window somewhere else and work it from there: see PluginWindow.
	PLUGIN_WINDOW = &"plugin_window",
	## Save the open project where it was last saved or opened from. Reaper saves through its
	## own action; the built-in engine and the stand-in write DAWproject.
	PROJECT_SAVE = &"project_save",
	## Open a project file, save to a new one and start an empty one: only an engine that owns
	## its project files can, because a remote DAW's files are on its own machine.
	PROJECT_FILES = &"project_files",
	## Records the host's own inputs itself, when its transport records: Reaper, from its own
	## inputs. A DAW that cannot is given the host's microphone and keys by the game, the way a
	## guest's are (GuestAudio and GuestMidi, as the host).
	RECORDS_OWN_INPUTS = &"records_own_inputs",
}

var state := MixState.new()
## The overview of every take placed through this backend, by file name: a DAW that reports
## its items back (Reaper) reports the file, never the overview.
var take_peaks := {}

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


## True while the DAW has said more than this has yet taken in: a refresh from Reaper is tens of
## thousands of messages, applied a few milliseconds' worth a frame. Gear holds its rebuilds
## until it is false, so a busy project is built once when it has arrived, not once a frame
## as each piece of it does.
func catching_up() -> bool:
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
## Input monitoring, as Reaper's I_RECMON numbers it: 0 off, 1 on, 2 auto (on while armed and
## stopped, or recording -- what you hear on a punch-in).
func set_track_monitor(_index: int, _mode: int) -> void: pass

func set_master_volume(_taper: float) -> void: pass
func set_master_pan(_pan: float) -> void: pass

func set_fx_param(_track_index: int, _fx_index: int, _param: int, _value: float) -> void: pass
func set_fx_enabled(_track_index: int, _fx_index: int, _enabled: bool) -> void: pass
## The plugin's own wet/dry, 0..1, where 1 is all plugin.
func set_fx_wet(_track_index: int, _fx_index: int, _wet: float) -> void: pass
## The plugin's next (1) or previous (-1) preset. A no-op without Capability.FX_PRESETS.
func step_fx_preset(_track_index: int, _fx_index: int, _direction: int) -> void: pass
## Take plugin `fx_index` off `from_track` and put it in slot `to_fx` of `to_track`, pushing what
## is there down -- or leave the original where it is and put a copy there. Slots are numbered as
## this backend numbers them in the cache, and a `to_fx` past the end of the chain means the
## end. A no-op without Capability.FX_CHAIN.
func move_fx(_from_track: int, _fx_index: int, _to_track: int, _to_fx: int, _copy: bool) -> void: pass

## One send's level and pan. `send_index` is the send as the wire numbers it: 1-based, in the
## track's own send order -- `/track/3/send/1` is track 3's first send. Same 0..1 taper as a
## track fader for the level, 0.5 centre for the pan.
func set_send_volume(_track_index: int, _send_index: int, _taper: float) -> void: pass
func set_send_pan(_track_index: int, _send_index: int, _pan: float) -> void: pass
## Ask for the plugin's own reading of one parameter ("-12.0 dB"), to arrive later as the
## parameter's text in the cache. A backend that cannot know a plugin's units says nothing, and
## the rack shows the plain percentage it always could.
func read_fx_param_text(_track_index: int, _fx_index: int, _param: int) -> void: pass
## Read `params` of a plugin into the cache -- values, names, the plugin's words -- or with none,
## list its real parameters as FXState.param_list. A backend whose cache already holds every
## parameter, like the stand-in, has nothing to fetch.
func read_fx_params(_track_index: int, _fx_index: int, _params: Array) -> void: pass
## The plugin's own window, live, or null without Capability.PLUGIN_WINDOW. Whoever opens it
## closes it.
func open_plugin_window(_track_index: int, _fx_index: int) -> PluginWindow: return null

## Show the slice of the project starting at `offset` tracks in. A no-op on a backend that
## answers false to Capability.TRACK_BANKING.
func set_track_bank(_offset: int) -> void: pass

func transport_play() -> void: pass
func transport_stop() -> void: pass
func transport_record() -> void: pass
## Playback wraps round the loop range, or does not.
func set_looping(_on: bool) -> void: pass
## Where the open project lives on disk, or empty when it has never been saved.
var project_path := ""
## Saves the project. `path` empty means where it already is; returns what went wrong or could
## not be saved, as sentences, empty when all of it was written.
func save_project(_path: String) -> PackedStringArray: return PackedStringArray(["this DAW cannot save from here"])
## Opens a project file in place of the open one; returns what went wrong, empty on success.
func open_project(_path: String) -> PackedStringArray: return PackedStringArray(["this DAW cannot open files from here"])
## Replaces the open project with an empty one.
func new_project() -> PackedStringArray: return PackedStringArray(["this DAW cannot start a project from here"])
## The click, on or off.
func set_metronome(_on: bool) -> void: pass
## The project tempo, in beats per minute. Constant-tempo projects only: a project with a tempo
## map has its first marker moved, which is what Reaper's own tempo field does.
func set_tempo(_bpm: float) -> void: pass
## Move the playhead. Seconds from the project start.
func seek(_seconds: float) -> void: pass
## The loop range / time selection, in seconds.
func set_loop_range(_start: float, _end: float) -> void: pass
func undo() -> void: pass
func redo() -> void: pass

## Item editing. Items are (track, index in lane, left to right). `additive` adds to or takes
## from the selection instead of replacing it.
func select_item(_track_index: int, _item_index: int, _additive: bool) -> void: pass
func clear_item_selection() -> void: pass
func move_item(_track_index: int, _item_index: int, _start: float) -> void: pass
## Cut every selected item that spans `seconds` there. Both halves stay selected.
func split_selected(_seconds: float) -> void: pass
## A marker at `seconds`, called `marker_name`. An edit, so it is undoable where the DAW keeps
## history. A no-op on a backend that answers false to Capability.MARKERS.
func add_marker(_seconds: float, _marker_name: String) -> void: pass

## A take of notes, placed by song position: a new MIDI item on `track_index` from `start` to
## `end` seconds, holding `notes` as [on, off, pitch, velocity, channel] rows in absolute
## seconds. One undo step. Arguments arrive already cleaned (MidiTake.clean_args). A backend
## that cannot do it answers false to Capability.MIDI_TAKES.
func insert_midi_take(_track_index: int, _start: float, _end: float, _notes: Array,
		_name: String) -> void: pass

## A recorded take: a new audio item on `track_index` at `start` seconds, `length` long, playing
## `source` -- a file name in AudioTake.DIR on this machine -- from its beginning. `peaks` is the
## file's overview, for drawing. One undo step. Only ever called on the host, by the host: a
## guest's audio arrives through Session, never as an intent, so no peer can name a file. A
## backend that cannot do it answers false to Capability.AUDIO_TAKES.
func insert_audio_take(_track_index: int, _start: float, _source: String, _length: float,
		_peaks: PackedByteArray, _name: String) -> void: pass


# --- item edits, on the cache ------------------------------------------------------------
#
# The same edits every backend has to show the moment they are made: the offline mix because the
# cache IS its project, a live one because the DAW's answer is a round trip away and a block that
# stays put for a beat after you let go of it reads as a drop that did not take.

## Replace one lane, through the same address the timeline arrives on, so it replicates.
func _write_lane(track_index: int, items: Array) -> void:
	var packed := MixWire._pack_items(items)
	record_for_replication("/track/%d/items" % track_index, packed)
	MixWire.apply(state, "/track/%d/items" % track_index, packed)


## A lane's items as fresh objects, so an edit never mutates what a surface is still drawing.
func _lane_copy(track_index: int) -> Array:
	return MixWire._unpack_items(MixWire._pack_items(state.track(track_index).items))


func _locally_select(track_index: int, item_index: int, additive: bool) -> void:
	if state.item(track_index, item_index) == null:
		return
	for index in state.track_indices():
		var t := state.track(index)
		var touched: bool = index == track_index
		if not additive:
			for item in t.items:
				touched = touched or item.selected
		if not touched:
			continue
		var lane := _lane_copy(index)
		for item in lane:
			var target: bool = index == track_index and item.index == item_index
			if target:
				item.selected = not item.selected if additive else true
			elif not additive:
				item.selected = false
		_write_lane(index, lane)


func _locally_clear_selection() -> void:
	for index in state.track_indices():
		var any := false
		for item in state.track(index).items:
			any = any or item.selected
		if any:
			var lane := _lane_copy(index)
			for item in lane:
				item.selected = false
			_write_lane(index, lane)


func _locally_move(track_index: int, item_index: int, start: float) -> void:
	if state.item(track_index, item_index) == null:
		return
	var lane := _lane_copy(track_index)
	lane[item_index].start = maxf(start, 0.0)
	_write_lane(track_index, lane)


## Returns how many items were cut.
func _locally_split(seconds: float) -> int:
	var cut := 0
	for index in state.track_indices():
		var hit := false
		for item in state.track(index).items:
			hit = hit or (item.selected and item.contains(seconds))
		if not hit:
			continue
		var lane := _lane_copy(index)
		var added: Array = []
		for item in lane:
			if item.selected and item.contains(seconds):
				var right := MixState.ItemState.new()
				right.start = seconds
				right.length = item.end() - seconds
				right.name = item.name
				right.muted = item.muted
				right.selected = true
				right.source = item.source
				right.peaks = item.peaks
				right.source_offset = item.source_offset + (seconds - item.start)
				# Each half keeps the end it had: the fade in stays on the left, the fade out goes
				# with the right, and both keep the clip's gain.
				right.gain_db = item.gain_db
				right.loop_start = item.loop_start
				right.loop_end = item.loop_end
				right.fade_out = minf(item.fade_out, right.length)
				_split_notes(item, right, seconds)
				item.length = seconds - item.start
				item.fade_out = 0.0
				item.fade_in = minf(item.fade_in, item.length)
				added.append(right)
				cut += 1
		lane.append_array(added)
		_write_lane(index, lane)
	return cut


## A cut MIDI item's notes go with the half they start in, and a note that runs over the cut is
## shortened to it: what Reaper does with a split that crosses a held note.
func _split_notes(left: MixState.ItemState, right: MixState.ItemState, seconds: float) -> void:
	if left.notes.is_empty():
		return
	var keep: Array = []
	var moved: Array = []
	for n in MidiTake.unpack_relative(left.notes, left.start):
		if n[0] < seconds:
			n[1] = minf(n[1], seconds)
			keep.append(n)
		else:
			moved.append(n)
	left.notes = MidiTake.pack_relative(keep, left.start)
	right.notes = MidiTake.pack_relative(moved, seconds)


## A take's item, drawn at once: the offline project's whole edit, and a live DAW's preview of
## the answer the bridge is about to give.
func _locally_insert_take(track_index: int, start: float, end: float, notes: Array,
		take_name: String) -> void:
	var lane := _lane_copy(track_index)
	var item := MixState.ItemState.new()
	item.start = start
	item.length = end - start
	item.name = take_name
	item.notes = MidiTake.pack_relative(notes, start)
	lane.append(item)
	_write_lane(track_index, lane)


func _locally_insert_audio(track_index: int, start: float, source: String, length: float,
		peaks: PackedByteArray, take_name: String) -> void:
	take_peaks[source] = peaks
	var lane := _lane_copy(track_index)
	var item := MixState.ItemState.new()
	item.start = start
	item.length = length
	item.name = take_name
	item.source = source
	item.peaks = peaks
	lane.append(item)
	_write_lane(track_index, lane)


## Every lane with something in it, packed, for an undo step to put back.
func _lanes_snapshot() -> Dictionary:
	var out := {}
	for index in state.track_indices():
		out[index] = MixWire._pack_items(state.track(index).items)
	return out


## Every marker, through the address the timeline delivers them on, so it replicates.
func _write_markers(markers: Dictionary) -> void:
	var packed := MixWire._pack_markers(markers)
	record_for_replication("/timeline/markers", packed)
	MixWire.apply(state, "/timeline/markers", packed)


func _restore_lanes(snapshot: Dictionary) -> void:
	for index in snapshot:
		var packed: Array = snapshot[index]
		record_for_replication("/track/%d/items" % index, packed)
		MixWire.apply(state, "/track/%d/items" % index, packed)

## Return false when the routing change could not be made, so a surface can decline the gesture
## rather than draw a cable that is not there.
func create_send(_from_track: int, _to_track: int) -> bool: return false
func remove_send(_from_track: int, _send_index: int) -> bool: return false
## A send into `to_track`'s key input (channels 3/4) rather than into its mix: what a compressor
## or gate on that track listens to when it is set to its sidechain. Removed like any send.
func create_sidechain(_from_track: int, _to_track: int) -> bool: return false


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
