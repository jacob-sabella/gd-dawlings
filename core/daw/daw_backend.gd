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


func save_project(_path: String) -> PackedStringArray: return PackedStringArray(["this DAW cannot save from here"])
## Opens a project file in place of the open one; returns what went wrong or was left out of it
## as sentences. It opened when `project_path` is `path` afterwards, whatever it returns.
func open_project(_path: String) -> PackedStringArray: return PackedStringArray(["this DAW cannot open files from here"])
## Replaces the open project with an empty one.
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
## The loop range / time selection, in seconds.
func set_loop_range(_start: float, _end: float) -> void: pass
func undo() -> void: pass
func redo() -> void: pass
## Undone or redone to `depth` steps of history, in one go: the history list's jump.
func undo_to(_depth: int) -> void: pass
## What the edit under way is called, for the history list: set by DAW around each call, "" when
## nobody said.
var acting := ""

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
## A new, empty track at `at` (from 1), everything from there on moving down one.
func add_track(_at: int, _track_name: String) -> void: pass
## A track gone, with its items and effects, and the sends that went to it. A folder's children
## move out a level.
func remove_track(_index: int) -> void: pass
## A copy of a track right after it, as Reaper's duplicate makes one: under the same name, with
## its settings, effects and theirs, sends, items and automation; not armed, not selected. In a
## folder it stays in the folder. One undo step.
func duplicate_track(_index: int) -> void: pass
func rename_track(_index: int, _track_name: String) -> void: pass
func set_track_colour(_index: int, _colour: Color) -> void: pass
## A track into group `group` (1 and up), or out of any (0). One undo step.
func set_track_group(_index: int, _group: int) -> void: pass
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
func render(_stems: bool, _bits := 24, _normalise := false, _rate := 48000) -> void: pass
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


func _write_comp(track_index: int, comp: Array) -> void:
	var packed := MixWire.pack_comp(comp)
	record_for_replication("/track/%d/comp" % track_index, packed)
	MixWire.apply(state, "/track/%d/comp" % track_index, packed)


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
## the answer the bridge is about to give.
func _locally_insert_take(track_index: int, start: float, end: float, notes: Array,
		take_name: String) -> void:
	var lane := _lane_copy(track_index)
	var item := MixState.ItemState.new()
	item.start = start
	item.length = end - start
	item.name = take_name
	item.notes = MidiTake.pack_relative(notes, start)
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
