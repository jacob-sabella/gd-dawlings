class_name MixState
extends RefCounted

## The mix, as this process currently believes it to be.
##
## DAW-NEUTRAL BY CONSTRUCTION. Nothing in here is a Reaper concept: tracks with a level, a pan,
## three toggles and a colour; plugins with normalised parameters; sends named by destination;
## a transport. Every DAW this project could speak to has all of it, and the ones that have more
## can carry it as additional fields rather than as a second model. The translation from a
## particular DAW's wire vocabulary into this lives in that DAW's backend and nowhere else --
## see core/daw/daw_backend.gd.
##
## This is a CACHE, never a master copy. The DAW owns the mix; everything here arrived over the
## wire and may be stale by a frame. Nothing in the scene may treat a value here as committed:
## a fader that has been grabbed shows the hand's position and waits for Reaper to agree.
##
## Why a plain model with signals rather than nodes holding their own values: in a hybrid session
## the same track is drawn several times at once -- a channel strip on someone's monitor, the same
## strip in AR two metres away, a rack unit, and a node on the patchbay. One cache, many readers.

signal track_added(index: int)
signal track_changed(index: int, field: StringName)
signal transport_changed()
signal master_changed(field: StringName)
signal fx_changed(track_index: int, fx_index: int)
## The arrangement changed shape: items appeared or moved, or the project got longer. Separate
## from track_added because a timeline rebuilds on this and a console does not care.
signal timeline_changed()
## Which slice of the project the track indices currently mean.
signal bank_changed()


class SendState extends RefCounted:
	var index: int = 0
	var dest_name: String = ""
	## The destination's track number, or -1 when only a name is known.
	##
	## Both, rather than one, because the two channels disagree about what a send points at.
	## OSC can only say the destination's NAME, which is ambiguous the moment a project has two
	## tracks called "Verb" -- and duplicate names are completely normal. The ReaScript bridge
	## says the index. Whoever draws a cable should prefer the index and fall back to the name,
	## so the bay is exact when the bridge is loaded and still roughly right when it is not.
	var dest_track: int = -1

	## The destination, best effort: the index when the bridge supplied one, else resolve the
	## name against `state`.
	func resolve(state) -> int:
		if dest_track > 0:
			return dest_track
		if dest_name == "":
			return -1
		for index in state.track_indices():
			if state.track(index).display_name() == dest_name:
				return index
		return -1

	var volume: float = 1.0
	var pan: float = 0.5


class FXState extends RefCounted:
	var index: int = 0
	var name: String = ""
	var enabled: bool = true
	## Normalised 0..1 by param index. Sparse on purpose: Reaper only reports the current
	## parameter bank, so a missing key means "not yet told", which is not the same as zero.
	var params: Dictionary = {}
	var param_names: Dictionary = {}


## The master bus. Deliberately NOT a TrackState with a reserved index.
##
## Reaper addresses it as `/master/...`, not as a numbered track, and it has no mute, no solo, no
## record arm and no sends-to-anywhere. Folding it into the track dictionary would mean every
## loop over `track_indices()` -- the console's strips, the patchbay's two rows, the rack --
## having to remember to skip it, and the one that forgets puts a MASTER jack on the patchbay.
class MasterState extends RefCounted:
	var volume: float = 0.716
	var volume_db: float = 0.0
	var pan: float = 0.5
	var vu_l: float = 0.0
	var vu_r: float = 0.0


## One block of audio or MIDI on the timeline.
##
## Deliberately thin. A DAW's item has takes, stretch markers, fades, envelopes and a source
## file; none of that is drawable at the size a lane is rendered, and carrying it would mean a
## second model to keep in sync for no pixel gained. What the timeline draws is where a thing
## starts, how long it is, what it is called and whether it is muted.
class ItemState extends RefCounted:
	var index: int = 0
	## Seconds from the start of the project. Seconds and not bars: tempo can change, and a
	## position stored in bars would move whenever it did.
	var start: float = 0.0
	var length: float = 0.0
	var name: String = ""
	var muted: bool = false

	func end() -> float:
		return start + length


