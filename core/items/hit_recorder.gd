class_name HitRecorder
extends Node

## The hand percussion played here, taken down as MIDI while the song records (docs/items_loop.md):
## each hit a General MIDI drum note (InstrumentItem.pitch) on channel 10 (9 from 0), or a pitched
## item's note on its own channel (InstrumentItem.MELODIC_CHANNEL), stamped by the song
## position the player was hearing when they played it, and the take put on the armed track as
## one intent when recording stops -- the way a guest's keys are (GuestMidi, MidiTake).
##
## An instrument whose output jack goes into a track (Jacks, docs/spatial_loop.md slice 5) is
## recorded onto that track instead, armed or not: a take of its own per track, begun with its
## first hit while the song records and sent with the armed one's, when recording stops.
##
## What is heard is GuestMidi's: the mix stream's position on a guest, the replicated playhead
## on a host. A hit sounds through this machine's output, so the player lines up what comes out
## of the speakers a moment from now with the mix coming out then: the stamp is moved on by the
## output's latency.

##
## SNAPPED GENTLY (docs/spatial_loop.md slice 17). A hand percussion hit (not a pitched item's) is
## recorded a little nearer the beat than it was played: within SNAP_WINDOW of the nearest
## sixteenth (`snapped_at`, on MixState's bar grid), it is moved SNAP_PULL of the way there. Only the
## stamp moves: what was heard, and the `at` sent to the room, are the hit's own. Whether a hit is
## snapped is its player's ("Snap hand percussion", GuestMidi.snap_hits), carried with each hit
## (Session.item_hit's `snap`), so it is the player's choice whichever machine takes it down.

## Drums, in MIDI's numbering from 0.
const CHANNEL := 9
## How far of the way to the nearest sixteenth a snapped hit is moved: half, so a feel is kept.
const SNAP_PULL := 0.5
## Only a hit this near a sixteenth (s) is moved; one further off was played there on purpose.
const SNAP_WINDOW := 0.035
## A sixteenth, in the tempo map's quarter-note beats.
const SIXTEENTH := 0.25

## Where the song is, here: {seconds, playing, recording, valid}. GuestMidi.heard by default; the
## suite gives its own.
var heard_source: Callable = Callable()
## Seconds of song after which a running take is sent and a fresh one begun, and a take is also
## sent when the song wraps round its loop (the same "has it moved on, or stepped sharply back"
## check catches both); 0.0 (default) sends only when recording stops, as before. Set by Tour
## during a brief that needs parts ticked live (Tour.take_roll_seconds), unset otherwise.
var roll_every := 0.0
## What the last take did, for the suite and the notice: {notes, track, start, end} or empty.
var last_take := {}
var takes_sent := 0
## Said once a recording when a hit has nowhere to go: no track armed.
signal unarmed()

var _take: MidiTake = null
## The track the running take goes on: chosen as it begins.
var _track := 0
var _warned := false
## The takes onto tracks a jack goes into, by track: {track: MidiTake}.
var _jacked: Dictionary = {}


## The track a take goes on: the first armed, or none.
static func armed_track() -> int:
	if DAW.state == null:
		return 0
	var indices: Array = DAW.state.tracks.keys()
	indices.sort()
	for index in indices:
		var t: MixState.TrackState = DAW.state.tracks[index]
		if t != null and t.rec_arm:
			return int(index)
	return 0


func heard() -> Dictionary:
	if heard_source.is_valid():
		return heard_source.call()
	if Session.guest_midi != null:
		return Session.guest_midi.heard()
	return {"seconds": 0.0, "playing": false, "recording": false, "valid": false}


func is_recording() -> bool:
	return _take != null


## The tracks a jack's take is running onto now.
func jacked_tracks() -> Array:
	var out := _jacked.keys()
	out.sort()
	return out


## A hit played here, `item` the instrument: into the take, if one is running. `at` is the song
## position the hit was played to (InstrumentItem.played's, the one read of `stamp` its sound was
## pitched by), so it is recorded where and as what it was heard, with no second stamp; NAN is
## "now". Its note is the item's at `at` (`note_at`: a drum's own pitch, a bell's chord tone), on
## the item's channel (`channel`: the drums', or InstrumentItem.MELODIC_CHANNEL), as long as the
## item says (`note_seconds`). `track`, a track its jack goes into (Jacks.hit): onto that track's
## own take, whether or not anything is armed, and not into the armed one; 0, the armed one.
## `snap`: whether its player snaps it (1 yes, 0 no; -1 this player's own `snaps`). A pitched
## item's note is never moved: its tone is the chord's at `at`.
func hit(item: InstrumentItem, velocity: int, at := NAN, track := 0, snap := -1) -> void:
	var h := heard()
	follow(h)
	var moved := (snap == 1 or (snap < 0 and snaps())) and not item.pitched()
	if track > 0:
		if not _rolling(h):
			return
		if is_nan(at):
			at = stamp()
		if moved:
			at = snapped_at(at, DAW.state)
		var take: MidiTake = _jacked.get(track)
		if take == null:
			take = MidiTake.new()
			# From where the song is heard, or from the hit if it was played a hair before that.
			take.begin(minf(float(h["seconds"]), at))
			_jacked[track] = take
		_note(take, item, velocity, at)
		return
	if _take == null:
		if h["valid"] and h.get("recording", false) and not _warned:
			_warned = true
			unarmed.emit()
		return
	if is_nan(at):
		at = stamp()
	if moved:
		at = snapped_at(at, DAW.state)
	_note(_take, item, velocity, at)


