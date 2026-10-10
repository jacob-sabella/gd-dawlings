class_name HitRecorder
extends Node

## The hand percussion played here, taken down as MIDI while the song records (docs/items_loop.md):
## each hit a General MIDI drum note (InstrumentItem.pitch) on channel 10, stamped by the song
## position the player was hearing when they played it, and the take put on the armed track as
## one intent when recording stops -- the way a guest's keys are (GuestMidi, MidiTake).
##
## What is heard is GuestMidi's: the mix stream's position on a guest, the replicated playhead
## on a host. A hit sounds through this machine's output, so the player lines up what comes out
## of the speakers a moment from now with the mix coming out then: the stamp is moved on by the
## output's latency.

## Drums, in MIDI's numbering from 0.
const CHANNEL := 9

## Where the song is, here: {seconds, playing, recording, valid}. GuestMidi.heard by default; the
## suite gives its own.
var heard_source: Callable = Callable()
## What the last take did, for the suite and the notice: {notes, track, start, end} or empty.
var last_take := {}
var takes_sent := 0
## Said once a recording when a hit has nowhere to go: no track armed.
signal unarmed()

var _take: MidiTake = null
## The track the running take goes on: chosen as it begins.
var _track := 0
var _warned := false


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


## A hit played here, `item` the instrument: into the take, if one is running.
func hit(item: InstrumentItem, velocity: int) -> void:
	follow(heard())
	if _take == null:
		var h := heard()
		if h["valid"] and h.get("recording", false) and not _warned:
			_warned = true
			unarmed.emit()
		return
	var at := stamp()
	_take.note_on(item.pitch(), velocity, CHANNEL, at)
	_take.note_off(item.pitch(), CHANNEL, at + InstrumentItem.NOTE_SECONDS)
	_take.reach(at + InstrumentItem.NOTE_SECONDS)


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
## armed track, sent when it stops.
func follow(h: Dictionary) -> void:
	var rolling: bool = h["valid"] and h.get("recording", false) and DAW.state.takes_at(float(h["seconds"]))
	if not rolling:
		_warned = false
	if rolling and armed_track() > 0:
		if _take == null:
			_take = MidiTake.new()
			_take.begin(h["seconds"])
			_track = armed_track()
		_take.reach(h["seconds"])
	elif _take != null:
		_commit()


func _commit() -> void:
	var take := _take
	_take = null
	var done := take.finish()
	var notes: Array = done["notes"]
	var track := _track
	if notes.is_empty() or track <= 0:
		return
	takes_sent += 1
	DAW.insert_midi_take(track, done["start"], done["end"], notes,
			"%s percussion %d" % [Session.local_name, takes_sent])
	last_take = {"notes": notes.size(), "track": track, "start": done["start"], "end": done["end"]}