class TrackState extends RefCounted:
	var index: int = 0
	var name: String = ""
	## The DAW's normalised fader position, 0..1 -- NOT a gain multiplier and NOT dB. Converting it
	## for display is a control's business; storing it converted would lose the round trip.
	var volume: float = 0.716
	var volume_db: float = 0.0
	var pan: float = 0.5
	var mute: bool = false
	var solo: bool = false
	var rec_arm: bool = false
	var selected: bool = false
	var colour: Color = Color(0.55, 0.57, 0.6)
	## Reaper's I_FOLDERDEPTH on this track: 1 opens a folder, 0 stays at the current level, and
	## a negative number closes that many. It is a DELTA, not a level -- the level is the running
	## sum over the tracks before it, which is what `MixState.folder_level` works out.
	var folder_depth: int = 0
	## Peak 0..1 per channel. Decayed by the meter that draws it, not by Reaper.
	var vu_l: float = 0.0
	var vu_r: float = 0.0
	var fx: Dictionary = {}
	var sends: Dictionary = {}
	## ItemState, in start order. Empty when the backend cannot report an arrangement at all,
	## which is not the same as a track with nothing on it -- see DAWBackend.Capability.
	var items: Array = []

	func display_name() -> String:
		return name if name != "" else "Track %d" % index


var tracks: Dictionary = {}
var master := MasterState.new()
var playing: bool = false
var recording: bool = false
var position_seconds: float = 0.0
var position_string: String = "1.1.00"
var tempo: float = 120.0
## Seconds. How far the ruler has to run, which is NOT derivable from the items: a project can
## be longer than its last item, and a timeline that ends at the last block cannot be scrolled
## into the empty bars you are about to record into.
var project_length: float = 0.0
## {position_seconds: String name}, in no particular order.
var markers: Dictionary = {}

## How many of the project's tracks come BEFORE the one this cache calls index 1.
##
## The uncomfortable fact this models: a control surface protocol streams a BANK of tracks, not
## a project. Reaper's bank is 64 wide, so in a 90-track session the indices in this cache mean
## tracks 1..64 or tracks 65..90 depending on where the bank is, and nothing in the message
## itself says which. Without this, a 90-track project silently looks like a 64-track one and
## the fader labelled KICK moves something else after a bank change.
var bank_offset: int = 0
## How wide the bank is -- how many tracks the surface can see at once.
var bank_size: int = 64
## Tracks in the whole project, or -1 when nothing has said. -1 is not zero: "I have not been
## told how big this project is" and "this project has no tracks" want opposite things drawn.
var project_track_count: int = -1


## The project-wide number of a track this cache calls `index`. What a human reads off a desk.
func absolute_track_number(index: int) -> int:
	return bank_offset + index


## True when there is more project than this bank can show.
func has_more_banks() -> bool:
	return project_track_count > bank_size


## Which tracks this cache is holding, out of how many exist, or "" when it holds them all.
##
## Here rather than in each surface because THREE things now have to say it and they must not
## drift: a console that says "17-32 OF 90" beside a timeline that says "17-32 of 90 tracks" is
## two different facts as far as anyone reading the room is concerned.
##
## Measured from what is HELD, not from bank_size. has_more_banks() asks whether the project is
## bigger than a bank, which is a different question and not always the same answer -- the
## offline stand-in at 90 tracks caches all 90 and a caption derived from bank_size would have
## read "TRACKS 1-64 OF 90" over ninety drawn lanes. A caption that disagrees with the thing it
## is captioning is worse than none, since the whole job here is to be believed about what is
## missing. The range therefore comes from the keys actually in the cache.
##
## Empty string for "nothing to say", which is the case a caller must handle: a session that
## fits needs no caption, and a caption that is always present teaches people to stop reading
## it exactly when it starts mattering.
func bank_caption() -> String:
	var held := tracks.size()
	if project_track_count <= 0 or held <= 0 or held >= project_track_count:
		return ""
	return "TRACKS %d-%d OF %d" % [bank_offset + 1, bank_offset + held, project_track_count]


