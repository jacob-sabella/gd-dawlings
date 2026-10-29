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
## Tracks were added, removed or put back by an undo: `map` is old index -> new index, and a track
## that is gone is not in it. For whatever keeps a track by its number outside the mix.
signal tracks_renumbered(map: Dictionary)
## A render is done: the files written, and anything that went wrong (both empty when there was
## nothing to render). See `render`.
signal render_finished(files: PackedStringArray, problems: PackedStringArray)

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
	## Write the mix, and each track's stem, to sound files: see `render`.
	RENDER = &"render",
	## Reorder tracks and put them in and out of folders (move_track).
	TRACK_ORDER = &"track_order",
	## Fold everything one gesture writes into one undo step, whatever it writes (open_edit and
	## close_edit). Reaper can only through the bridge; its plain OSC writes stay its own steps.
	EDIT_GROUPS = &"edit_groups",
	## Set how wide a track's stereo image is (set_track_width): the stage table's ring. Reaper
	## only through the bridge, which puts the track in its stereo pan mode to have one.
	WIDTH = &"width",
	## Hold one lane of automation off following the song (hold_lane) while a write bead writes
	## over it. Reaper only through the bridge, which switches the envelope off and back; without
	## it the bead still writes, and the lane plays over the player while they do.
	LANE_HOLD = &"lane_hold",
	## Paste a clip carried on a cassette onto a track as a new item (paste_item): a MIDI item with
	## its notes and controls, or an audio item with its file, offset, fades, gain and loop. Reaper
	## only through the bridge, whose PasteItem makes the item; OSC cannot make one.
	PASTE_ITEMS = &"paste_items",
	## Play a demo part (ItemState.part) in an item's window: the built-in demo song's parts are the
	## built-in engine's and its stand-in's alone. Reaper has no parts, so a demo cassette is refused
	## there (docs/spatial_loop.md part two, slice 24).
	DEMO_PARTS = &"demo_parts",
	## Sound the song where the playhead is dragged (scrub): the DJ platter turned by hand plays it
	## there (docs/spatial_loop.md part two, slice 27). The built-in engine plays short windows of
	## the mix; Reaper takes OSC's scrub. A DAW that cannot is moved by quiet seeks, and the
	## platter's card says so.
	SCRUB = &"scrub",
	## Lay the song's sections end to end in a new order (arrange_sections): the items, markers,
	## regions, automation and comps between the first region's start and the last's end, as one
	## edit (docs/spatial_loop.md part two, slice 29). Reaper only through the bridge, whose
	## ArrangeSections splits and moves them inside one Undo block; OSC can move none of it.
	ARRANGE = &"arrange",
	## Measure each track's spectrum (Spectra, GodotBackend.track_spectrum): the EQ wall's shapes
	## (docs/spatial_loop.md part two, slice 36). Only where the tracks are played: the built-in
	## engine. Reaper hands its tracks' audio to nobody, so the wall says "spectra need the
	## built-in engine".
	SPECTRA = &"spectra",
	## Keep the song's lyrics (set_lyrics, MixState.lyrics; docs/spatial_loop.md part two, slice 56):
	## the built-in engine and the stand-in in the .dawproject's metadata comment, Reaper in its
	## project notes through the bridge's SetLyrics. OSC has no notes.
	LYRICS = &"lyrics",
}


## The shortest an item can be trimmed to, and the range of an item's own gain.
const MIN_ITEM_SECONDS := 0.01
const ITEM_GAIN_MIN := -60.0
## A quantise grid, in beats: no finer than a 128th note, no coarser than a bar of 4/4 four times.
const QUANTIZE_GRID_MIN := 1.0 / 32.0
const QUANTIZE_GRID_MAX := 16.0
## Swing at 1 puts every off-beat grid point a third of a step late: the triplet feel. 0 is straight.
const SWING_MAX := 1.0
const TRANSPOSE_MAX := 48
const VELOCITY_SHIFT_MAX := 126
## The most a humanise may move a note (seconds) and change its velocity, either way.
const HUMANISE_SECONDS_MAX := 0.1
const HUMANISE_VELOCITY_MAX := 40
const ITEM_GAIN_MAX := 24.0

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
## How wide the track's stereo image is: 0 folds it to mono, 1 leaves it as it was recorded.
## One undo step. A no-op without Capability.WIDTH.
func set_track_width(_index: int, _width: float) -> void: pass
func set_track_mute(_index: int, _muted: bool) -> void: pass
func set_track_solo(_index: int, _soloed: bool) -> void: pass
func set_track_rec_arm(_index: int, _armed: bool) -> void: pass
## Input monitoring, as Reaper's I_RECMON numbers it: 0 off, 1 on, 2 auto (on while armed and
## stopped, or recording -- what you hear on a punch-in).
func set_track_monitor(_index: int, _mode: int) -> void: pass
## What a track records from: one of `state.inputs` by id, or "" for whatever the recorder is set
## to. Saved with the project.
func set_track_input(_index: int, _input: String) -> void: pass
func set_track_automation_mode(_index: int, _mode: int) -> void: pass

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
## Taken before the track's fader and pan rather than after.
func set_send_pre_fader(_track_index: int, _send_index: int, _pre: bool) -> void: pass
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
## Whether this one plugin has a window to open: every one does in a DAW, but Godot's own
## effects in the built-in engine have none.
func has_plugin_window(_track_index: int, _fx_index: int) -> bool: return true
## Whether the DAW's OWN plugins' windows -- drawn by the DAW's toolkit, not the plugin's -- take
## the clicks a PluginWindow passes on, as well as showing. True unless a backend knows otherwise.
func works_own_plugin_windows() -> bool: return true

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
## The bus a track's live instrument plays on in this engine, for keys played into it to be heard
## through the track; empty where the engine has no such bus (Reaper monitors its own inputs).
func monitor_bus(_track_index: int) -> StringName: return &""
## A track's instrument plugin, hosted here (DawKitPlugin), or null. Only the built-in engine
## hosts plugins itself; a DAW's own are played through the DAW.
func track_instrument(_track_index: int) -> Object: return null
## The samples of delay the plugin in a slot adds (what it reports), 0 for none or where the
## engine does not host plugins itself.
func fx_latency(_track_index: int, _fx_index: int) -> int: return 0


func save_project(_path: String) -> PackedStringArray: return PackedStringArray(["this DAW cannot save from here"])
## Opens a project file in place of the open one; returns what went wrong or was left out of it
## as sentences. It opened when `project_path` is `path` afterwards, whatever it returns.
func open_project(_path: String) -> PackedStringArray: return PackedStringArray(["this DAW cannot open files from here"])
## Replaces the open project with an empty one.
func save_template(_template_name: String) -> PackedStringArray: return PackedStringArray(["this DAW cannot keep templates"])
func new_project_from_template(_template_name: String) -> PackedStringArray: return PackedStringArray(["this DAW cannot start from a template"])
func new_project(_tracks := 4) -> PackedStringArray: return PackedStringArray(["this DAW cannot start a project from here"])
## Whether anything changed since the project was saved, opened or started. A DAW that cannot
## say answers false.
func has_unsaved_changes() -> bool: return false
## Takes the project as it is now for the saved one.
func mark_clean() -> void: pass
## The click, on or off.
func set_metronome(_on: bool) -> void: pass
## Bars of click before recording starts, 0 for none (MixState.count_in_bars). Not a history
## step, as the click is not.
func set_count_in(_bars: int) -> void: pass
## The count-in before playback as well (MixState.count_in_play). Not a history step either.
func set_count_in_play(_on: bool) -> void: pass
## Pre-roll: the song under the count-in (MixState.pre_roll). Not a history step either.
func set_pre_roll(_on: bool) -> void: pass
## The time signature's changes, as MixState.time_signature_points: [beat, numerator,
## denominator], the first at beat 0 and the song's own; one point is one signature.
func set_time_signature_map(_points: Array) -> void: pass
## Punching in and out to the loop range (MixState.punch). Not a history step.
func set_punch(_on: bool) -> void: pass
## The project tempo, in beats per minute. Constant-tempo projects only: a project with a tempo
## map has its first marker moved, which is what Reaper's own tempo field does.
func set_tempo(_bpm: float) -> void: pass
## Move the playhead. Seconds from the project start.
func seek(_seconds: float) -> void: pass
## The playhead dragged to `seconds` by a hand moving the song `speed` song-seconds a second
## (negative is backwards), heard there where the DAW can (Capability.SCRUB): not history, and
## the transport left as it is. Where it cannot, a quiet seek.
func scrub(seconds: float, _speed: float) -> void:
	seek(seconds)
## The loop range / time selection, in seconds.
func set_loop_range(_start: float, _end: float) -> void: pass
func undo() -> void: pass
func redo() -> void: pass
## Undone or redone to `depth` steps of history, in one go: the history list's jump.
func undo_to(_depth: int) -> void: pass
## What the edit under way is called, for the history list: set by DAW around each call, "" when
## nobody said.
var acting := ""
## Whose edit it is: the peer a guest's intent came from, 0 for this machine's own. Set by DAW
## around each call, as `acting` is, so an edit group is the one its own player opened.
var acting_peer := 0

## Edit groups (Capability.EDIT_GROUPS): one undo step per gesture, however many values it writes.
## A drag that moves pan and volume at once alternates between two controls, and folding by time
## and control (as a single fader's drag folds) would make a step of almost every frame. Between
## `open_edit` and `close_edit` everything `acting_peer` writes is one step, called `edit_name`,
## in the place in history where its first write was. One edit open per player: another
## player's write in between is a step of its own. An edit opened over one still open closes the
## first. Closed as well by an undo or a redo, by EDIT_IDLE_MSEC with nothing written, and by the
## player leaving the session (DAW.close_edits_of), so a lost let-go cannot hold history open.
func open_edit(_edit_name: String) -> void: pass
func close_edit() -> void: pass
## An open edit nothing has been written into for this long is closed.
const EDIT_IDLE_MSEC := 10000

## Lanes held off following the song (Capability.LANE_HOLD): [track index, target] -> the player
## holding it (`acting_peer`). A write bead (WriteBead) holds the lane it writes for as long as it
## is out, so its player hears the control they move rather than the lane they are writing over,
## and its pass replaces that stretch of the lane when it ends (set_automation). Not history, not a
## touch pass and not an automation mode: nothing times it out but the let-go, or its player
## leaving (`release_lanes_of`).
var held_lanes := {}


## A lane another player holds is theirs: neither held again nor let go by anybody else, so one
## guest cannot let go of another's lane under their bead (`acting_peer` is who asks).
func hold_lane(track_index: int, target: String, on: bool) -> void:
	var key := [track_index, target]
	if held_lanes.has(key) and int(held_lanes[key]) != acting_peer:
		push_warning("DAW: refused player %d's %s of lane %s, held by player %d." % [acting_peer, "hold" if on else "let-go", key, int(held_lanes[key])])
		return
	if on:
		held_lanes[key] = acting_peer
	elif held_lanes.has(key):
		held_lanes.erase(key)
	else:
		return
	_hold_lane(track_index, target, on)


## Whether lane `target` of `track_index` is held (hold_lane).
func lane_held(track_index: int, target: String) -> bool:
	return held_lanes.has([track_index, target])


## Every lane `peer` (0 for this machine) holds, followed again.
func release_lanes_of(peer: int) -> void:
	var was := acting_peer
	acting_peer = peer
	for key in held_lanes.keys():
		if int(held_lanes[key]) == peer:
			hold_lane(int(key[0]), str(key[1]), false)
	acting_peer = was


## Override: the lane held or let go, in whatever this DAW follows lanes with.
func _hold_lane(_track_index: int, _target: String, _on: bool) -> void: pass

