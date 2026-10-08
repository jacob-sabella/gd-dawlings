class_name GuestMidi
extends Node

## A guest's keyboard, played into the host's project.
##
## The guest hears the host's mix late and plays along to what it hears. Each note is stamped
## with the song position that was coming out of the guest's speakers when the key went down
## (MixFeed.heard_position), not with the moment it reached anyone, and a take goes to the host
## as one intent -- DAW.insert_midi_take -- which puts it where the guest heard it. The guest
## hears its own keys from a small local synth, never round trip. See docs/architecture.md,
## "Recording a guest".
##
## A take follows the host's transport: it begins when the guest HEARS the host start recording
## and ends when it hears the recording stop -- heard, not told, so the take's edges are on the
## same clock as its notes.

signal changed()

## Notes from MIDI devices (OS.open_midi_inputs) and from the computer keyboard both land here.
## The track a take goes onto; 0 for none chosen.
var target_track := 0:
	set(v):
		target_track = v
		changed.emit()
## Record when the host records. Off, notes still play the monitor but nothing is taken.
var record_with_host := true:
	set(v):
		if record_with_host and not v and _take != null:
			_commit()
		record_with_host = v
		changed.emit()
## Hear my own keys, locally.
var monitor := true:
	set(v):
		monitor = v
		synth.enabled = v
		changed.emit()
var monitor_db := -6.0:
	set(v):
		monitor_db = v
		synth.volume_db = v

var synth: MonitorSynth
## The MIDI devices the OS reported when inputs were last opened.
var devices := PackedStringArray()
var midi_open := false
## What the last take did, for the panel: {notes, track, start, end} or empty.
var last_take := {}
## How many takes this guest has sent, for naming them.
var takes_sent := 0
## The song position to stamp with when the guest is not listening to the stream -- someone in
## the host's own room, hearing the host's speakers. The replicated playhead, run between
## updates; less exact than the stream's stamps by however late the host's speakers are.
var _replicated := SongClock.new()
var _take: MidiTake = null
## Where heard() asks, when set: returns {seconds, playing, recording, valid}. For the suite,
## which has no stream to listen to.
var heard_source: Callable = Callable()
## Pitches down right now, for the panel's keys and for closing them if the guest leaves.
var held := {}


func _ready() -> void:
	synth = MonitorSynth.new()
	synth.name = "MonitorSynth"
	add_child(synth)
	synth.volume_db = monitor_db
	Session.role_changed.connect(_on_role_changed)


func _exit_tree() -> void:
	if midi_open:
		OS.close_midi_inputs()


## Open every MIDI input the OS can see. Asked for, rather than done at startup, because on some
## systems opening the inputs takes the devices away from other applications.
func open_midi() -> void:
	if midi_open:
		OS.close_midi_inputs()
	OS.open_midi_inputs()
	devices = OS.get_connected_midi_inputs()
	midi_open = true
	changed.emit()


func close_midi() -> void:
	if midi_open:
		OS.close_midi_inputs()
	midi_open = false
	devices = PackedStringArray()
	changed.emit()


func is_recording() -> bool:
	return _take != null


func take_note_count() -> int:
	return 0 if _take == null else _take.notes.size() + _take.held_count()


func _on_role_changed() -> void:
	if Session.role == Session.Role.GUEST:
		if MonitorSynth.available():
			synth.start()
		return
	# Out of the session: a take in progress has nowhere to go any more.
	_take = null
	_release_all()
	synth.stop()
	target_track = 0


func _input(event: InputEvent) -> void:
	var midi := event as InputEventMIDI
	if midi == null or Session.role != Session.Role.GUEST:
		return
	match midi.message:
		MIDI_MESSAGE_NOTE_ON:
			# Running status: a note-on at velocity 0 is how most keyboards say note-off.
			if midi.velocity == 0:
				note_off(midi.pitch, midi.channel)
			else:
				note_on(midi.pitch, midi.velocity, midi.channel)
		MIDI_MESSAGE_NOTE_OFF:
			note_off(midi.pitch, midi.channel)
		MIDI_MESSAGE_CONTROL_CHANGE:
			if midi.controller_number == 64:
				sustain(midi.controller_value >= 64, midi.channel)


func note_on(pitch: int, velocity: int, channel := 0) -> void:
	synth.note_on(pitch, velocity)
	held[pitch] = velocity
	if _take != null:
		_take.note_on(pitch, velocity, channel, stamp())
	changed.emit()


func note_off(pitch: int, channel := 0) -> void:
	synth.note_off(pitch)
	held.erase(pitch)
	if _take != null:
		_take.note_off(pitch, channel, stamp())
	changed.emit()


func sustain(down: bool, channel := 0) -> void:
	if _take != null:
		_take.sustain(down, channel, stamp())


## The song position this guest is hearing now: the mix stream's stamp when listening to it,
## the replicated playhead when not. {seconds, playing, recording, valid, source}.
func heard() -> Dictionary:
	if heard_source.is_valid():
		var given: Dictionary = heard_source.call()
		given["source"] = "given"
		return given
	var feed := Session.mix_feed
	if feed != null and feed.listening:
		var h := feed.heard_position()
		if h["valid"]:
			h["source"] = "stream"
			return h
	var out := _replicated.at(Time.get_ticks_usec())
	out["source"] = "replicated"
	return out


## The song position to give a note played now: what the guest is hearing, moved on by the time
## the note's own sound takes to reach the guest's ears through the monitor synth. The player
## lines up the SOUND of the key with the sound of the mix; the key went down that much earlier.
## With the monitor off they hear their own gear, whose latency is theirs and is not known here.
func stamp() -> float:
	var h := heard()
	var seconds: float = h["seconds"]
	if h["playing"] and monitor and synth.is_running():
		seconds += synth.latency_seconds()
	return seconds


func _process(_delta: float) -> void:
	if Session.role != Session.Role.GUEST:
		return
	if DAW.state != null:
		_replicated.observe(DAW.state.position_seconds, DAW.state.playing, DAW.state.recording,
				Time.get_ticks_usec())
	follow(heard())


## The take, following what the guest hears of the host's transport: begun when recording is
## heard to start, stretched while it runs, sent when it is heard to stop.
func follow(h: Dictionary) -> void:
	var rolling: bool = h["valid"] and h["recording"]
	if rolling and record_with_host and target_track > 0:
		if _take == null:
			_take = MidiTake.new()
			_take.begin(h["seconds"])
			# Keys already down when the take starts are in it from its first moment.
			for pitch in held:
				_take.note_on(pitch, held[pitch], 0, h["seconds"])
			changed.emit()
		_take.reach(h["seconds"])
	elif _take != null:
		_commit()


## The take, to the host, as one intent.
func _commit() -> void:
	var take := _take
	_take = null
	if take == null:
		return
	var done := take.finish()
	var notes: Array = done["notes"]
	if not notes.is_empty() and target_track > 0:
		takes_sent += 1
		var name := "%s take %d" % [Session.local_name, takes_sent]
		DAW.insert_midi_take(target_track, done["start"], done["end"], notes, name)
		last_take = {"notes": notes.size(), "track": target_track, "start": done["start"],
				"end": done["end"]}
	changed.emit()


func _release_all() -> void:
	for pitch in held.keys():
		synth.note_off(pitch)
	held.clear()
