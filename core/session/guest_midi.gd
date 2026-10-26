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
## position it was played to (`song`), for whoever has a plug in their monitor (TheirMonitor),
## and with what played it (`source`: the keytar, the harp, the fingertips...; `instruments`).
##
## A take follows the host's transport: it begins when the guest HEARS the host start recording
## and ends when it hears the recording stop -- heard, not told, so the take's edges are on the
## same clock as its notes.

signal changed()
## A key down or up, wherever it was played from: for the keytar in this player's hands to show.
signal key(pitch: int, down: bool)
## A note on or off (Session.Note's ON, OFF) as it is sent to everyone, with the song position and
## source it went with: for this player's keys' own jack (`keys:P`, Jacks), which passes it on.
signal note(kind: int, pitch: int, velocity: int, song: float, source: StringName)

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
## The instruments in this player's reach that play their keys: {name: true}, from `&"keytar"`,
## `&"harp"`, `&"fingertips"`, `&"cable"` and `&"wheel"`. While any is here, their keys are
## played, sent and taken down whatever this machine is, a host or alone too, and a take with no
## track chosen goes on the armed one (HitRecorder.armed_track). Each instrument puts in and takes
## out only its own name (`reach`), so one leaving never takes another's away. An instrument is
## in reach before it plays, so the synth is running by its first note, and stays in between
## notes, so a recording is one take across the gaps between strums, not one per strum.
var instruments := {}
## A keytar in this player's hands (KeytarItem): `&"keytar"` in `instruments`.
var keytar: bool:
	get:
		return instruments.has(&"keytar")
	set(v):
		reach(&"keytar", v)
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
## A host's keys heard through the track they go onto (its fader and effects, through Godot's
## mixer: about 44 ms here), rather than straight out through the native helper (about 15 ms).
## On by default, for the take's sake: a key is stamped where the song was as it was heard, and
## how late the song is heard is only known through Godot, whose report leaves out the sound
## server's own buffering. Through the track the key is as late as the song and the two cancel;
## straight out, it is not, and on PipeWire here a recorded note landed 40 ms after its sound.
var through_track := true:
	set(v):
		if through_track == v:
			return
		through_track = v
		if _host_synth:
			# Heard again the new way, from the next key.
			_host_synth = false
			_hear_host_keys()
		changed.emit()
## Where heard() asks, when set: returns {seconds, playing, recording, valid}. For the suite,
## which has no stream to listen to.
var heard_source: Callable = Callable()
## Seconds of song after which a running take is sent and a fresh one begun, and a take is also
## sent when the song wraps round its loop; 0.0 (default) sends only when recording stops, as
## before. Set by Tour during a brief that needs parts ticked live (Tour.take_roll_seconds).
var roll_every := 0.0
## Pitches down right now, for the panel's keys and for closing them if the guest leaves:
## {pitch: velocity}, whatever is holding them. What holds each is counted in `_down`.
var held := {}
## What has each pitch down (KeysDown), by source: a pitch two instruments hold sounds until
## both have let it go.
var _down := KeysDown.new()
## The sources played into the running take, in the order they first played, to name it by.
var _take_sources: Array = []


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


## `name` come into this player's reach (`on`) or gone out of it: the only writer of
## `instruments`. Off the session's keys (not a guest, whose synth always runs), the synth is
## started when the first instrument comes and stopped when the last goes. What the one going
## still had down is let go.
func reach(name: StringName, on: bool) -> void:
	if on == instruments.has(name):
		return
	var had := has_instruments()
	if on:
		instruments[name] = true
	else:
		instruments.erase(name)
		for pitch in _down.held_by(name):
			note_off(pitch, 0, 0.0, false, name)
	if Session.role != Session.Role.GUEST and had != has_instruments():
		if on:
			synth.start()
		else:
			_release_all()
			synth.stop()
	changed.emit()


## Whether any instrument is in this player's reach (`instruments`).
func has_instruments() -> bool:
	return not instruments.is_empty()


## Whether keys played here are this machine's to play: a guest's always, anyone's with an
## instrument in reach, and a host's whose DAW does not record its own inputs (`host_records`).
func plays() -> bool:
	return Session.role == Session.Role.GUEST or has_instruments() or host_records()