## Item editing. Items are (track, index in lane, left to right). `additive` adds to or takes
## from the selection instead of replacing it.
func select_item(_track_index: int, _item_index: int, _additive: bool) -> void: pass
func clear_item_selection() -> void: pass
## Every item on every track, selected.
func select_all_items() -> void: pass
func select_track_items(_track_index: int) -> void: pass
## `to_track`, when it is another track, moves the item onto that one as well: off one shelf and
## onto another. 0 keeps it where it is.
func move_item(_track_index: int, _item_index: int, _start: float, _to_track := 0) -> void: pass
## Cut every selected item that spans `seconds` there. Both halves stay selected.
func split_selected(_seconds: float) -> void: pass
## Every selected item, gone.
func delete_selected() -> void: pass
func ripple_delete_selected() -> void: pass
## On each track, the selected items glued into one (glue_picks says which). One undo step.
func glue_selected() -> void: pass
## Every selected, unlocked item moved by `amount` of `unit` (NUDGE_SECONDS, NUDGE_BEATS or
## NUDGE_BARS; less than nothing is earlier), along the tempo map from where each one starts, none
## before the song's start. One undo step; a nudge that moves nothing is none.
func nudge_selected(_amount: float, _unit: int) -> void: pass
const NUDGE_SECONDS := 0
const NUDGE_BEATS := 1
const NUDGE_BARS := 2
## A copy of every selected item, straight after it; the copies are then the selection, as Reaper's
## own Duplicate leaves it.
func duplicate_selected() -> void: pass
## Copies of the selected items with the earliest one's start put at `seconds`, each on its own
## track and keeping its distance from the others. The originals stay selected.
func copy_selected_to(_seconds: float) -> void: pass
## An item's edges moved to `start` and `end` seconds, its contents staying where they are in the
## song: trimming, not moving.
func trim_item(_track_index: int, _item_index: int, _start: float, _end: float) -> void: pass
## Ripple editing (Reaper's ripple per track, Pro Tools' shuffle): an item moved, and every later
## unlocked item on its track moved by as much; an item trimmed, and every item after its old end
## moved by as far as the end did.
func ripple_move_item(_track_index: int, _item_index: int, _start: float) -> void: pass
func ripple_trim_item(_track_index: int, _item_index: int, _start: float, _end: float) -> void: pass
## An item's own level, in dB on top of its track's.
func set_item_gain(_track_index: int, _item_index: int, _db: float) -> void: pass
## An audio item stretched (kind PROCESS_STRETCH, `amount` the new length over the old) or
## pitch-shifted (PROCESS_PITCH, semitones) into a new file. One undo step. Only the engines that
## hold the sound do it; Reaper's bridge has no such edit here yet.
func process_item(_track_index: int, _item_index: int, _kind: int, _amount: float) -> void: pass
## An item's fade in and fade out, in seconds.
func set_item_fades(_track_index: int, _item_index: int, _fade_in: float, _fade_out: float) -> void: pass
## Two overlapping items of a track faded into each other over the overlap, the earlier out and
## the later in, both equal-power. One undo step; nothing when they do not overlap or either is
## locked.
func crossfade_items(_track_index: int, _first: int, _second: int) -> void: pass
## How an item's fade in and fade out run, each one of DawKitClip's FADE_ shapes. One undo step;
## none when it already is.
func set_item_fade_shape(_track_index: int, _item_index: int, _in_shape: int, _out_shape: int) -> void: pass
## Silence an item without removing it: it keeps its place and its edits, and plays again unmuted.
func set_item_muted(_track_index: int, _item_index: int, _muted: bool) -> void: pass
func set_item_locked(_track_index: int, _item_index: int, _locked: bool) -> void: pass
func set_item_lane(_track_index: int, _item_index: int, _lane: float) -> void: pass
func set_comp(_track_index: int, _from: float, _to: float, _lane: float) -> void: pass
func flatten_comp(_track_index: int) -> void: pass
## A MIDI item's lane of controller events: see DAW.set_item_controls. `flat` is [time, value] pairs.
func set_item_controls(_track_index: int, _item_index: int, _kind: int, _channel: int, _flat: Array) -> void: pass
## Freeze a track: its sound through its plugins, before its fader, written to a file, and its items
## and plugins swapped for that (MixState.TrackState.frozen). Takes as long as the song plays; a
## no-op without Capability.RENDER. `render_finished` says how it went.
func freeze_track(_track_index: int) -> void: pass
## Put a frozen track back as it was.
func thaw_track(_track_index: int) -> void: pass
## A new, empty track at `at` (from 1), everything from there on moving down one.
func add_track(_at: int, _track_name: String) -> void: pass
## A track gone, with its items and effects, and the sends that went to it. A folder's children
## move out a level.
func remove_track(_index: int) -> void: pass
## Track `index` moved, with whatever is in it when it is a folder, to be track `to` (from 1, in
## the order after the move), inside folder `parent` (a track's index now, 0 for none). Refused
## when the folder is not just before it or around it there, or is the track itself or in it.
## Without Capability.TRACK_ORDER a no-op. One undo step.
func move_track(_index: int, _to: int, _parent: int) -> void: pass
## A copy of a track right after it, as Reaper's duplicate makes one: under the same name, with
## its settings, effects and theirs, sends, items and automation; not armed, not selected. In a
## folder it stays in the folder. One undo step.
func duplicate_track(_index: int) -> void: pass
func rename_track(_index: int, _track_name: String) -> void: pass
func set_track_colour(_index: int, _colour: Color) -> void: pass
## A track into group `group` (1 and up), or out of any (0). One undo step.
func set_track_group(_index: int, _group: int) -> void: pass
## A group's VCA trim in decibels (-60 to +12): every track in it is that much louder or
## quieter, with no audio through the VCA. One undo step.
func set_vca(_group: int, _db: float) -> void: pass
func add_fx(_track_index: int, _plugin: String, _at: int) -> void: pass
func remove_fx(_track_index: int, _fx_index: int) -> void: pass
## A track's lane of automation for `target` (see MixState.TrackState.automation), whole; empty
## points take the lane away.
func set_automation(_track_index: int, _target: String, _points: Array) -> void: pass
## Write the song -- its loop range while it loops, else all of it -- to a WAV beside the project:
## the mix, and with `stems` each track's own, each with a tail after the range of up to
## RENDER_TAIL_SECONDS for effects to ring out. `render_finished` says when and where. A no-op
## without Capability.RENDER. `normalise`: the mix brought to a peak of RENDER_NORMALISE_DB, and
## every stem by the same gain, so the stems still add up to the mix (Reaper's "normalize stems to
## master").
func render(_stems: bool, _bits := 24, _normalise := false, _rate := 48000, _flac := false) -> void: pass
const RENDER_TAIL_SECONDS := 4.0
## A normalised render's peak, in dBFS: a decibel under full scale, room for a lossy encoder's
## overshoot.
const RENDER_NORMALISE_DB := -1.0
## The tempo's changes (see MixState.tempo_points), the first at beat 0 and setting the tempo;
## empty for one tempo throughout.
func set_tempo_map(_points: Array) -> void: pass
## Every note of a MIDI item moved `semitones` up (or down), each kept within 0-127.
func transpose_item(_track_index: int, _item_index: int, _semitones: int) -> void: pass
## Every note of a MIDI item harder (positive) or softer, kept between 1 and 127.
func shift_velocity(_track_index: int, _item_index: int, _by: int) -> void: pass
## Every note of a MIDI item nudged at random, up to `seconds` and `velocity`: see _locally_humanise.
func set_note_velocity(_track_index: int, _item_index: int, _note_index: int, _velocity: int) -> void: pass
func legato_item(_track_index: int, _item_index: int) -> void: pass
func staccato_item(_track_index: int, _item_index: int) -> void: pass
func even_velocity(_track_index: int, _item_index: int) -> void: pass
func move_note(_track_index: int, _item_index: int, _note_index: int, _by: float) -> void: pass
func place_note(_track_index: int, _item_index: int, _note_index: int, _by: float, _semitones: int) -> void: pass
func set_note_end(_track_index: int, _item_index: int, _note_index: int, _off: float) -> void: pass
func insert_note(_track_index: int, _item_index: int, _on: float, _off: float, _pitch: int) -> void: pass
func transpose_note(_track_index: int, _item_index: int, _note_index: int, _semitones: int) -> void: pass
func delete_note(_track_index: int, _item_index: int, _note_index: int) -> void: pass
func retrograde_item(_track_index: int, _item_index: int) -> void: pass
func rename_item(_track_index: int, _item_index: int, _item_name: String) -> void: pass
func humanise_item(_track_index: int, _item_index: int, _seconds: float, _velocity: int) -> void: pass
## An audio item played backwards, or forwards again (MixState.ItemState.reversed).
func set_item_reversed(_track_index: int, _item_index: int, _reversed: bool) -> void: pass
## Every note of a MIDI item pulled `strength` (0-1) of the way to the nearest `grid_beats` line
## of the song's beat grid, keeping its length.
func quantize_item(_track_index: int, _item_index: int, _grid_beats: float, _strength: float, _swing := 0.0) -> void: pass
## Quantise a MIDI item to the feel of another (see `groove_of`). Only the engines that edit
## notes themselves do it; Reaper's bridge has no such edit, so it leaves the notes as they are.
func groove_item(_track_index: int, _item_index: int, _from_track: int, _from_item: int, _grid_beats: float, _strength: float) -> void: pass
## A marker at `seconds`, called `marker_name`. An edit, so it is undoable where the DAW keeps
## history. A no-op on a backend that answers false to Capability.MARKERS.
func add_marker(_seconds: float, _marker_name: String) -> void: pass
func edit_marker(_at: float, _to: float, _marker_name: String) -> void: pass
func remove_marker(_at: float) -> void: pass
## A named span; and the one starting at `at` (to a millisecond) gone. As markers: no-ops on a
## backend that answers false to Capability.MARKERS.
func add_region(_start: float, _end: float, _region_name: String) -> void: pass
func remove_region(_at: float) -> void: pass
## The region starting at `at` (to a millisecond) moved, resized or renamed: from `start` to `end`,
## called `region_name`. One undo step; nothing when there is none there.
func edit_region(_at: float, _start: float, _end: float, _region_name: String) -> void: pass


## `regions` with one more, kept in order of starts. A second region at the same start replaces
## the first: two spans from one place is a mistake, not an arrangement.
static func regions_added(regions: Array, start: float, end: float, region_name: String) -> Array:
	var out: Array = regions.filter(func(r): return absf(float(r[0]) - start) >= 0.001)
	out.append([start, end, region_name])
	out.sort_custom(func(x, y): return x[0] < y[0])
	return out


static func regions_removed(regions: Array, at: float) -> Array:
	return regions.filter(func(r): return absf(float(r[0]) - at) >= 0.001)


## `regions` with the one at `at` made [start, end, region_name]; as they were with none there.
## Moved onto another's start, it replaces that one, as a new region there would.
static func regions_edited(regions: Array, at: float, start: float, end: float, region_name: String) -> Array:
	if regions_removed(regions, at).size() == regions.size():
		return regions
	return regions_added(regions_removed(regions, at), start, end, region_name)


## The key of the marker at `at` in `markers`, to a millisecond, or NAN for none.
static func marker_key(markers: Dictionary, at: float) -> float:
	for t in markers:
		if absf(float(t) - at) < 0.001:
			return float(t)
	return NAN


## `markers` with the one at `at` renamed and moved to `to`; or taken out, with `remove`.
static func markers_edited(markers: Dictionary, at: float, to: float, marker_name: String, remove := false) -> Dictionary:
	var out := markers.duplicate()
	var key := marker_key(markers, at)
	if is_nan(key):
		return out
	out.erase(key)
	if not remove:
		out[to] = marker_name
	return out

## A take of notes, placed by song position: a new MIDI item on `track_index` from `start` to
## `end` seconds, holding `notes` as [on, off, pitch, velocity, channel] rows in absolute
## seconds, and `controls` (the bend, the mod wheel, expression) flat [time, kind, value, channel]
## in absolute seconds. One undo step. Arguments arrive already cleaned (MidiTake.clean_args). A
## backend that cannot do it answers false to Capability.MIDI_TAKES.
func insert_midi_take(_track_index: int, _start: float, _end: float, _notes: Array,
		_name: String, _controls: Array = []) -> void: pass

## A recorded take: a new audio item on `track_index` at `start` seconds, `length` long, playing
## `source` -- a file name in AudioTake.DIR on this machine -- from its beginning. `peaks` is the
## file's overview, for drawing. One undo step. Only ever called on the host, by the host: a
## guest's audio arrives through Session, never as an intent, so no peer can name a file. A
## backend that cannot do it answers false to Capability.AUDIO_TAKES.
func insert_audio_take(_track_index: int, _start: float, _source: String, _length: float,
		_peaks: PackedByteArray, _name: String) -> void: pass

## A clip off a cassette (docs/spatial_loop.md part two, slice 24): a new item on `track_index` at
## `start` seconds, made from `packed` (MixWire.pack_item) as MixWire.unpack_item reads it -- the
## item it was cut from, notes, controls, file, fades, gain, loop and demo part, but for where it
## is. One undo step. Arguments arrive already checked (DAW.paste_refusal): a track that is there
## and not frozen, a file this machine has. A backend that cannot answers false to
## Capability.PASTE_ITEMS.
func paste_item(_track_index: int, _start: float, _packed: Dictionary) -> void: pass

## The song's sections laid end to end in a new order (docs/spatial_loop.md part two, slice 29):
## `order` is MixState.regions (in song order) by their indices there, in the order they are to
## play, already checked (DAW.arrange_refusal). Everything from the first region's start to the
## last's end moves with the section it is in (arrange_pieces): items, split where a section's
## edge crosses them; markers, so a section's harmony and notes go with it; the regions; every lane
## of automation; and each comp. A gap between regions is a piece of its own and keeps its place.
## A tempo or signature change at a piece's start moves with it. What is after the last region does
## not move. One undo step. A backend that cannot answers false to Capability.ARRANGE.
func arrange_sections(_order: Array) -> void: pass

