class_name ReaperState
extends RefCounted

## The mix, as this process currently believes it to be.
##
## This is a CACHE, never a master copy. Reaper owns the mix; everything here arrived over the
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


class SendState extends RefCounted:
	var index: int = 0
	var dest_name: String = ""
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


class TrackState extends RefCounted:
	var index: int = 0
	var name: String = ""
	## Reaper's normalised fader taper, 0..1 -- NOT a gain multiplier and NOT dB. Converting it
	## for display is a control's business; storing it converted would lose the round trip.
	var volume: float = 0.716
	var volume_db: float = 0.0
	var pan: float = 0.5
	var mute: bool = false
	var solo: bool = false
	var rec_arm: bool = false
	var selected: bool = false
	var colour: Color = Color(0.55, 0.57, 0.6)
	## Peak 0..1 per channel. Decayed by the meter that draws it, not by Reaper.
	var vu_l: float = 0.0
	var vu_r: float = 0.0
	var fx: Dictionary = {}
	var sends: Dictionary = {}

	func display_name() -> String:
		return name if name != "" else "Track %d" % index


var tracks: Dictionary = {}
var master := MasterState.new()
var playing: bool = false
var recording: bool = false
var position_seconds: float = 0.0
var position_string: String = "1.1.00"
var tempo: float = 120.0


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


## Reaper's normalised fader position to dB, close enough to its default taper to label a cap
## that is being dragged. Reaper also sends the true value on TRACK_VOLUME_DB -- prefer that
## whenever it has arrived, and use this only for a position the user is holding right now.
static func taper_to_db(v: float) -> float:
	if v <= 0.0:
		return -INF
	return 40.0 * (log(v) / log(10.0))


static func db_to_taper(db: float) -> float:
	return pow(10.0, db / 40.0)
