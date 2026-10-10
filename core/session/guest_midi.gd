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
## Every note also goes to everyone as it is played (Session.send_note), the host's keys and
## guests' alike, for whoever has a plug in this player's keys (TheirKeys), stamped with the song
## position it was played to (`song`), for whoever has a plug in their monitor (TheirMonitor).
##
## A take follows the host's transport: it begins when the guest HEARS the host start recording
## and ends when it hears the recording stop -- heard, not told, so the take's edges are on the
## same clock as its notes.

signal changed()
## A key down or up, wherever it was played from: for the keytar in this player's hands to show.
signal key(pitch: int, down: bool)

## Notes from MIDI devices and from the computer keyboard both land here. MIDI comes from the
## monitor keys' helper where it runs (NativeKeys: read from the sequencer the moment it
## arrives, heard at once, and passed on here stamped with when), and from Godot's own MIDI
## input (OS.open_midi_inputs, read once a frame) where it does not.
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
## A keytar in this player's hands (KeytarItem): their keys are played, sent and taken down
## whatever this machine is, a host or alone too, and a take with no track chosen goes on the
## armed one (HitRecorder.armed_track).
var keytar := false:
	set(v):
		if v == keytar:
			return
		keytar = v
		if Session.role != Session.Role.GUEST:
			if v:
				synth.start()
			else:
				_release_all()
				synth.stop()
		changed.emit()
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
## Whether MIDI is wanted: asked for from the panel.
var midi_open := false
## Whether Godot's own MIDI input is what is open, rather than the helper's.
var _os_midi := false
## What the last take did, for the panel: {notes, track, start, end} or empty.
var last_take := {}
## How many takes this guest has sent, for naming them.
var takes_sent := 0
## The song position to stamp with when the guest is not listening to the stream -- someone in
## the host's own room, hearing the host's speakers. The replicated playhead, run between
## updates; less exact than the stream's stamps by however late the host's speakers are.
var _replicated := SongClock.new()
var _take: MidiTake = null
## The track the running take goes on, chosen as it began.
var _take_track := 0
## Whether the monitor synth was started for a host recording its own keys (`host_records`).
var _host_synth := false
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
	if _os_midi:
		OS.close_midi_inputs()


## Open every MIDI input there is. Asked for, rather than done at startup, because on some
## systems opening the inputs takes the devices away from other applications.
func open_midi() -> void:
	midi_open = true
	_route_midi()


func close_midi() -> void:
	midi_open = false
	_route_midi()


## MIDI from wherever it is quickest: the helper's sequencer port while it runs, Godot's own
## input while it does not. Never both -- the same device opened twice is refused, or doubled.
func _route_midi() -> void:
	var native := synth.native if synth != null else null
	var by_os := midi_open and native == null
	if _os_midi and not by_os:
		OS.close_midi_inputs()
	if by_os:
		if _os_midi:
			OS.close_midi_inputs()
		OS.open_midi_inputs()
	_os_midi = by_os
	if native != null:
		native.take_midi(midi_open)
	devices = OS.get_connected_midi_inputs() if by_os else PackedStringArray()
	changed.emit()


## Whether keys played here are this machine's to play: a guest's always, anyone's with a keytar,
## and a host's whose DAW does not record its own inputs (`host_records`).
func plays() -> bool:
	return Session.role == Session.Role.GUEST or keytar or host_records()


## A host (or someone alone) on a DAW that cannot record its own inputs, the built-in engine:
## their keys are played, heard and taken down here, as a guest's are.
func host_records() -> bool:
	return Session.is_authority() and DAW.backend != null \
			and not DAW.can(DAWBackend.Capability.RECORDS_OWN_INPUTS)


## The track a take goes on: the one chosen, or with a keytar or as such a host and none chosen,
## the armed one.
func take_track() -> int:
	if target_track > 0:
		return target_track
	return HitRecorder.armed_track() if keytar or host_records() else 0


func is_recording() -> bool:
	return _take != null


func take_note_count() -> int:
	return 0 if _take == null else _take.notes.size() + _take.held_count()


func _on_role_changed() -> void:
	if Session.role == Session.Role.GUEST:
		if MonitorSynth.available():
			synth.start()
		_route_midi()
		return
	# Out of the session: a take in progress has nowhere to go any more.
	_take = null
	_release_all()
	synth.stop()
	if keytar:
		synth.start()
	_route_midi()
	target_track = 0


func _input(event: InputEvent) -> void:
	var midi := event as InputEventMIDI
	if midi == null or not plays():
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


## A key down. `age`: how long ago it went down, for a note that was heard before it got here
## (the helper's); `sounded`: whether it has been heard already, so it is not played twice.
func note_on(pitch: int, velocity: int, channel := 0, age := 0.0, sounded := false) -> void:
	_hear_host_keys()
	if not sounded:
		synth.note_on(pitch, velocity)
	Session.send_note(Session.Note.ON, pitch, velocity, song(age))
	held[pitch] = velocity
	key.emit(pitch, true)
	if _take != null:
		_take.note_on(pitch, velocity, channel, stamp(age))
	changed.emit()


func note_off(pitch: int, channel := 0, age := 0.0, sounded := false) -> void:
	if not sounded:
		synth.note_off(pitch)
	Session.send_note(Session.Note.OFF, pitch, 0, song(age))
	held.erase(pitch)
	key.emit(pitch, false)
	if _take != null:
		_take.note_off(pitch, channel, stamp(age))
	changed.emit()