## The song's lyrics made `text`, LRC (Lyrics), already cleaned (Lyrics.clean): MixState.lyrics, the
## whole text at once, so a TAP's one new time and a pasted verse are the same write. One undo step.
## A backend that cannot answers false to Capability.LYRICS.
func set_lyrics(_text: String) -> void: pass


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


func _write_comp(track_index: int, comp: Array) -> void:
	var packed := MixWire.pack_comp(comp)
	record_for_replication("/track/%d/comp" % track_index, packed)
	MixWire.apply(state, "/track/%d/comp" % track_index, packed)


## Lane `kind` on `channel` of the item made `flat`'s [time, value] pairs, the events inside the item
## and at most MixWire.CONTROLS_MAX in all. False when nothing changed, or the item is not MIDI.
func _locally_set_controls(track_index: int, item_index: int, kind: int, channel: int, flat: Array) -> bool:
	var it := state.item(track_index, item_index)
	if it == null or it.source != "" or kind < 0 or kind > DawKitClip.AFTERTOUCH:
		return false
	var c := DawKitClip.new()
	c.controls = it.controls.duplicate()
	var points: Array = []
	for i in range(0, flat.size() - 1, 2):
		if float(flat[i]) >= 0.0 and float(flat[i]) <= it.length:
			points.append([float(flat[i]), float(flat[i + 1])])
	c.set_control_lane(kind, points, clampi(channel, 0, 15))
	if c.controls == it.controls or c.control_count() > MixWire.CONTROLS_MAX:
		return false
	var items := _lane_copy(track_index)
	items[item_index].controls = c.controls
	_write_lane(track_index, items)
	return true


func _locally_set_lane(track_index: int, item_index: int, lane: int) -> bool:
	var it := state.item(track_index, item_index)
	lane = clampi(lane, 0, MixWire.LANES_MAX)
	if it == null or it.lane == lane:
		return false
	var items := _lane_copy(track_index)
	items[item_index].lane = lane
	_write_lane(track_index, items)
	return true


## `lane` sounds from `from` to `to` on the track (DawKitTrack.set_comp's rule, on the desk's
## own copy of the comp). False when nothing changed.
func _locally_set_comp(track_index: int, from: float, to: float, lane: int) -> bool:
	if state.tracks.get(track_index) == null or to <= from:
		return false
	var t := DawKitTrack.new()
	for it in state.track(track_index).items:
		var c := DawKitClip.new()
		c.start = it.start
		c.length = it.length
		t.clips.append(c)
	t.comp = state.track(track_index).comp.map(func(s): return s.duplicate())
	t.set_comp(maxf(from, 0.0), to, clampi(lane, 0, MixWire.LANES_MAX))
	if t.comp == state.track(track_index).comp:
		return false
	_write_comp(track_index, t.comp)
	return true


## Freeze the track to `rendered`, an item of its sound played through its plugins: what the track
## held is kept (MixState.TrackState.frozen), its items become that one item, its comp goes and its
## plugins are bypassed, since they are in the sound now. False if it is already frozen or unknown.
func _locally_freeze(track_index: int, rendered: MixState.ItemState) -> bool:
	var t: MixState.TrackState = state.tracks.get(track_index)
	if t == null or t.is_frozen():
		return false
	var on := {}
	for fx_index in t.plugins():
		on[fx_index] = t.fx[fx_index].enabled
	t.frozen = {"items": MixWire._pack_items(t.items), "comp": MixWire.pack_comp(t.comp), "fx_on": on}
	record_for_replication("/track/%d/frozen" % track_index, [1.0])
	_write_comp(track_index, [])
	_write_lane(track_index, [rendered])
	for fx_index in on:
		_write_fx_enabled(track_index, fx_index, false)
	return true


## The track put back as it was before `_locally_freeze`: the rendered item goes, its items and comp
## return and its plugins run as they did. False if it was not frozen.
func _locally_thaw(track_index: int) -> bool:
	var t: MixState.TrackState = state.tracks.get(track_index)
	if t == null or not t.is_frozen():
		return false
	var was := t.frozen
	t.frozen = {}
	record_for_replication("/track/%d/frozen" % track_index, [0.0])
	_write_lane(track_index, MixWire._unpack_items(was["items"]))
	_write_comp(track_index, MixWire.unpack_comp(was["comp"]))
	for fx_index in was["fx_on"]:
		_write_fx_enabled(track_index, fx_index, was["fx_on"][fx_index])
	return true


func _write_fx_enabled(track_index: int, fx_index: int, enabled: bool) -> void:
	var f := state.fx(track_index, fx_index, false)
	if f == null:
		return
	f.enabled = enabled
	state.fx_changed.emit(track_index, fx_index)
	record_for_replication("/track/%d/fx/%d/bypass" % [track_index, fx_index], [1.0 if enabled else 0.0])


## `item` cut to [from, to) (song seconds, inside it) as an item of its own, sounding as it did there:
## the file offset moved on by what was cut off the front, the notes trimmed to the window and counted
## from the new start, a fade kept only on an end that is still the item's own. On the first lane.
static func item_slice(item: MixState.ItemState, from: float, to: float) -> MixState.ItemState:
	var c: MixState.ItemState = MixWire._unpack_items(MixWire._pack_items([item]))[0]
	c.selected = false
	c.lane = 0
	c.start = from
	c.length = to - from
	c.source_offset = item.source_offset + (from - item.start)
	if from > item.start:
		c.fade_in = 0.0
	if to < item.end():
		c.fade_out = 0.0
	c.fade_in = minf(c.fade_in, c.length)
	c.fade_out = minf(c.fade_out, c.length)
	if not item.notes.is_empty():
		var kept := PackedFloat32Array()
		var shift := from - item.start
		for i in range(0, item.notes.size() - 4, 5):
			var on := item.notes[i] - shift
			var off := item.notes[i + 1] - shift
			if off <= 0.0 or on >= c.length:
				continue
			kept.append_array(PackedFloat32Array([maxf(on, 0.0), minf(off, c.length), item.notes[i + 2], item.notes[i + 3], item.notes[i + 4]]))
		c.notes = kept
	c.controls = MidiTake.controls_between(item.controls, item.start, from, to, from)
	return c


## The track's comp made plain: each item cut to the stretches that name its lane, all on the first
## lane, and no comp. False when there was none.
func _locally_flatten_comp(track_index: int) -> bool:
	var t: MixState.TrackState = state.tracks.get(track_index)
	if t == null or t.comp.is_empty():
		return false
	var out: Array = []
	for item in t.items:
		for s in t.comp:
			if s[2] != item.lane:
				continue
			var from := maxf(item.start, s[0])
			var to := minf(item.end(), s[1])
			if to - from > MIN_ITEM_SECONDS:
				out.append(item_slice(item, from, to))
	_write_lane(track_index, out)
	_write_comp(track_index, [])
	return true


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


func _locally_select_all() -> void:
	for index in state.track_indices():
		if state.track(index).items.all(func(it): return it.selected):
			continue
		var lane := _lane_copy(index)
		for item in lane:
			item.selected = true
		_write_lane(index, lane)


## One track's items all selected and every other track's cleared.
func _locally_select_track(track_index: int) -> void:
	if not state.tracks.has(track_index):
		return
	for index in state.track_indices():
		var want: bool = index == track_index
		if state.track(index).items.all(func(it): return it.selected == want):
			continue
		var lane := _lane_copy(index)
		for item in lane:
			item.selected = want
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


func _locally_move(track_index: int, item_index: int, start: float, to_track := 0) -> void:
	if state.item(track_index, item_index) == null:
		return
	var lane := _lane_copy(track_index)
	if to_track <= 0 or to_track == track_index or state.track(to_track, false) == null:
		lane[item_index].start = maxf(start, 0.0)
		_write_lane(track_index, lane)
		return
	var moving: MixState.ItemState = lane[item_index]
	lane.remove_at(item_index)
	moving.start = maxf(start, 0.0)
	var into := _lane_copy(to_track)
	into.append(moving)
	_write_lane(track_index, lane)
	_write_lane(to_track, into)


## Returns how many items were cut.
func _locally_split(seconds: float) -> int:
	var cut := 0
	for index in state.track_indices():
		var hit := false
		for item in state.track(index).items:
			hit = hit or (item.selected and not item.locked and item.contains(seconds))
		if not hit:
			continue
		var lane := _lane_copy(index)
		var added: Array = []
		for item in lane:
			# A locked item is not cut, selected or not.
			if item.selected and not item.locked and item.contains(seconds):
				var right := MixState.ItemState.new()
				right.start = seconds
				right.length = item.end() - seconds
				right.name = item.name
				right.muted = item.muted
				right.selected = true
				right.source = item.source
				right.peaks = item.peaks
				right.reversed = item.reversed
				right.part = item.part
				right.source_offset = item.source_offset + (seconds - item.start)
				# Each half keeps the end it had: the fade in stays on the left, the fade out goes
				# with the right, and both keep the clip's gain.
				right.gain_db = item.gain_db
				right.loop_start = item.loop_start
				right.loop_end = item.loop_end
				right.fade_out = minf(item.fade_out, right.length)
				right.fade_shape = item.fade_shape
				right.fade_out_shape = item.fade_out_shape
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
	if not left.controls.is_empty():
		var whole := left.controls
		left.controls = MidiTake.controls_between(whole, left.start, left.start, seconds, left.start)
		right.controls = MidiTake.controls_between(whole, left.start, seconds, INF, seconds)
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


## The selected, unlocked items of each track that glue into one, by track: two or more that
## are all MIDI, or all cuts of one file that follow on from each other in it and on the track,
## as a split leaves them; none looped or reversed, all at one gain. Gluing audio that is not one
## file played straight through would need a bounce to a new file, which the built-in engine
## does not do.
static func glue_picks(s: MixState) -> Dictionary:
	var out := {}
	for index in s.track_indices():
		var picked: Array = s.track(index).items.filter(func(it): return it.selected and not it.locked)
		if picked.size() < 2:
			continue
		picked.sort_custom(func(a, b): return a.start < b.start)
		if gluable(picked):
			out[index] = picked
	return out


## `items`, sorted by start, can be one item. See glue_picks.
static func gluable(items: Array) -> bool:
	var first: MixState.ItemState = items[0]
	var midi := first.source.is_empty()
	for k in items.size():
		var it: MixState.ItemState = items[k]
		if it.is_looped() or it.reversed or not is_equal_approx(it.gain_db, first.gain_db) \
				or it.source.is_empty() != midi:
			return false
		if midi or k == 0:
			continue
		var before: MixState.ItemState = items[k - 1]
		if it.source != first.source or absf(it.start - before.end()) > 0.0005 \
				or absf(it.source_offset - (before.source_offset + before.length)) > 0.0005:
			return false
	return true


## Returns how many tracks had items glued. The glued item is the first one, run to where the
## last ends, its fade-out the last one's, selected. A MIDI item keeps the notes each part
## played -- a note cut short at a part's end stays cut there -- and the gaps between parts stay
## silent.
func _locally_glue_selected() -> int:
	var picks := glue_picks(state)
	for index in picks:
		var lane := _lane_copy(index)
		var parts: Array = lane.filter(func(it): return it.selected and not it.locked)
		parts.sort_custom(func(a, b): return a.start < b.start)
		var glued: MixState.ItemState = parts[0]
		var end := 0.0
		var last: MixState.ItemState = parts[0]
		for it in parts:
			if it.end() >= end:
				end = it.end()
				last = it
		if glued.source.is_empty():
			var notes: Array = []
			for it in parts:
				for n in MidiTake.unpack_relative(it.notes, it.start):
					if n[0] >= it.start - 0.000001 and n[0] < it.end():
						n[1] = minf(n[1], it.end())
						notes.append(n)
			notes.sort_custom(func(a, b): return a[0] < b[0])
			glued.notes = MidiTake.pack_relative(notes, glued.start)
			var events := PackedFloat64Array()
			for it in parts:
				events.append_array(MidiTake.controls_between(it.controls, it.start, it.start, it.end(), glued.start))
			glued.controls = DawKitClip.clean_controls(Array(events))
		glued.length = end - glued.start
		glued.fade_out = last.fade_out
		glued.fade_out_shape = last.fade_out_shape
		glued.muted = parts.all(func(it): return it.muted)
		var kept := lane.filter(func(it): return it == glued or not (it.selected and not it.locked))
		_write_lane(index, kept)
	return picks.size()