## A host (or someone alone) on a DAW that cannot record its own inputs, the built-in engine:
## their keys are played, heard and taken down here, as a guest's are.
func host_records() -> bool:
	return Session.is_authority() and DAW.backend != null \
			and not DAW.can(DAWBackend.Capability.RECORDS_OWN_INPUTS)


## The track a take goes on: the one chosen, or with an instrument in reach or as such a host and
## none chosen, the first armed one that does not take a microphone.
func take_track() -> int:
	if target_track > 0:
		return target_track
	if not (has_instruments() or host_records()) or DAW.state == null:
		return 0
	for index in GuestAudio._armed():
		if not DAW.state.input_of(index).begins_with("audio:"):
			return index
	return 0


## Every track a take goes onto: its own, and as such a host with none chosen, every other armed
## track whose input is the keys.
func take_tracks() -> Array:
	var out: Array = [_take_track] if _take_track > 0 else []
	if target_track > 0 or not host_records() or out.is_empty():
		return out
	for index in GuestAudio._armed():
		if index != _take_track and DAW.state.input_of(index) == "midi":
			out.append(index)
	return out


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
	if has_instruments():
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
## `source`: what played it (`instruments`' names, `&""` for plain keys), sent with it and
## counted in `held`. `at`: the song position it was played to, when the one who played it
## already knows (a note from another player's instrument); NAN for now, `stamp()`. The take and
## the sent note both take it.
func note_on(pitch: int, velocity: int, channel := 0, age := 0.0, sounded := false,
		source := &"", at := NAN) -> void:
	_hear_host_keys()
	var plugin = _track_plugin()
	if plugin != null:
		# The track's own instrument plugin, as a DAW monitors an armed track's instrument.
		plugin.note_on(pitch, velocity, channel)
		_plugin_notes[pitch] = plugin
	elif not sounded:
		synth.note_on(pitch, velocity)
	var timed := not is_nan(at)
	var sent := at if timed else song(age)
	Session.send_note(Session.Note.ON, pitch, velocity, sent, source)
	note.emit(Session.Note.ON, pitch, velocity, sent, source)
	_down.press(pitch, source, velocity)
	held[pitch] = velocity
	key.emit(pitch, true)
	if _take != null:
		_take.note_on(pitch, velocity, channel, at if timed else stamp(age))
		_take_played(source)
	changed.emit()


## A key up, as `note_on` has it. Sent whatever else holds the pitch, so whoever plays this
## player's instruments elsewhere hears that one let go; but here the pitch sounds on, and stays
## in the take, until the last source holding it lets go (`_down`). An up from a source that
## never had down a pitch another source holds touches nothing.
func note_off(pitch: int, channel := 0, age := 0.0, sounded := false, source := &"",
		at := NAN) -> void:
	if not _down.holds(pitch, source) and _down.is_down(pitch):
		return
	var timed := not is_nan(at)
	var sent := at if timed else song(age)
	Session.send_note(Session.Note.OFF, pitch, 0, sent, source)
	note.emit(Session.Note.OFF, pitch, 0, sent, source)
	if not _down.let_go(pitch, source):
		changed.emit()
		return
	if _plugin_notes.has(pitch):
		# Off on the plugin it went on, though the keys have moved to another track since.
		_plugin_notes[pitch].note_off(pitch, channel)
		_plugin_notes.erase(pitch)
	elif not sounded:
		synth.note_off(pitch)
	held.erase(pitch)
	key.emit(pitch, false)
	if _take != null:
		_take.note_off(pitch, channel, at if timed else stamp(age))
	changed.emit()


func sustain(down: bool, channel := 0, age := 0.0, sounded := false) -> void:
	var plugin = _track_plugin()
	if plugin != null:
		plugin.control(64, 127 if down else 0, channel)
	elif not sounded:
		synth.sustain(down)
	Session.send_note(Session.Note.PEDAL_DOWN if down else Session.Note.PEDAL_UP, 0, 0, song(age))
	if _take != null:
		_take.sustain(down, channel, stamp(age))


## Notes played on an instrument plugin and not yet let go: pitch -> the plugin.
var _plugin_notes := {}