## Whether this player's hand percussion is snapped: "Snap hand percussion" (GuestMidi.snap_hits),
## on unless they turned it off.
static func snaps() -> bool:
	return Session.guest_midi == null or Session.guest_midi.snap_hits


## The sixteenth nearest song position `seconds`, on `state`'s grid: counted from the start of the
## bar it is in (MixState.bar_at), through the tempo's and the signature's changes.
static func nearest_sixteenth(seconds: float, state: MixState) -> float:
	if state == null:
		return seconds
	var beat := state.beat_at(seconds)
	var meter := state.meter()
	var bar_from := meter.beat_of_bar(floorf(meter.bar_at(beat)))
	return state.seconds_at_beat(bar_from + roundf((beat - bar_from) / SIXTEENTH) * SIXTEENTH)


## Where a snapped hit played to `seconds` is recorded: SNAP_PULL of the way to the nearest
## sixteenth when it is within SNAP_WINDOW of it, where it was played otherwise.
static func snapped_at(seconds: float, state: MixState) -> float:
	var off := nearest_sixteenth(seconds, state) - seconds
	if absf(off) > SNAP_WINDOW:
		return seconds
	return seconds + off * SNAP_PULL


## One hit into `take`: the item's note at `at`, on its channel, as long as it says.
func _note(take: MidiTake, item: InstrumentItem, velocity: int, at: float) -> void:
	var note := item.note_at(at)
	var length := item.note_seconds()
	take.note_on(note, velocity, item.channel(), at)
	take.note_off(note, item.channel(), at + length)
	take.reach(at + length)


## Whether what is heard now is being recorded: recording, past any count-in, inside any punch.
func _rolling(h: Dictionary) -> bool:
	return h["valid"] and h.get("recording", false) and DAW.state.takes_at(float(h["seconds"]))


## The song position a hit played now lands on, in the player's ears.
func stamp() -> float:
	var h := heard()
	var seconds: float = h["seconds"]
	if h["playing"]:
		seconds += AudioServer.get_output_latency()
	return seconds


func _process(_delta: float) -> void:
	follow(heard())


## The take, following the transport as heard: begun when recording is heard to start onto an
## armed track, sent when it stops -- and, with `roll_every` set, sent and begun afresh as the
## song moves on, so a part ticks live rather than waiting for the whole brief to finish.
func follow(h: Dictionary) -> void:
	var rolling := _rolling(h)
	if not rolling:
		_warned = false
	var s: float = float(h["seconds"])
	if _take != null and roll_every > 0.0 and (s >= _take.start + roll_every or s < _take.start - 0.5):
		_commit()
	if rolling and armed_track() > 0:
		if _take == null:
			_take = MidiTake.new()
			_take.begin(h["seconds"])
			_track = armed_track()
		_take.reach(h["seconds"])
	elif _take != null:
		_commit()
	# A jack's takes keep the same time as the armed one's: sent when it stops or rolls on, and a
	# fresh one begun by the next hit.
	for track in _jacked.keys():
		var take: MidiTake = _jacked[track]
		if not rolling or (roll_every > 0.0 and (s >= take.start + roll_every or s < take.start - 0.5)):
			_jacked.erase(track)
			_send(take, int(track))
		else:
			take.reach(s)


func _commit() -> void:
	var take := _take
	_take = null
	_send(take, _track)


## `take`, finished, onto `track` as one intent: nothing, if nothing was played into it.
func _send(take: MidiTake, track: int) -> void:
	var done := take.finish()
	var notes: Array = done["notes"]
	if notes.is_empty() or track <= 0:
		return
	takes_sent += 1
	DAW.insert_midi_take(track, done["start"], done["end"], notes,
			"%s percussion %d" % [Session.local_name, takes_sent])
	last_take = {"notes": notes.size(), "track": track, "start": done["start"], "end": done["end"]}