## Returns how many were deleted.
func _locally_delete_selected() -> int:
	var gone := 0
	for index in state.track_indices():
		if not state.track(index).items.any(func(it): return it.selected and not it.locked):
			continue
		var lane := _lane_copy(index)
		# A locked item stays, selected or not.
		var kept := lane.filter(func(it): return not it.selected or it.locked)
		gone += lane.size() - kept.size()
		_write_lane(index, kept)
	return gone


## Returns how many were deleted. Each later item on a track moves back by the length of every
## deleted item that started before it, so a gap closes and nothing after it changes its order. A
## locked item is neither deleted nor moved.
func _locally_ripple_delete_selected() -> int:
	var gone := 0
	for index in state.track_indices():
		if not state.track(index).items.any(func(it): return it.selected and not it.locked):
			continue
		var lane := _lane_copy(index)
		var cut := lane.filter(func(it): return it.selected and not it.locked)
		var kept := lane.filter(func(it): return not it.selected or it.locked)
		for item in kept:
			if item.locked:
				continue
			var back := 0.0
			for c in cut:
				if c.start < item.start:
					back += minf(c.length, item.start - c.start)
			item.start = maxf(item.start - back, 0.0)
		gone += cut.size()
		_write_lane(index, kept)
	return gone


## The items on a track that a ripple from `from` seconds carries: unlocked, not the one edited,
## starting at or after it.
func _ripple_followers(track_index: int, item_index: int, from: float) -> Array:
	var out: Array = []
	var items: Array = state.track(track_index).items
	for j in items.size():
		if j != item_index and not items[j].locked and items[j].start >= from - 0.000001:
			out.append(j)
	return out


## Every one of `indices` on the track moved by `delta` seconds, none before the song's start.
func _ripple_shift(track_index: int, indices: Array, delta: float) -> void:
	if indices.is_empty() or is_zero_approx(delta):
		return
	var lane := _lane_copy(track_index)
	for j in indices:
		lane[j].start = maxf(lane[j].start + delta, 0.0)
	_write_lane(track_index, lane)


## False when there is no such item or it does not move.
func _locally_ripple_move(track_index: int, item_index: int, start: float) -> bool:
	var it := state.item(track_index, item_index)
	if it == null or is_equal_approx(maxf(start, 0.0), it.start):
		return false
	var delta := maxf(start, 0.0) - it.start
	var later := _ripple_followers(track_index, item_index, it.start)
	_locally_move(track_index, item_index, start)
	_ripple_shift(track_index, later, delta)
	return true


## False when there is no such item or the trim is refused or changes nothing.
func _locally_ripple_trim(track_index: int, item_index: int, start: float, end: float) -> bool:
	var it := state.item(track_index, item_index)
	if it == null:
		return false
	var was_start := it.start
	var was_end := it.end()
	var later := _ripple_followers(track_index, item_index, was_end)
	_locally_trim(track_index, item_index, start, end)
	var now := state.item(track_index, item_index)
	if is_equal_approx(now.start, was_start) and is_equal_approx(now.end(), was_end):
		return false
	_ripple_shift(track_index, later, now.end() - was_end)
	return true


## Where an item starting at `start` lands nudged by `amount` of `unit`.
func nudged(start: float, amount: float, unit: int) -> float:
	match unit:
		NUDGE_BEATS:
			return maxf(state.seconds_at_beat(state.beat_at(start) + amount), 0.0)
		NUDGE_BARS:
			return maxf(state.bar_to_seconds(state.bar_at(start) + 1.0 + amount), 0.0)
	return maxf(start + amount, 0.0)


## [track, start before, start after] for every item a nudge moves.
func _locally_nudge(amount: float, unit: int) -> Array:
	var moved: Array = []
	for index in state.track_indices():
		if not state.track(index).items.any(func(it): return it.selected and not it.locked):
			continue
		var lane := _lane_copy(index)
		var any := false
		for it in lane:
			if not it.selected or it.locked:
				continue
			var to := nudged(it.start, amount, unit)
			if absf(to - it.start) > 0.000001:
				moved.append([index, it.start, to])
				it.start = to
				any = true
		if any:
			_write_lane(index, lane)
	return moved


## Returns how many were copied.
func _locally_duplicate_selected() -> int:
	var made := 0
	for index in state.track_indices():
		if not state.track(index).items.any(func(it): return it.selected):
			continue
		var lane := _lane_copy(index)
		var copies: Array = []
		for item in lane:
			if not item.selected:
				continue
			var copy: MixState.ItemState = MixWire._unpack_items(MixWire._pack_items([item]))[0]
			copy.start = item.end()
			# A looped part goes on round; a file goes on from where the copy's start is in it
			# only when it loops, so a plain take repeats rather than running on past its end.
			if item.is_looped():
				copy.source_offset = item.source_offset + item.length
			item.selected = false
			copies.append(copy)
		lane.append_array(copies)
		made += copies.size()
		_write_lane(index, lane)
	return made


func _locally_copy_selected_to(seconds: float) -> int:
	var earliest := INF
	for index in state.track_indices():
		for it in state.track(index).items:
			if it.selected:
				earliest = minf(earliest, it.start)
	if earliest == INF:
		return 0
	var made := 0
	for index in state.track_indices():
		if not state.track(index).items.any(func(it): return it.selected):
			continue
		var lane := _lane_copy(index)
		var copies: Array = []
		for item in lane:
			if not item.selected:
				continue
			var copy: MixState.ItemState = MixWire._unpack_items(MixWire._pack_items([item]))[0]
			copy.start = maxf(seconds, 0.0) + item.start - earliest
			copy.selected = false
			copies.append(copy)
		lane.append_array(copies)
		made += copies.size()
		_write_lane(index, lane)
	return made


## The edges an item can have: no further left than its file starts (or the song does), and a
## real length.
func _locally_trim(track_index: int, item_index: int, start: float, end: float) -> void:
	var item := state.item(track_index, item_index)
	if item == null:
		return
	var earliest := 0.0
	if not item.source.is_empty() and not item.is_looped():
		earliest = maxf(item.start - item.source_offset, 0.0)
	start = maxf(start, earliest)
	if end - start < MIN_ITEM_SECONDS:
		return
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	var moved := start - it.start
	if not it.notes.is_empty():
		var kept: Array = []
		for n in MidiTake.unpack_relative(it.notes, it.start):
			if n[0] >= start and n[0] < end:
				n[1] = minf(n[1], end)
				kept.append(n)
		it.notes = MidiTake.pack_relative(kept, start)
	if not it.controls.is_empty():
		it.controls = MidiTake.controls_between(it.controls, it.start, start, end, start)
	it.source_offset += moved
	it.start = start
	it.length = end - start
	it.fade_in = minf(it.fade_in, it.length)
	it.fade_out = minf(it.fade_out, it.length - it.fade_in)
	_write_lane(track_index, lane)


## How long an item's file is, in seconds: from its overview here, to a fiftieth of a second; a
## backend that has the sound itself says exactly.
func source_seconds(item: MixState.ItemState) -> float:
	return float(item.peaks.size()) / float(AudioTake.PEAKS_PER_SECOND)


## False when there is no such item, it already is as asked, or it cannot be: a MIDI item (it has
## no sound to turn round) or a looped one (its loop is in the file's forward time). The offset
## turns round with the sound -- what was the item's right edge in the file is its left -- and the
## overview with it.
## Where an item's sound is on this machine; the engines that keep project media say more.
func media_path(source: String) -> String:
	return ProjectSettings.globalize_path(AudioTake.DIR.path_join(source.get_file()))


## Item sound processing kinds, for `process_item`.
const PROCESS_STRETCH := 0
const PROCESS_PITCH := 1
## The longest sound processed at once: WSOLA in script takes seconds for each ten.
const PROCESS_MAX_SECONDS := 60.0
const STRETCH_MIN := DawKitStretch.MIN_RATIO
const STRETCH_MAX := DawKitStretch.MAX_RATIO
const PITCH_SHIFT_MAX := 24.0


## An audio item's sound made longer or shorter (`amount` is the new length over the old, the pitch
## kept) or higher or lower (`amount` in semitones, the length kept), as a new file beside the
## takes; the item then plays that file. Nothing for a MIDI, reversed or looped item, one with no
## file on this machine, or one too long to process at once. The old file stays, other items use it.
func _locally_process(track_index: int, item_index: int, kind: int, amount: float) -> bool:
	var it := state.item(track_index, item_index)
	if it == null or it.source.is_empty() or it.reversed or it.is_looped() or not is_finite(amount):
		return false
	var path := media_path(it.source)
	if not FileAccess.file_exists(path):
		return false
	var file := DawKitAudioFile.read(path)
	if not str(file.get("error", "")).is_empty() or file.get("samples") == null:
		return false
	var channels := int(file["channels"])
	var rate := int(file["rate"])
	var samples: PackedFloat32Array = file["samples"]
	if float(samples.size()) / maxi(channels, 1) / maxi(rate, 1) > PROCESS_MAX_SECONDS:
		return false
	var ratio := 1.0
	var made: PackedFloat32Array
	if kind == PROCESS_STRETCH:
		ratio = clampf(amount, STRETCH_MIN, STRETCH_MAX)
		made = DawKitStretch.stretch(samples, channels, rate, ratio)
	elif kind == PROCESS_PITCH:
		amount = clampf(amount, -PITCH_SHIFT_MAX, PITCH_SHIFT_MAX)
		if is_zero_approx(amount):
			return false
		made = DawKitStretch.pitch_shift(samples, channels, rate, amount)
	else:
		return false
	DirAccess.make_dir_recursive_absolute(AudioTake.DIR)
	var name := "%s_%s%d.wav" % [it.source.get_file().get_basename().left(40), "s" if kind == PROCESS_STRETCH else "p",
			Time.get_ticks_msec()]
	var made_path := ProjectSettings.globalize_path(AudioTake.DIR.path_join(name))
	if DawKitAudioFile.write_wav(made_path, made, channels, rate, 32) != OK:
		return false
	var peaks := DawKitAudioFile.peaks(made, channels, rate)
	take_peaks[name] = peaks
	var lane := _lane_copy(track_index)
	var item: MixState.ItemState = lane[item_index]
	item.source = name
	item.peaks = peaks
	item.source_offset *= ratio
	item.length *= ratio
	_write_lane(track_index, lane)
	return true


func _locally_reverse(track_index: int, item_index: int, reversed: bool) -> bool:
	var it := state.item(track_index, item_index)
	if it == null or it.reversed == reversed or it.source.is_empty() or it.is_looped():
		return false
	var lane := _lane_copy(track_index)
	var item: MixState.ItemState = lane[item_index]
	item.source_offset = maxf(source_seconds(it) - it.source_offset - it.length, 0.0)
	var flipped := item.peaks.duplicate()
	flipped.reverse()
	item.peaks = flipped
	item.reversed = reversed
	_write_lane(track_index, lane)
	return true


## False when there is no such item or it already is as asked.
## [earlier, later, overlap] of a crossfade between two items, or [] when there is none to make.
func crossfade_of(track_index: int, first: int, second: int) -> Array:
	var a := state.item(track_index, first)
	var b := state.item(track_index, second)
	if a == null or b == null or first == second or a.locked or b.locked:
		return []
	if b.start < a.start:
		var swap := first
		first = second
		second = swap
		a = state.item(track_index, first)
		b = state.item(track_index, second)
	var overlap := minf(a.end(), b.end()) - b.start
	return [first, second, overlap] if overlap >= MIN_ITEM_SECONDS else []


## False when there is no crossfade to make.
func _locally_crossfade(track_index: int, first: int, second: int) -> bool:
	var x := crossfade_of(track_index, first, second)
	if x.is_empty():
		return false
	var lane := _lane_copy(track_index)
	var a: MixState.ItemState = lane[x[0]]
	var b: MixState.ItemState = lane[x[1]]
	a.fade_out = minf(x[2], a.length - a.fade_in)
	b.fade_in = x[2]
	b.fade_out = minf(b.fade_out, b.length - b.fade_in)
	# Only the two ends that cross: each item's other end keeps its own shape.
	a.fade_out_shape = DawKitClip.FADE_EQUAL_POWER
	b.fade_shape = DawKitClip.FADE_EQUAL_POWER
	_write_lane(track_index, lane)
	return true


## False when there is no such item or it already is as asked.
func _locally_fade_shape(track_index: int, item_index: int, in_shape: int, out_shape: int) -> bool:
	var it := state.item(track_index, item_index)
	if it == null or (it.fade_shape == in_shape and it.fade_out_shape == out_shape):
		return false
	var lane := _lane_copy(track_index)
	lane[item_index].fade_shape = in_shape
	lane[item_index].fade_out_shape = out_shape
	_write_lane(track_index, lane)
	return true