## The instrument plugin the host's keys play, when they go through the track (`through_track`)
## and its track has one (the built-in engine's, DAW.track_instrument); null otherwise.
func _track_plugin() -> Object:
	if has_instruments() or not through_track or not host_records():
		return null
	return DAW.track_instrument(take_track())


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
			if not has_instruments():
				_release_all()
				synth.stop()
		return
	if _host_synth and through_track:
		# The keys follow the track they go onto, as the armed track or the choice changes.
		var through := DAW.monitor_bus(take_track())
		if through != synth.bus:
			synth.set_bus(through)
	if midi_open:
		_hear_host_keys()
	_take_native_midi()
	follow(heard())


## A host recording its own keys hears them through the track they go onto (`through_track`), as
## a DAW monitors a track's instrument: the instrument on that track's bus (DAW.monitor_bus), so
## its fader and effects are in what the host hears, through Godot's mixer. Without it, straight
## out through the native helper, sooner, but a take's notes then land late (see through_track).
## Started when MIDI is opened or the first key is played, not before, so a host who never plays
## never has it running.
func _hear_host_keys() -> void:
	if _host_synth or has_instruments() or not host_records():
		return
	_host_synth = true
	if synth.is_running():
		synth.stop()
	if through_track:
		# Through the track, so through Godot: the helper's sound would not pass the track's fader.
		synth.allow_native = false
		synth.set_bus(DAW.monitor_bus(take_track()))
	else:
		synth.allow_native = OS.get_environment("R3D_GODOT_KEYS") != "1"
		synth.set_bus(&"")
	if MonitorSynth.available() and not synth.is_running():
		synth.start()
	# MIDI comes through whichever path plays it.
	_route_midi()


## The take, following what the guest hears of the host's transport: begun when recording is
## heard to start, stretched while it runs, sent when it is heard to stop.
func follow(h: Dictionary) -> void:
	# Past any count-in and inside any punch range, as heard here (MixState.takes_at).
	var rolling: bool = h["valid"] and h["recording"] and DAW.state.takes_at(float(h["seconds"]))
	# A host's keys do not go onto a track whose input is a microphone.
	var takes_keys := not (host_records() and DAW.state.input_of(take_track()).begins_with("audio:"))
	var s: float = float(h["seconds"])
	if _take != null and roll_every > 0.0 and (s >= _take.start + roll_every or s < _take.start - 0.5):
		_commit()
	if rolling and record_with_host and take_track() > 0 and takes_keys:
		if _take == null:
			_take = MidiTake.new()
			_take.begin(h["seconds"])
			_take_track = take_track()
			_take_sources.clear()
			# Keys already down when the take starts are in it from its first moment.
			for pitch in held:
				_take.note_on(pitch, held[pitch], 0, h["seconds"])
				for source in _down.sources_of(pitch):
					_take_played(source)
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
		var name := "%s %s %d" % [Session.local_name, take_name(_take_sources), takes_sent]
		var onto := take_tracks()
		for index in onto:
			DAW.insert_midi_take(index, done["start"], done["end"], notes, name)
		last_take = {"notes": notes.size(), "track": _take_track, "start": done["start"],
				"end": done["end"], "tracks": onto}
	changed.emit()


## `source` played into the running take: kept, to name the take by. Plain keys played with
## the keytar in hand are the keytar's, as they show on it.
func _take_played(source: StringName) -> void:
	var played := source
	if played == &"":
		played = &"keytar" if keytar else &"keys"
	if played not in _take_sources:
		_take_sources.append(played)


## What a take is called after what played in it (`_take_played`): `harp`, `harp+fingertips`,
## `keytar`, and `take` for plain keys alone, as every take was before there were instruments.
static func take_name(played: Array) -> String:
	if played.is_empty() or played == [&"keys"]:
		return "take"
	return "+".join(PackedStringArray(played.map(func(s: StringName) -> String: return String(s))))


## Every key down let go, by whatever holds it: heard, sent and shown, as if each were.
func _release_all() -> void:
	for pitch in held.keys():
		var sources := _down.sources_of(pitch)
		if sources.is_empty():
			note_off(pitch)
		for source in sources:
			note_off(pitch, 0, 0.0, false, source)
	held.clear()
	_down.clear()


## Tracks were added or removed on the host: the chosen track is still the same track, and none
## once it is gone.
func follow_renumber(map: Dictionary) -> void:
	if target_track > 0:
		target_track = int(map.get(target_track, 0))
	if _take_track > 0:
		_take_track = int(map.get(_take_track, 0))