func set_bank(offset: int, size: int = -1) -> void:
	var new_size := size if size > 0 else bank_size
	if offset == bank_offset and new_size == bank_size:
		return
	bank_offset = offset
	bank_size = new_size
	# The indices now mean different tracks, so everything keyed by index is wrong rather than
	# stale. Dropping it is the only honest move: keeping it would leave the previous bank's
	# names on this bank's faders until each one happened to be re-sent.
	tracks.clear()
	bank_changed.emit()


## Replace one track's arrangement wholesale.
##
## Wholesale and not per item, because the only honest unit of change is the lane: a DAW that
## reports items at all reports them as a list, and diffing to find the three that moved costs
## more than redrawing twelve rectangles.
func set_track_items(index: int, items: Array) -> void:
	var t := track(index)
	t.items = items
	t.items.sort_custom(func(a, b): return a.start < b.start)
	timeline_changed.emit()


func set_project_length(seconds: float) -> void:
	if is_equal_approx(project_length, seconds):
		return
	project_length = seconds
	timeline_changed.emit()


## The length the ruler should actually draw: whatever the DAW says, but never shorter than the
## last thing on the timeline, and never zero -- a ruler of length zero divides by it.
func timeline_length() -> float:
	var out := project_length
	for index in tracks:
		var t: TrackState = tracks[index]
		if not t.items.is_empty():
			out = maxf(out, t.items[-1].end())
	return maxf(out, 1.0)


func track(index: int, create: bool = true) -> TrackState:
	if tracks.has(index):
		return tracks[index]
	if not create:
		return null
	var t := TrackState.new()
	t.index = index
	tracks[index] = t
	track_added.emit(index)
	return t


## How deep in the folder tree a track sits, counting from 0.
##
## Reaper stores the DELTA on each track rather than the level, because that is what a .RPP
## records -- so the level only exists as a running sum, and only in track order. Computed on
## demand rather than cached: the alternative is a cache invalidated by every structure poll,
## every bank change and every track insert, which is three chances to show the wrong grouping.
func folder_level(index: int) -> int:
	var level := 0
	for i in track_indices():
		if i >= index:
			break
		level = maxi(level + track(i).folder_depth, 0)
	return level


## True when `index` starts a new group. This is what a console puts a gap at.
##
## NOT simply "the level changed", which is the obvious rule and the wrong one. A folder's
## parent sits at the OUTER level -- that is what makes it the parent -- so a level-change rule
## cuts between the bus and its own children and leaves the bus lumped in with whatever
## happened to precede it. On the demo project that put the VOX bus in with the guitars.
##
## So: a group starts where a track OPENS a folder (the parent heads its group, the way a track
## panel draws it) or where the level DROPS back out of one. A rise immediately under a parent
## is not a break, because the parent already started that group.
func starts_group(index: int) -> bool:
	var order := track_indices()
	var at := order.find(index)
	if at <= 0:
		return at == 0
	if track(index).folder_depth > 0:
		return true
	return folder_level(index) < folder_level(order[at - 1])


func track_indices() -> Array:
	var keys := tracks.keys()
	keys.sort()
	return keys


func set_track_field(index: int, field: StringName, value: Variant) -> void:
	var t := track(index)
	if t.get(field) == value:
		return
	t.set(field, value)
	track_changed.emit(index, field)


func set_master_field(field: StringName, value: Variant) -> void:
	if master.get(field) == value:
		return
	master.set(field, value)
	master_changed.emit(field)


func fx(track_index: int, fx_index: int, create: bool = true) -> FXState:
	var t := track(track_index)
	if t.fx.has(fx_index):
		return t.fx[fx_index]
	if not create:
		return null
	var f := FXState.new()
	f.index = fx_index
	t.fx[fx_index] = f
	fx_changed.emit(track_index, fx_index)
	return f


func send(track_index: int, send_index: int, create: bool = true) -> SendState:
	var t := track(track_index)
	if t.sends.has(send_index):
		return t.sends[send_index]
	if not create:
		return null
	var s := SendState.new()
	s.index = send_index
	t.sends[send_index] = s
	return s