## False when there is no such item, the name is empty, or it already has it.
func _locally_rename_item(track_index: int, item_index: int, item_name: String) -> bool:
	var it := state.item(track_index, item_index)
	if it == null or item_name == "" or it.name == item_name:
		return false
	var lane := _lane_copy(track_index)
	lane[item_index].name = item_name
	_write_lane(track_index, lane)
	return true


func _locally_lock(track_index: int, item_index: int, locked: bool) -> bool:
	var it := state.item(track_index, item_index)
	if it == null or it.locked == locked:
		return false
	var lane := _lane_copy(track_index)
	lane[item_index].locked = locked
	_write_lane(track_index, lane)
	return true


## False when there is no such item or it already is as asked.
func _locally_mute(track_index: int, item_index: int, muted: bool) -> bool:
	var it := state.item(track_index, item_index)
	if it == null or it.muted == muted:
		return false
	var lane := _lane_copy(track_index)
	lane[item_index].muted = muted
	_write_lane(track_index, lane)
	return true


## NAN leaves that part of the item as it is.
func _locally_shape(track_index: int, item_index: int, gain_db: float, fade_in: float, fade_out: float) -> void:
	if state.item(track_index, item_index) == null:
		return
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	if not is_nan(gain_db):
		it.gain_db = clampf(gain_db, ITEM_GAIN_MIN, ITEM_GAIN_MAX)
	if not is_nan(fade_in):
		it.fade_in = clampf(fade_in, 0.0, it.length)
	if not is_nan(fade_out):
		it.fade_out = clampf(fade_out, 0.0, it.length - it.fade_in)
	_write_lane(track_index, lane)


## The tracks put in a new order: `order[n]` is the old index of new track n + 1, or 0 for a new,
## empty one. Sends follow their destinations and go with a removed one; a removed track's folder
## shape passes to its neighbours, so its children move out a level and the track before a removed
## last child closes the folder instead. Answers old index -> new index.
func _locally_renumber(order: Array) -> Dictionary:
	var olds := state.track_indices()
	var map := {}
	for n in order.size():
		if int(order[n]) > 0:
			map[int(order[n])] = n + 1
	var depth := {}
	for i in olds:
		depth[i] = state.tracks[i].folder_depth
	for pos in olds.size():
		var gone: int = olds[pos]
		var d: int = depth[gone]
		if map.has(gone) or d == 0:
			continue
		if d < 0:
			for back in range(pos - 1, -1, -1):
				if map.has(olds[back]):
					depth[olds[back]] += d
					break
		else:
			var level := d
			for later in range(pos + 1, olds.size()):
				level += depth[olds[later]]
				if level <= 0:
					depth[olds[later]] += d
					break
	var tracks := {}
	for n in order.size():
		if int(order[n]) > 0:
			# A send's automation names its destination by number, which follows it too.
			var lanes: Dictionary = state.tracks[int(order[n])].automation
			for target in lanes.keys():
				if String(target).begins_with("send:"):
					var to := int(String(target).substr(5))
					var points: Array = lanes[target]
					lanes.erase(target)
					if map.has(to):
						lanes["send:%d" % map[to]] = points
	for n in order.size():
		var t: MixState.TrackState
		if int(order[n]) > 0:
			t = state.tracks[int(order[n])]
			t.folder_depth = depth[int(order[n])]
		else:
			t = MixState.TrackState.new()
		t.index = n + 1
		tracks[n + 1] = t
	for t in tracks.values():
		var slots: Array = t.sends.keys()
		slots.sort()
		var kept := {}
		for slot in slots:
			var sd: MixState.SendState = t.sends[slot]
			if sd.dest_track > 0:
				if not map.has(sd.dest_track):
					continue
				sd.dest_track = map[sd.dest_track]
			sd.index = kept.size() + 1
			kept[sd.index] = sd
		t.sends = kept
	state.tracks = tracks
	state.project_track_count = order.size()
	return map


## Old index -> new index for an `order` as `_locally_renumber` takes it.
static func _map_of(order: Array) -> Dictionary:
	var map := {}
	for n in order.size():
		if int(order[n]) > 0:
			map[int(order[n])] = n + 1
	return map


## `order` for a track added at `at`, or removed from `index`, when there are `count`.
## Track `from`'s settings, effects, sends, items and automation written onto `to`, an empty track
## just after it (see duplicate_track): through the snapshot, so the copy is whatever a guest
## would read of the original. A folder's end moves to the copy, so the copy stays inside it.
func _locally_copy_track(from: int, to: int) -> void:
	var prefix := "/track/%d/" % from
	for entry in MixWire.snapshot(state):
		var address: String = entry[0]
		if address.begins_with(prefix):
			MixWire.apply(state, "/track/%d/%s" % [to, address.substr(prefix.length())], entry[1])
	var original := state.track(from)
	var copy := state.track(to)
	copy.part = original.part
	copy.rec_arm = false
	copy.selected = false
	for it in copy.items:
		it.selected = false
	if original.folder_depth < 0:
		copy.folder_depth = original.folder_depth
		original.folder_depth = 0
	else:
		copy.folder_depth = 0


## How `move_track(index, to, parent)` changes a project whose tracks have these folder depths
## (Reaper's deltas, track 1 first): {"order": the old indices in their new order (for
## `_locally_renumber`), "depths": the folder depth of each, new order}. Empty when it cannot be.
static func move_plan(depths: Array, index: int, to: int, parent: int) -> Dictionary:
	var count := depths.size()
	if index < 1 or index > count or parent < 0 or parent > count or parent == index:
		return {}
	# Each track's folder, from the running depth.
	var parents := {}
	var open: Array[int] = []
	for i in range(1, count + 1):
		parents[i] = open.back() if not open.is_empty() else 0
		var d: int = depths[i - 1]
		if d > 0:
			for _k in d:
				open.append(i)
		else:
			for _k in -d:
				if not open.is_empty():
					open.pop_back()
	# The track and everything inside it go together.
	var block: Array[int] = [index]
	for i in range(index + 1, count + 1):
		if block.has(parents[i]):
			block.append(i)
		else:
			break
	if block.has(parent):
		return {}
	var order: Array = []
	for i in range(1, count + 1):
		if not block.has(i):
			order.append(i)
	var at := clampi(to - 1, 0, order.size())
	for k in block.size():
		order.insert(at + k, block[k])
	parents[index] = parent
	# Each track's folder has to be open where it is: the last track before it, or one that
	# track is in.
	var stack: Array = []
	var levels: Array[int] = []
	for i in order:
		var p: int = parents[i]
		while not stack.is_empty() and stack.back() != p:
			stack.pop_back()
		if p != 0 and stack.is_empty():
			return {}
		levels.append(stack.size())
		stack.append(i)
	var out_depths: Array[int] = []
	for n in order.size():
		var next := levels[n + 1] if n + 1 < order.size() else 0
		out_depths.append(next - levels[n])
	return {"order": order, "depths": out_depths}


static func _order_adding(count: int, at: int) -> Array:
	var order := range(1, count + 1)
	order.insert(clampi(at, 1, count + 1) - 1, 0)
	return order


static func _order_removing(count: int, index: int) -> Array:
	var order := range(1, count + 1)
	order.erase(index)
	return order


## False when the item has no notes to change.
func _locally_transpose(track_index: int, item_index: int, semitones: int) -> bool:
	var item := state.item(track_index, item_index)
	if item == null or item.notes.is_empty() or semitones == 0:
		return false
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	var notes := it.notes.duplicate()
	for n in range(0, notes.size() - 4, 5):
		notes[n + 2] = clampi(int(notes[n + 2]) + semitones, 0, 127)
	it.notes = notes
	_write_lane(track_index, lane)
	return true


func _locally_shift_velocity(track_index: int, item_index: int, by: int) -> bool:
	var item := state.item(track_index, item_index)
	if item == null or item.notes.is_empty() or by == 0:
		return false
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	var notes := it.notes.duplicate()
	for n in range(0, notes.size() - 4, 5):
		notes[n + 3] = clampi(int(notes[n + 3]) + by, 1, 127)
	it.notes = notes
	_write_lane(track_index, lane)
	return true


## Every note of a MIDI item made to end where the next one begins -- the next later start, of
## any pitch, so a chord's notes all run to the same place and the last note keeps its length.
## Overlapping notes are cut back as well as short ones lengthened. False when nothing changes.
func _locally_legato(track_index: int, item_index: int) -> bool:
	var item := state.item(track_index, item_index)
	if item == null or item.notes.is_empty():
		return false
	var notes := item.notes.duplicate()
	var changed := false
	var width := MidiTake.NOTE_WIDTH
	for n in range(0, notes.size() - width + 1, width):
		var next := INF
		for m in range(0, notes.size() - width + 1, width):
			var on: float = notes[m]
			if on > notes[n] + MidiTake.MIN_NOTE and on < next:
				next = on
		if next < INF and not is_equal_approx(notes[n + 1], next):
			notes[n + 1] = next
			changed = true
	if not changed:
		return false
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	it.notes = notes
	_write_lane(track_index, lane)
	return true


## Every note of a MIDI item cut to half its length, never below the shortest a note may be.
## False when nothing changes.
func _locally_staccato(track_index: int, item_index: int) -> bool:
	var item := state.item(track_index, item_index)
	if item == null or item.notes.is_empty():
		return false
	var notes := item.notes.duplicate()
	var changed := false
	for n in range(0, notes.size() - MidiTake.NOTE_WIDTH + 1, MidiTake.NOTE_WIDTH):
		var length: float = notes[n + 1] - notes[n]
		var short := maxf(length * 0.5, MidiTake.MIN_NOTE)
		if short < length - 0.0001:
			notes[n + 1] = notes[n] + short
			changed = true
	if not changed:
		return false
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	it.notes = notes
	_write_lane(track_index, lane)
	return true


## A MIDI item's notes mirrored in time about the middle of the item: each ends as far from the
## item's end as it began from its start. Notes are kept inside the item. False when there are none.
func _locally_retrograde(track_index: int, item_index: int) -> bool:
	var item := state.item(track_index, item_index)
	if item == null or item.notes.is_empty():
		return false
	var notes := item.notes.duplicate()
	var width := MidiTake.NOTE_WIDTH
	var span := item.length
	for n in range(0, notes.size() - width + 1, width):
		var on := clampf(span - float(notes[n + 1]), 0.0, span)
		var off := clampf(span - float(notes[n]), 0.0, span)
		notes[n] = on
		notes[n + 1] = maxf(off, on + MidiTake.MIN_NOTE)
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	it.notes = notes
	_write_lane(track_index, lane)
	return true


## Every note of a MIDI item given the rounded average of their velocities. False when they
## already agree.
func _locally_even_velocity(track_index: int, item_index: int) -> bool:
	var item := state.item(track_index, item_index)
	if item == null or item.notes.is_empty():
		return false
	var notes := item.notes.duplicate()
	var width := MidiTake.NOTE_WIDTH
	var total := 0.0
	var count := 0
	for n in range(0, notes.size() - width + 1, width):
		total += float(notes[n + 3])
		count += 1
	var mean := clampi(roundi(total / count), 1, 127)
	var changed := false
	for n in range(0, notes.size() - width + 1, width):
		if int(notes[n + 3]) != mean:
			notes[n + 3] = mean
			changed = true
	if not changed:
		return false
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	it.notes = notes
	_write_lane(track_index, lane)
	return true


## The furthest one edit moves a note, in seconds.
const NOTE_MOVE_MAX := 60.0

## One note moved `by` seconds, its length kept, held inside its item (so one pressed against an
## end stops there). False when there is no such note or it does not move.
func _locally_move_note(track_index: int, item_index: int, note_index: int, by: float) -> bool:
	var item := state.item(track_index, item_index)
	var at := note_index * MidiTake.NOTE_WIDTH
	if item == null or note_index < 0 or at + MidiTake.NOTE_WIDTH > item.notes.size():
		return false
	var on: float = item.notes[at]
	var length: float = float(item.notes[at + 1]) - on
	var to := clampf(on + clampf(by, -NOTE_MOVE_MAX, NOTE_MOVE_MAX), 0.0, maxf(item.length - length, 0.0))
	if is_equal_approx(to, on):
		return false
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	var notes := it.notes.duplicate()
	notes[at] = to
	notes[at + 1] = to + length
	it.notes = notes
	_write_lane(track_index, lane)
	return true


## One note moved in time and pitch at once (see the two above). False when it does neither.
func _locally_place_note(track_index: int, item_index: int, note_index: int, by: float, semitones: int) -> bool:
	var moved := _locally_move_note(track_index, item_index, note_index, by)
	return _locally_transpose_note(track_index, item_index, note_index, semitones) or moved