func sustain(down: bool, channel := 0, age := 0.0, sounded := false) -> void:
	if not sounded:
		synth.sustain(down)
	Session.send_note(Session.Note.PEDAL_DOWN if down else Session.Note.PEDAL_UP, 0, 0, song(age))
	if _take != null:
		_take.sustain(down, channel, stamp(age))


## What the helper heard and played since the last frame, into the take.
func _take_native_midi() -> void:
	var native := synth.native
	if native == null:
		return
	if native.devices != devices:
		devices = native.devices.duplicate()
		changed.emit()
	for e in native.take():
		if e.has("sustain"):
			sustain(e["sustain"], e["channel"], e["age"], true)
		elif e["on"]:
			note_on(e["pitch"], e["velocity"], e["channel"], e["age"], true)
		else:
			note_off(e["pitch"], e["channel"], e["age"], true)


## The song position this guest is hearing now: the mix stream's stamp when listening to it,
## the replicated playhead when not. {seconds, playing, recording, valid, source}.
func heard() -> Dictionary:
	if heard_source.is_valid():
		var given: Dictionary = heard_source.call()
		given["source"] = "given"
		return given
	if host_records():
		# The host's own engine, heard through its own output: the playhead less what the output
		# still holds, as the host's microphone is timed.
		var own := Session.host_heard()
		own["source"] = "host"
		return own
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
## `age`: how long ago the key went down, for one that is only being told of now.
func stamp(age := 0.0) -> float:
	var h := heard()
	var seconds: float = h["seconds"]
	if h["playing"]:
		seconds -= age
		if monitor and synth.is_running():
			seconds += synth.latency_seconds()
	return seconds


## The song position a note played now was played to, as `stamp` has it, for the monitor others
## hear it in (TheirMonitor); -1 when what is heard is not a song playing.
func song(age := 0.0) -> float:
	var h := heard()
	return stamp(age) if h["valid"] and h["playing"] else -1.0


func _process(_delta: float) -> void:
	# On a host too: there, what is heard is the host's own playhead, and a monitor (TheirMonitor)
	# asks it.
	if DAW.state != null:
		_replicated.observe(DAW.state.position_seconds, DAW.state.playing, DAW.state.recording,
				Time.get_ticks_usec())
	if not plays():
		if _take != null:
			_commit()
		if _host_synth:
			_host_synth = false
			synth.set_bus(&"")
			synth.allow_native = OS.get_environment("R3D_GODOT_KEYS") != "1"
			if not keytar:
				_release_all()
				synth.stop()
		return
	if _host_synth:
		# The keys follow the track they go onto, as the armed track or the choice changes.
		var through := DAW.monitor_bus(take_track())
		if through != synth.bus:
			synth.set_bus(through)
	if midi_open:
		_hear_host_keys()
	_take_native_midi()
	follow(heard())


## A host recording its own keys hears them through the track they go onto, as a DAW monitors a
## track's instrument: the instrument on that track's bus (DAW.monitor_bus), so its fader and
## effects are in what the host hears. Started when MIDI is opened or the first key is played,
## not before, so a host who never plays never has it running.
func _hear_host_keys() -> void:
	if _host_synth or keytar or not host_records():
		return
	_host_synth = true
	# Through the track, so through Godot: the helper's sound would not pass the track's fader.
	synth.allow_native = false
	if synth.native != null:
		synth.stop()
	synth.set_bus(DAW.monitor_bus(take_track()))
	if MonitorSynth.available() and not synth.is_running():
		synth.start()
	# MIDI came through the helper while it ran; now it comes through Godot.
	_route_midi()


## The take, following what the guest hears of the host's transport: begun when recording is
## heard to start, stretched while it runs, sent when it is heard to stop.
func follow(h: Dictionary) -> void:
	# Past any count-in and inside any punch range, as heard here (MixState.takes_at).
	var rolling: bool = h["valid"] and h["recording"] and DAW.state.takes_at(float(h["seconds"]))
	# A host's keys do not go onto a track whose input is a microphone.
	var takes_keys := not (host_records() and DAW.state.input_of(take_track()).begins_with("audio:"))
	if rolling and record_with_host and take_track() > 0 and takes_keys:
		if _take == null:
			_take = MidiTake.new()
			_take.begin(h["seconds"])
			_take_track = take_track()
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
	if not notes.is_empty() and _take_track > 0:
		takes_sent += 1
		var name := "%s %s %d" % [Session.local_name, "keytar" if keytar else "take", takes_sent]
		DAW.insert_midi_take(_take_track, done["start"], done["end"], notes, name)
		last_take = {"notes": notes.size(), "track": _take_track, "start": done["start"],
				"end": done["end"]}
	changed.emit()


## Every key down let go: heard, sent and shown, as if each were.
func _release_all() -> void:
	for pitch in held.keys():
		note_off(pitch)
	held.clear()


## Tracks were added or removed on the host: the chosen track is still the same track, and none
## once it is gone.
func follow_renumber(map: Dictionary) -> void:
	if target_track > 0:
		target_track = int(map.get(target_track, 0))
	if _take_track > 0:
		_take_track = int(map.get(_take_track, 0))