## One note made to end at `off` seconds into its item: at least MIN_NOTE after it starts, at most
## the item's end. False when there is no such note or it already ends there.
func _locally_set_note_end(track_index: int, item_index: int, note_index: int, off: float) -> bool:
	var item := state.item(track_index, item_index)
	var at := note_index * MidiTake.NOTE_WIDTH
	if item == null or note_index < 0 or at + MidiTake.NOTE_WIDTH > item.notes.size():
		return false
	var on: float = item.notes[at]
	off = clampf(off, on + MidiTake.MIN_NOTE, maxf(item.length, on + MidiTake.MIN_NOTE))
	if is_equal_approx(off, item.notes[at + 1]):
		return false
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	var notes := it.notes.duplicate()
	notes[at + 1] = off
	it.notes = notes
	_write_lane(track_index, lane)
	return true


## The velocity of a note put in by hand.
const INSERT_VELOCITY := 100

## A note put into a MIDI item, in its place among the notes by start, clipped to the item. False
## when the item is not MIDI, the note would begin at or past its end, or it holds MAX_NOTES.
func _locally_insert_note(track_index: int, item_index: int, on: float, off: float, pitch: int) -> bool:
	var item := state.item(track_index, item_index)
	if item == null or item.source != "" or on >= item.length - MidiTake.MIN_NOTE \
			or item.notes.size() / MidiTake.NOTE_WIDTH >= MidiTake.MAX_NOTES:
		return false
	on = maxf(on, 0.0)
	off = clampf(off, on + MidiTake.MIN_NOTE, maxf(item.length, on + MidiTake.MIN_NOTE))
	var at := item.notes.size()
	for n in range(0, item.notes.size() - MidiTake.NOTE_WIDTH + 1, MidiTake.NOTE_WIDTH):
		if item.notes[n] > on:
			at = n
			break
	var notes := item.notes.duplicate()
	var fresh := PackedFloat32Array([on, off, clampi(pitch, 0, 127), INSERT_VELOCITY, 0])
	for k in fresh.size():
		notes.insert(at + k, fresh[k])
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	it.notes = notes
	_write_lane(track_index, lane)
	return true


## One note of a MIDI item moved by semitones, clamped to 0-127. False when there is no such note
## or it cannot move that way.
func _locally_transpose_note(track_index: int, item_index: int, note_index: int, semitones: int) -> bool:
	var item := state.item(track_index, item_index)
	var at := note_index * MidiTake.NOTE_WIDTH
	if item == null or note_index < 0 or at + MidiTake.NOTE_WIDTH > item.notes.size() or semitones == 0:
		return false
	var pitch := clampi(int(item.notes[at + 2]) + semitones, 0, 127)
	if pitch == int(item.notes[at + 2]):
		return false
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	var notes := it.notes.duplicate()
	notes[at + 2] = pitch
	it.notes = notes
	_write_lane(track_index, lane)
	return true


## One note of a MIDI item taken out. False when there is no such note.
func _locally_delete_note(track_index: int, item_index: int, note_index: int) -> bool:
	var item := state.item(track_index, item_index)
	var at := note_index * MidiTake.NOTE_WIDTH
	if item == null or note_index < 0 or at + MidiTake.NOTE_WIDTH > item.notes.size():
		return false
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	var notes := it.notes.duplicate()
	for _k in MidiTake.NOTE_WIDTH:
		notes.remove_at(at)
	it.notes = notes
	_write_lane(track_index, lane)
	return true


## One note of a MIDI item given a velocity. False when there is no such note or it already has it.
func _locally_set_note_velocity(track_index: int, item_index: int, note_index: int, velocity: int) -> bool:
	var item := state.item(track_index, item_index)
	var at := note_index * MidiTake.NOTE_WIDTH
	if item == null or note_index < 0 or at + 4 >= item.notes.size():
		return false
	velocity = clampi(velocity, 1, 127)
	if int(item.notes[at + 3]) == velocity:
		return false
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	var notes := it.notes.duplicate()
	notes[at + 3] = velocity
	it.notes = notes
	_write_lane(track_index, lane)
	return true


## The note a velocity edit means at `seconds` into a MIDI item: the one sounding then, else the
## next to start, else the last. -1 for an item with no notes.
static func note_near(notes: Array, seconds: float) -> int:
	var count := notes.size() / MidiTake.NOTE_WIDTH
	var next := -1
	for n in count:
		var on: float = notes[n * MidiTake.NOTE_WIDTH]
		var off: float = notes[n * MidiTake.NOTE_WIDTH + 1]
		if on <= seconds and seconds < off:
			return n
		if on > seconds and (next < 0 or on < notes[next * MidiTake.NOTE_WIDTH]):
			next = n
	return next if next >= 0 else count - 1


## Every note of a MIDI item moved up to `seconds` early or late and made up to `velocity` softer
## or harder, at random -- but the same random for the same notes: seeded from them, so the host's
## edit is one answer, and a second press (on notes the first has moved) is a different one. A
## note keeps its length, and none is moved before its item's start. Each amount is triangular,
## small nudges commoner than large ones, as a player's are.
func _locally_humanise(track_index: int, item_index: int, seconds: float, velocity: int) -> bool:
	var item := state.item(track_index, item_index)
	if item == null or item.notes.is_empty() or (seconds <= 0.0 and velocity <= 0):
		return false
	seconds = clampf(seconds, 0.0, HUMANISE_SECONDS_MAX)
	velocity = clampi(velocity, 0, HUMANISE_VELOCITY_MAX)
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	var notes := it.notes.duplicate()
	var dice := RandomNumberGenerator.new()
	dice.seed = hash(Array(notes))
	for n in range(0, notes.size() - 4, 5):
		var moved := maxf(notes[n] + (dice.randf() - dice.randf()) * seconds, 0.0) - notes[n]
		notes[n] += moved
		notes[n + 1] += moved
		notes[n + 3] = clampi(int(notes[n + 3]) + roundi((dice.randf() - dice.randf()) * velocity), 1, 127)
	it.notes = notes
	_write_lane(track_index, lane)
	return true


## The grid is in beats from the song's start, through the tempo's changes. A note pulled before
## its item's start stops there.
## The grid point nearest `beat`, in beats, on a grid of `grid` beats swung by `swing`: every odd
## point (the off-beat of each pair) is `swing` thirds of a step late, so at 1 a pair of eighths
## plays as the long-short of a triplet.
static func swung_grid_beat(beat: float, grid: float, swing: float) -> float:
	var at := func(k: int) -> float:
		return k * grid + (swing * grid / 3.0 if posmod(k, 2) == 1 else 0.0)
	var k := floori(beat / grid)
	var best: float = at.call(k)
	for c in [k - 1, k + 1]:
		var b: float = at.call(c)
		if absf(b - beat) < absf(best - beat):
			best = b
	return best


## How early (negative) or late each grid slot of a cycle of `slots` is played, in beats, from the
## notes' onsets (in beats): the mean of its notes' distances from the straight grid. Slots with
## no note are on the grid. Empty if there are no onsets.
static func groove_of(onsets: Array, grid: float, slots := 16) -> Array:
	if onsets.is_empty() or grid <= 0.0 or slots < 1:
		return []
	var sum: Array = []
	var count: Array = []
	sum.resize(slots)
	count.resize(slots)
	sum.fill(0.0)
	count.fill(0)
	for b in onsets:
		var k := roundi(float(b) / grid)
		var slot := posmod(k, slots)
		sum[slot] += float(b) - k * grid
		count[slot] += 1
	var out: Array = []
	for n in slots:
		out.append(sum[n] / count[n] if count[n] > 0 else 0.0)
	return out


## The beat `beat` is pulled to: the nearest straight grid point, moved by its slot's groove.
static func groove_beat(beat: float, grid: float, groove: Array) -> float:
	var k := roundi(beat / grid)
	return k * grid + (float(groove[posmod(k, groove.size())]) if not groove.is_empty() else 0.0)


## False when either item is missing or has no notes, or the two are the same item.
func _locally_groove(track_index: int, item_index: int, from_track: int, from_item: int,
		grid_beats: float, strength: float) -> bool:
	var item := state.item(track_index, item_index)
	var source := state.item(from_track, from_item)
	if item == null or source == null or item.notes.is_empty() or source.notes.is_empty() \
			or (track_index == from_track and item_index == from_item) or strength <= 0.0:
		return false
	var grid := clampf(grid_beats, QUANTIZE_GRID_MIN, QUANTIZE_GRID_MAX)
	strength = clampf(strength, 0.0, 1.0)
	var onsets: Array = []
	for n in range(0, source.notes.size() - 4, 5):
		onsets.append(state.beat_at(source.start + source.notes[n]))
	# A cycle of a bar when the feel lasts a bar or more, else of a beat, so a short pattern still
	# reaches every bar of the one it is lent to.
	var bar_beats := float(state.beats_per_bar)
	var span := state.beat_at(source.end()) - state.beat_at(source.start)
	var groove := groove_of(onsets, grid, maxi(roundi((bar_beats if span >= bar_beats else 1.0) / grid), 1))
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	var notes := it.notes.duplicate()
	for n in range(0, notes.size() - 4, 5):
		var on := it.start + notes[n]
		var target := state.seconds_at_beat(groove_beat(state.beat_at(on), grid, groove))
		var moved := maxf(on + (target - on) * strength, it.start) - on
		notes[n] += moved
		notes[n + 1] += moved
	it.notes = notes
	_write_lane(track_index, lane)
	return true


func _locally_quantize(track_index: int, item_index: int, grid_beats: float, strength: float,
		swing := 0.0) -> bool:
	var item := state.item(track_index, item_index)
	if item == null or item.notes.is_empty() or strength <= 0.0:
		return false
	var grid := clampf(grid_beats, QUANTIZE_GRID_MIN, QUANTIZE_GRID_MAX)
	strength = clampf(strength, 0.0, 1.0)
	var lane := _lane_copy(track_index)
	var it: MixState.ItemState = lane[item_index]
	var notes := it.notes.duplicate()
	for n in range(0, notes.size() - 4, 5):
		var on := it.start + notes[n]
		var target := state.seconds_at_beat(swung_grid_beat(state.beat_at(on), grid,
				clampf(swing, 0.0, SWING_MAX)))
		var moved := maxf(on + (target - on) * strength, it.start) - on
		notes[n] += moved
		notes[n + 1] += moved
	it.notes = notes
	_write_lane(track_index, lane)
	return true


## A recorded take added to a track's items (`items`, a copy of them). On a track that comps, it goes
## on the lane above any it lies over and the comp is made to play it where it was recorded, the usual
## newest-take-plays; on any other track it is just added, a newer item over an older as always.
func _land_in_lane(track_index: int, items: Array, item: MixState.ItemState) -> void:
	var comping := not state.track(track_index).comp.is_empty()
	if comping:
		var above := -1
		for other in items:
			if other.start < item.end() and other.end() > item.start:
				above = maxi(above, other.lane)
		item.lane = mini(above + 1, MixWire.LANES_MAX)
	items.append(item)
	_write_lane(track_index, items)
	if comping:
		_locally_set_comp(track_index, item.start, item.end(), item.lane)


## A take's item, drawn at once: the offline project's whole edit, and a live DAW's preview of
## the answer the bridge is about to give. Its controls are counted from its start, as an item
## carries them (ItemState.controls), and play on the built-in engine with its notes.
func _locally_insert_take(track_index: int, start: float, end: float, notes: Array,
		take_name: String, controls: Array = []) -> void:
	var lane := _lane_copy(track_index)
	var item := MixState.ItemState.new()
	item.start = start
	item.length = end - start
	item.name = take_name
	item.notes = MidiTake.pack_relative(notes, start)
	var relative: Array = []
	for o in range(0, controls.size() - DawKitClip.CONTROL_WIDTH + 1, DawKitClip.CONTROL_WIDTH):
		relative.append_array([float(controls[o]) - start, controls[o + 1], controls[o + 2], controls[o + 3]])
	item.controls = DawKitClip.clean_controls(relative)
	_land_in_lane(track_index, lane, item)


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
	_land_in_lane(track_index, lane, item)


## A pasted clip's item (`paste_item`), drawn at once: `item` (MixWire.unpack_item's) at `start` on
## `track_index`, its file's overview drawn from the file where this machine has it, since a clip
## never carries its peaks.
func _locally_paste(track_index: int, start: float, item: MixState.ItemState) -> void:
	item.start = maxf(start, 0.0)
	if not item.source.is_empty():
		if not take_peaks.has(item.source):
			take_peaks[item.source] = AudioTake.overview_of(media_path(item.source))
		item.peaks = take_peaks[item.source]
		if item.reversed:
			item.peaks = item.peaks.duplicate()
			item.peaks.reverse()
	_land_in_lane(track_index, _lane_copy(track_index), item)


# --- sections rearranged (docs/spatial_loop.md part two, slice 29) -------------------------------
#
# A rearrangement is planned as pieces: each region, and each gap between two of them, as
# [from, end, to] in seconds, `from` and `end` where it is and `to` where it is to start, in the
# new order. The regions take the new order; a gap keeps its place among them. Laid end to end from
# the first region's start, the pieces end where the last region ended, so nothing after moves.
# Only where two pieces next to each other move by different amounts is anything cut (`cuts`):
# a section that stays where it is is left as it was.

## How near two times are to be one, in seconds: a region's edge and the item that ends on it.
const ARRANGE_EPSILON := 0.0005
## How far before a cut edge a closing point of automation goes, to keep a ramp's slope there.
const ARRANGE_EDGE := 0.001


## The pieces for `order` (indices into `regions`, which are in song order), in the new order: one
## [from, end, to] each. Empty when `order` is not a reordering of every region (each once), there
## are fewer than two, or two overlap.
static func arrange_pieces(regions: Array, order: Array) -> Array:
	var n := regions.size()
	if n < 2 or order.size() != n:
		return []
	var seen := {}
	for k in order:
		if typeof(k) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(k)) or int(k) < 0 or int(k) >= n \
				or seen.has(int(k)):
			return []
		seen[int(k)] = true
	if not regions_overlapping(regions).is_empty():
		return []
	var slots: Array = []
	for i in n:
		slots.append(i)
		if i < n - 1 and float(regions[i + 1][0]) - float(regions[i][1]) > ARRANGE_EPSILON:
			slots.append([float(regions[i][1]), float(regions[i + 1][0])])
	var at := float(regions[0][0])
	var next := 0
	var out: Array = []
	for slot in slots:
		var span: Array = slot if slot is Array else regions[int(order[next])]
		if not slot is Array:
			next += 1
		out.append([float(span[0]), float(span[1]), at])
		at += float(span[1]) - float(span[0])
	return out


## The first two regions (indices) that overlap, or [] for none.
static func regions_overlapping(regions: Array) -> Array:
	for i in regions.size() - 1:
		if float(regions[i + 1][0]) < float(regions[i][1]) - ARRANGE_EPSILON:
			return [i, i + 1]
	return []


## How far the piece that holds `seconds` moves (0 outside them).
static func arrange_delta(pieces: Array, seconds: float) -> float:
	for p in pieces:
		if seconds >= float(p[0]) - 0.000001 and seconds < float(p[1]) - 0.000001:
			return float(p[2]) - float(p[0])
	return 0.0


## Where things are cut: each edge, where it is now, between two pieces (or a piece and the song
## beyond them) that move by different amounts. Empty when nothing moves.
static func arrange_cuts(pieces: Array) -> Array:
	var song := pieces.duplicate()
	song.sort_custom(func(a, b): return a[0] < b[0])
	var cuts: Array = []
	var left := 0.0
	for p in song:
		var d := float(p[2]) - float(p[0])
		if absf(d - left) > 0.000001:
			cuts.append(float(p[0]))
		left = d
	if not song.is_empty() and absf(left) > 0.000001:
		cuts.append(float(song[-1][1]))
	return cuts


## The cuts that fall inside [from, to), not on its ends.
static func _cuts_inside(cuts: Array, from: float, to: float) -> Array:
	return cuts.filter(func(c): return c > from + ARRANGE_EPSILON and c < to - ARRANGE_EPSILON)


## Whether a rearrangement would cut or move `item`.
static func arrange_touches(item: MixState.ItemState, pieces: Array, cuts: Array) -> bool:
	return not _cuts_inside(cuts, item.start, item.end()).is_empty() \
			or absf(arrange_delta(pieces, item.start + item.length * 0.5)) > 0.000001


## A lane's items laid out as the pieces say: each cut where it crosses an edge (item_slice, on the
## lane it was on), and each part moved with the piece it is in. Fresh objects, in no order.
static func arranged_items(items: Array, pieces: Array, cuts: Array) -> Array:
	var out: Array = []
	for it: MixState.ItemState in MixWire._unpack_items(MixWire._pack_items(items)):
		var inside := _cuts_inside(cuts, it.start, it.end())
		if inside.is_empty():
			it.start += arrange_delta(pieces, it.start + it.length * 0.5)
			out.append(it)
			continue
		var edges: Array = [it.start] + inside + [it.end()]
		for k in edges.size() - 1:
			var part := item_slice(it, edges[k], edges[k + 1])
			part.lane = it.lane
			part.start += arrange_delta(pieces, (edges[k] + edges[k + 1]) * 0.5)
			out.append(part)
	return out


## Spans of [start, end, ...] (a comp's) laid out as the pieces say, cut at the edges they cross.
static func arranged_spans(spans: Array, pieces: Array, cuts: Array) -> Array:
	var out: Array = []
	for span in spans:
		var edges: Array = [float(span[0])] + _cuts_inside(cuts, float(span[0]), float(span[1])) + [float(span[1])]
		for k in edges.size() - 1:
			var d := arrange_delta(pieces, (edges[k] + edges[k + 1]) * 0.5)
			var part: Array = span.duplicate()
			part[0] = edges[k] + d
			part[1] = edges[k + 1] + d
			out.append(part)
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


## Markers moved with the piece each is on: one on a section's start goes with that section.
static func arranged_markers(markers: Dictionary, pieces: Array) -> Dictionary:
	var out := {}
	for t in markers:
		out[float(t) + arrange_delta(pieces, float(t) + ARRANGE_EPSILON)] = markers[t]
	return out


## The brackets a rearrangement writes so each section keeps its harmony, [seconds, name] each in
## the new song (Harmony). A section with no bracket at its start plays the one before it; moved,
## another may be before it now, so the one it had is written at its new start: onto the marker
## there ("Verse 2 [A minor]"), or as a marker that is only brackets. A progression goes on from
## the bar it had reached, so it is written turned round to start there. The song after the last
## region, when anything is there, keeps its harmony the same way. A section before any bracket
## takes what is before it now: no bracket says "no key".
static func arranged_brackets(s: MixState, pieces: Array) -> Array:
	var out: Array = []
	if pieces.is_empty():
		return out
	var now := arranged_markers(s.markers, pieces)
	var clocks := arranged_clocks(s, pieces)
	var map := DawKitTempoMap.from_array(clocks[0])
	var meter := DawKitMeter.from_array(clocks[1], maxi(s.beats_per_bar, 1), maxi(s.beat_unit, 1))
	var bar_was := func(t: float) -> float: return s.bar_at(t)
	var bar_now := func(t: float) -> float: return meter.bar_at(map.beat_at(t))
	# Each piece's start, [where it was, where it goes], in the new order; then the song after.
	var starts: Array = []
	var last := -INF
	for p in pieces:
		starts.append([float(p[0]), float(p[2])])
		last = maxf(last, float(p[1]))
	if _anything_after(s, last):
		starts.append([last, last])
	starts.sort_custom(func(a, b): return a[1] < b[1])
	for start in starts:
		var was := _harmony_from(s.markers, start[0], bar_was)
		if was.is_empty() or was[2]:
			continue
		var here := _harmony_from(now, start[1], bar_now)
		if not here.is_empty() and here[0] == was[0]:
			continue
		var at: float = start[1]
		var name := "[%s]" % was[1]
		for t in now:
			if absf(float(t) - at) <= Harmony.AT_SLACK:
				at = float(t)
				name = "%s [%s]" % [str(now[t]).strip_edges(), was[1]]
				break
		now[at] = name
		out.append([at, name])
	return out


## The harmony in force at `seconds` among `markers` (Harmony.at's latest bracket at or before
## it), as [what it plays, the bracket to write for it there, whether its bracket is at
## `seconds`]; empty before any. What it plays is the key and the chords from the bar `seconds`
## is in (`bar_of`), so two that say the same compare equal however they were written.
static func _harmony_from(markers: Dictionary, seconds: float, bar_of: Callable) -> Array:
	var times: Array = markers.keys()
	times.sort()
	var h: Harmony = null
	var from := 0.0
	for t in times:
		if float(t) > seconds + Harmony.AT_SLACK:
			break
		var parsed := Harmony.parse(str(markers[t]))
		if parsed != null:
			h = parsed
			from = float(t)
	if h == null:
		return []
	var colon := h.text.find(":")
	var key := (h.text if colon < 0 else h.text.left(colon)).strip_edges()
	var n := h.progression.size()
	var plays := "%d %s" % [h.root, h.mode]
	if n == 0:
		return [plays, h.text, absf(from - seconds) <= Harmony.AT_SLACK]
	var by := posmod(floori(float(bar_of.call(seconds)) + Harmony.BAR_SLACK)
			- floori(float(bar_of.call(from)) + Harmony.BAR_SLACK), n)
	var words := PackedStringArray()
	for i in n:
		words.append(str(h.progression[(by + i) % n][0]))
	# A held bar first holds the chord before it, which the turned round one must say.
	var held := by
	while held > 0 and str(h.progression[held][0]) == "-":
		held -= 1
	words[0] = str(h.progression[held][0])
	var chords := " ".join(words)
	return ["%s: %s" % [plays, chords], h.text if by == 0 else "%s: %s" % [key, chords],
			absf(from - seconds) <= Harmony.AT_SLACK]


## Whether the song goes on after `seconds`: a marker at or past it, or an item ending past it.
static func _anything_after(s: MixState, seconds: float) -> bool:
	if s.markers.keys().any(func(t): return float(t) >= seconds - ARRANGE_EPSILON):
		return true
	for index in s.track_indices():
		if s.track(index).items.any(func(it): return it.start + it.length > seconds + ARRANGE_EPSILON):
			return true
	return false


## The regions moved with themselves, in the new song order.
static func arranged_regions(regions: Array, pieces: Array) -> Array:
	var out: Array = []
	for r in regions:
		var d := arrange_delta(pieces, float(r[0]) + ARRANGE_EPSILON)
		out.append([float(r[0]) + d, float(r[1]) + d, r[2]])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


## The shape of the stretch of `points` at `seconds`: HOLD before the first and after the last.
static func _shape_at(points: Array, seconds: float) -> int:
	var shape := DawKitAutomation.HOLD
	for i in points.size():
		if float(points[i][0]) > seconds:
			return shape if i > 0 else DawKitAutomation.HOLD
		shape = int(points[i][2])
	return DawKitAutomation.HOLD


## A lane of automation ([seconds, value, shape] in order) laid out as the pieces say, so each
## piece sounds as it did: its own points moved with it, and where a piece now meets one it did not,
## a point at its start with its value there (and, ramping into an edge, one just before its end).
## Past the last region the lane is as it was, a point at the end keeping it there. A lane with no
## point in the pieces and nothing ramping through them is returned as it is.
static func arranged_lane(points: Array, pieces: Array, cuts: Array) -> Array:
	if points.is_empty() or cuts.is_empty():
		return points
	var first := INF
	var last := -INF
	for p in pieces:
		first = minf(first, float(p[0]))
		last = maxf(last, float(p[1]))
	var within := points.filter(func(pt): return float(pt[0]) >= first - ARRANGE_EPSILON and float(pt[0]) < last + ARRANGE_EPSILON)
	if within.is_empty() and _shape_at(points, first) == DawKitAutomation.HOLD:
		return points
	var is_cut := func(t: float) -> bool: return cuts.any(func(c): return absf(c - t) < ARRANGE_EPSILON)
	var has_point := func(t: float) -> bool: return points.any(func(pt): return absf(float(pt[0]) - t) < ARRANGE_EPSILON)
	var out: Array = points.filter(func(pt): return float(pt[0]) < first - ARRANGE_EPSILON)
	var before_any := out.is_empty()
	for p in pieces:
		var from := float(p[0])
		var end := float(p[1])
		var d := float(p[2]) - from
		if is_cut.call(from) and not has_point.call(from):
			out.append([from + d, DawKitAutomation.value_in(points, from), _shape_at(points, from)])
		for pt in points:
			if float(pt[0]) >= from - ARRANGE_EPSILON and float(pt[0]) < end - ARRANGE_EPSILON:
				out.append([float(pt[0]) + d, float(pt[1]), int(pt[2])])
		var close := end - ARRANGE_EDGE
		if is_cut.call(end) and _shape_at(points, close) == DawKitAutomation.LINEAR:
			out.append([close + d, DawKitAutomation.value_in(points, close), DawKitAutomation.HOLD])
	if is_cut.call(last) and not has_point.call(last):
		out.append([last, DawKitAutomation.value_in(points, last), _shape_at(points, last)])
	out.append_array(points.filter(func(pt): return float(pt[0]) >= last - ARRANGE_EPSILON))
	# Before the first point its value holds: with none before the pieces any more, keep the start
	# of the song at the value it had.
	if before_any and first > ARRANGE_EDGE and not out.is_empty() \
			and not is_equal_approx(float(out[0][1]), float(points[0][1])):
		out.push_front([0.0, float(points[0][1]), DawKitAutomation.HOLD])
	out.sort_custom(func(a, b): return a[0] < b[0])
	var kept: Array = []
	for pt in out:
		if kept.is_empty() or float(pt[0]) > float(kept[-1][0]) + 0.000001:
			kept.append(pt)
	return kept


## The beats of the song's clock that a tempo or signature change sits on inside the pieces anywhere
## but at a piece's start, or a tempo ramp through them: why they cannot be laid end to end, in
## words naming where, or "". `pieces` in any order; `named` names a piece by its start.
static func arrange_clock_refusal(s: MixState, pieces: Array, named: Callable) -> String:
	var map := s.tempo_map()
	var meter := s.meter()
	var first := INF
	var last := -INF
	var starts: Array = []
	for p in pieces:
		first = minf(first, float(p[0]))
		last = maxf(last, float(p[1]))
		starts.append(map.beat_at(float(p[0])))
	var b0 := map.beat_at(first)
	var b1 := map.beat_at(last)
	var tempo: Array = map.to_array()
	for i in tempo.size():
		var b := float(tempo[i][0])
		var ramps := DawKitTempoMap.shape_of(tempo[i][2]) != DawKitTempoMap.HOLD and i + 1 < tempo.size()
		if ramps and b < b1 - 0.0001 and float(tempo[i + 1][0]) > b0 - 0.0001:
			return "The tempo ramps through %s, so it cannot be moved in time: hold the tempo there first." \
					% named.call(_piece_at(pieces, map.seconds_at(maxf(b, b0))))
		if b > b0 + 0.0001 and b < b1 - 0.0001 and not starts.any(func(st): return absf(st - b) < 0.0001):
			return "The tempo changes inside %s, so it cannot be moved in time: put the change at its start." \
					% named.call(_piece_at(pieces, map.seconds_at(b)))
	for pt in meter.to_array():
		var b := float(pt[0])
		if b > b0 + 0.0001 and b < b1 - 0.0001 and not starts.any(func(st): return absf(st - b) < 0.0001):
			return "The time signature changes inside %s, so it cannot be moved: put the change at its start." \
					% named.call(_piece_at(pieces, map.seconds_at(b)))
	return ""


## The start of the piece that holds `seconds`, or the first piece's.
static func _piece_at(pieces: Array, seconds: float) -> float:
	for p in pieces:
		if seconds >= float(p[0]) - 0.000001 and seconds < float(p[1]) - 0.000001:
			return float(p[0])
	return float(pieces[0][0]) if not pieces.is_empty() else 0.0


## The song's clock laid out as the pieces say: `points` ([beat, ..., ...] from beat 0, a tempo
## map's or a signature's, as DawKitTempoMap.to_array and DawKitMeter.to_array give them) with what
## holds at each piece's start put at its new start, and what held past the last region kept there.
## `value_at` gives the point (less its beat) in force at a beat. Checked first: no change but at a
## piece's start, and no ramp (arrange_clock_refusal), so each piece keeps its beats.
static func arranged_clock(points: Array, pieces: Array, map: DawKitTempoMap, value_at: Callable) -> Array:
	var first := INF
	var last := -INF
	for p in pieces:
		first = minf(first, float(p[0]))
		last = maxf(last, float(p[1]))
	var b0 := map.beat_at(first)
	var b1 := map.beat_at(last)
	var out: Array = points.filter(func(pt): return float(pt[0]) < b0 - 0.0001)
	var held: Array = value_at.call(b0 - 0.0001) if not out.is_empty() else []
	var beat := b0
	for p in pieces:
		var from_beat := map.beat_at(float(p[0]))
		var now: Array = value_at.call(from_beat + 0.0001)
		if not _same_values(now, held):
			out.append([beat] + now)
			held = now
		beat += map.beat_at(float(p[1])) - from_beat
	var after: Array = points.filter(func(pt): return float(pt[0]) >= b1 - 0.0001)
	# A change back at the last region's end that the new last piece already holds says nothing.
	if not after.is_empty() and absf(float(after[0][0]) - b1) <= 0.0001 and _same_values(after[0].slice(1), held):
		after.remove_at(0)
	elif after.is_empty() or absf(float(after[0][0]) - b1) > 0.0001:
		var past: Array = value_at.call(b1 + 0.0001)
		if not _same_values(past, held):
			out.append([b1] + past)
	out.append_array(after)
	return out


## Whether two lists of numbers say the same, to a ten-thousandth.
static func _same_values(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(float(a[i]) - float(b[i])) > 0.0001:
			return false
	return true


## Whether two clocks' points (arranged_clock's) say the same.
static func _same_clock(a: Array, b: Array) -> bool:
	return a.size() == b.size() and range(a.size()).all(func(i): return _same_values(a[i], b[i]))


## The tempo map and signatures laid out as the pieces say ([tempo points, signature points], each
## whole from beat 0, as arranged_clock gives them).
static func arranged_clocks(s: MixState, pieces: Array) -> Array:
	var map := s.tempo_map()
	var meter := s.meter()
	var tempo := arranged_clock(map.to_array(), pieces, map, func(b: float) -> Array:
		return [map.bpm_at(b), DawKitTempoMap.HOLD])
	var sig := arranged_clock(meter.to_array(), pieces, map, func(b: float) -> Array:
		var at := meter.signature_at(b)
		return [at.x, at.y])
	return [tempo, sig]


## Everything a rearrangement changes, for an undo step to put back: every lane and comp, the
## markers, the regions, every lane of automation (the master's under 0), the tempo and its changes,
## and the signature and its changes.
func _arrangement() -> Dictionary:
	var lanes := {0: state.master.automation.duplicate(true)}
	for index in state.track_indices():
		lanes[index] = state.track(index).automation.duplicate(true)
	return {"lanes": _lanes_snapshot(), "markers": state.markers.duplicate(), "regions": state.regions.duplicate(true),
			"automation": lanes, "tempo": [state.tempo, state.tempo_points.duplicate(true)],
			"meter": [state.beats_per_bar, state.beat_unit, state.time_signature_points.duplicate(true)]}


func _put_arrangement(saved: Dictionary) -> void:
	_restore_lanes(saved["lanes"])
	_write_markers(saved["markers"])
	_write_regions(saved["regions"])
	for index in saved["automation"]:
		var was: Dictionary = saved["automation"][index]
		var now: Dictionary = state.master.automation if index == 0 else state.track(index).automation
		for target in now.keys() + was.keys():
			if was.get(target, []) != now.get(target, []):
				_write_automation(index, target, was.get(target, []))
	_write_tempo_points(float(saved["tempo"][0]), saved["tempo"][1])
	_write_meter_points(int(saved["meter"][0]), int(saved["meter"][1]), saved["meter"][2])


## The rearrangement made on the cache (see arrange_sections): the offline project's whole edit, and
## a live DAW's preview of what the bridge is about to do. False when nothing would move.
func _locally_arrange(order: Array) -> bool:
	var pieces := arrange_pieces(state.regions, order)
	var cuts := arrange_cuts(pieces)
	if pieces.is_empty() or cuts.is_empty():
		return false
	var clocks := arranged_clocks(state, pieces)
	var markers := arranged_markers(state.markers, pieces)
	for bracket in arranged_brackets(state, pieces):
		markers[bracket[0]] = bracket[1]
	for index in state.track_indices():
		var t := state.track(index)
		if t.items.any(func(it): return arrange_touches(it, pieces, cuts)):
			_write_lane(index, arranged_items(t.items, pieces, cuts))
		if not t.comp.is_empty():
			var comp := arranged_spans(t.comp, pieces, cuts)
			if comp != t.comp:
				_write_comp(index, comp)
		_arrange_automation(index, t.automation, pieces, cuts)
	_arrange_automation(0, state.master.automation, pieces, cuts)
	_write_markers(markers)
	_write_regions(arranged_regions(state.regions, pieces))
	var tempo: Array = clocks[0]
	if not _same_clock(tempo, state.tempo_map().to_array()):
		_write_tempo_points(float(tempo[0][1]), tempo if tempo.size() > 1 else [])
	var sig: Array = clocks[1]
	if not _same_clock(sig, state.meter().to_array()):
		_write_meter_points(int(sig[0][1]), int(sig[0][2]), sig if sig.size() > 1 else [])
	return true


func _arrange_automation(index: int, lanes: Dictionary, pieces: Array, cuts: Array) -> void:
	for target in lanes.keys():
		var lane := arranged_lane(lanes[target], pieces, cuts)
		if lane != lanes[target]:
			_write_automation(index, target, lane)


## One lane of automation, whole, through the address it arrives on, so it replicates.
func _write_automation(index: int, target: String, points: Array) -> void:
	var address := MixWire.automation_address(index, target)
	MixWire.apply(state, address, MixWire.pack_automation(points))
	record_for_replication(address, MixWire.pack_automation(points))


## The song's tempo and its changes ([beat, bpm, shape], empty for one tempo), so they replicate.
func _write_tempo_points(bpm: float, points: Array) -> void:
	state.tempo_points = points.duplicate(true)
	state.tempo = float(points[0][1]) if not points.is_empty() else bpm
	state.position_string = state.bar_beat(state.position_seconds)
	state.transport_changed.emit()
	record_for_replication("/tempo/map", MixWire.pack_tempo_points(points))
	record_for_replication("/tempo/raw", [state.tempo])


## The song's signature and its changes ([beat, numerator, denominator], empty for one), so they
## replicate.
func _write_meter_points(numerator: int, denominator: int, points: Array) -> void:
	state.beats_per_bar = int(points[0][1]) if not points.is_empty() else numerator
	state.beat_unit = int(points[0][2]) if not points.is_empty() else denominator
	state.time_signature_points = points.duplicate(true) if points.size() > 1 else []
	state.position_string = state.bar_beat(state.position_seconds)
	state.transport_changed.emit()
	record_for_replication("/timesig", [float(state.beats_per_bar), float(state.beat_unit)])
	record_for_replication("/timesig/map", MixWire.pack_meter_points(state.time_signature_points))


## Every lane with something in it, packed, for an undo step to put back.
func _lanes_snapshot() -> Dictionary:
	var out := {}
	for index in state.track_indices():
		out[index] = MixWire._pack_items(state.track(index).items)
		# The comp rides under its own key, "c<track>".
		out["c%d" % index] = MixWire.pack_comp(state.track(index).comp)
	return out


## Every marker, through the address the timeline delivers them on, so it replicates.
func _write_regions(regions: Array) -> void:
	var packed := MixWire.pack_regions(regions)
	record_for_replication("/timeline/regions", packed)
	MixWire.apply(state, "/timeline/regions", packed)


## The song's lyrics, through the address the timeline delivers them on, so they replicate.
func _write_lyrics(text: String) -> void:
	record_for_replication("/timeline/lyrics", [text])
	MixWire.apply(state, "/timeline/lyrics", [text])


func _write_markers(markers: Dictionary) -> void:
	var packed := MixWire._pack_markers(markers)
	record_for_replication("/timeline/markers", packed)
	MixWire.apply(state, "/timeline/markers", packed)


func _restore_lanes(snapshot: Dictionary) -> void:
	for index in snapshot:
		var packed: Array = snapshot[index]
		if index is String:
			record_for_replication("/track/%s/comp" % index.substr(1), packed)
			MixWire.apply(state, "/track/%s/comp" % index.substr(1), packed)
			continue
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


## Where the transport last stood still: where a recording the DAW counts in itself begins.
var _rest_seconds := 0.0
var _was_rolling := false


## Keeps `state.count_in_to` for a DAW that counts in on its own (Reaper): when recording starts
## from a standstill with a count-in due, the take begins where the transport stood, kept until
## the transport stops. The playhead is put back where the DAW is about to say it is, so nothing
## takes in the moment before it does; if it did not count in after all, the next playhead it
## reports is past the record point, and the take begins there. Every frame.
func follow_count_in() -> void:
	var rolling := state.playing
	# Recording counts in with a count-in set; playing, only with it set for playback too.
	var counts := state.counts_in() if state.recording else state.counts_in_playing()
	if rolling and not _was_rolling and state.count_in_to < 0.0 and counts:
		_set_count_in_to(_rest_seconds)
		state.position_seconds = state.count_in_start(_rest_seconds)
		record_for_replication("/time", [state.position_seconds])
	elif state.count_in_to >= 0.0 and not rolling:
		_set_count_in_to(-1.0)
	if not state.playing:
		_rest_seconds = state.position_seconds
	_was_rolling = rolling


func _set_count_in_to(seconds: float) -> void:
	state.count_in_to = seconds
	record_for_replication("/countin/to", [seconds])
	state.transport_changed.emit()


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
