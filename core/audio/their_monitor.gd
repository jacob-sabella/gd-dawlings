class_name TheirMonitor
extends Node

## Another player's monitor, rebuilt here: what they hear -- the backing, and their own keys on
## it -- in time as they heard it (docs/items_loop.md). For a staged performance: the performer
## goes ON AIR, and whoever has a plug in their pack's MONITOR socket hears them in time with the
## backing they played to.
##
## No sound crosses the session for it. Their notes do, each stamped with the song position they
## were hearing as they played it (Session.note_played, GuestMidi.song). Everyone hears the
## backing at their own moment and a note gets here later still, so neither can be played as it
## comes: here the mix this machine plays is copied (an AudioEffectCapture at the head of the Mix
## bus, ahead of the headphones' gain) into a delay line, held back by `delay` seconds, and each
## note waits until the delayed backing reaches the position it was played to. The delay starts
## at a guess from the network and grows, by a gap in the backing, whenever a note comes later
## than it allows; it never shrinks while the plug stays in, so the performance does not keep
## jumping.
##
## So the copy is as late as the slowest note, and that is the price: you hear them in time, not
## live. Where the mix is not played by the game (a host on Reaper) the backing is silence and
## only their notes are heard, still in time with each other.

## The guess a delay line starts at, over the note's own trip: the gap between their hearing and
## mine is not known until their first note says.
const START_S := 0.08
## Kept over the latest note there has been, so jitter does not keep finding the edge.
const MARGIN_S := 0.03
## The most the backing is held back. Past it the two are too far apart to be one performance (a
## seek, a stopped transport on one side) and a note is played as it comes.
const MOST_S := 1.5
## A note further ahead of the backing than this is not waited for.
const AHEAD_S := 2.0
## What the capture adds to the line on top of what is queued in it: Godot's mixer hands a bus
## over in steps of this many frames, so what has just been captured was mixed up to a step ago.
## Measured with a tone (an 80 ms line came out 84 ms behind the mix, while the queue read a
## sawtooth of 69 and 80): a step's worth puts the estimate on it.
const CAPTURE_LAG_FRAMES := 512
## A line's event that is a control, not a note: [due, CONTROL, controller, value].
const CONTROL := -1

## {peer id: Line}, the performers being listened to.
var lines: Dictionary = {}
## Where the song is, here: {seconds, playing, valid}. GuestMidi.heard by default; the suite
## gives its own.
var heard_source: Callable = Callable()
var _capture: AudioEffectCapture = null


## The bus a performer's monitor plays on here, by name.
static func bus_of(peer: int) -> StringName:
	return StringName("Their monitor %d" % peer)


## Listen to the monitors of `peers`, and of nobody else.
func set_performers(peers: Array) -> void:
	for peer in lines.keys():
		if peer not in peers:
			(lines[peer] as Line).stop()
			lines.erase(peer)
	for peer in peers:
		if lines.has(int(peer)):
			continue
		var line := Line.new()
		line.peer = int(peer)
		line.name = "Monitor%d" % peer
		line.delay = START_S + maxf(Session.note_delay_ms(int(peer)), 0.0) / 1000.0
		add_child(line)
		line.start()
		lines[int(peer)] = line
	_tap(not lines.is_empty())


func performers() -> Array:
	return lines.keys()


## A note from `from`, as Session.note_played says it: into their line, if it is listened to.
## A note-off from one of their instruments (`source`) while another still holds the pitch is
## not sounded: it would stop the other's note. Counted as they come, which is the order they
## were played in, and so the order the line sounds them.
## Their last note-off puts their wheel back to rest as it sounds, as on their end.
func play(kind: int, pitch: int, velocity: int, from: int, song := -1.0, source := &"") -> void:
	var line: Line = lines.get(from)
	if line == null:
		return
	if kind == Session.Note.ON:
		line.down.press(pitch, source, velocity)
	elif kind == Session.Note.OFF and not line.down.let_go(pitch, source):
		return
	line.arrive(kind, pitch, velocity, song, heard(), kind == Session.Note.OFF and line.down.is_empty())


## A control from `from`, as Session.control_played says it: into their line with the notes, so
## it bends what they played when it sounds, at the position they moved it at. Only while they
## have a note down, as TheirKeys.control has it.
func control(kind: int, value: int, from: int, song := -1.0, _source := &"") -> void:
	var line: Line = lines.get(from)
	if line == null or line.down.is_empty():
		return
	line.arrive(CONTROL, kind, value, song, heard())


func heard() -> Dictionary:
	if heard_source.is_valid():
		return heard_source.call()
	if Session.guest_midi != null:
		return Session.guest_midi.heard()
	return {"seconds": 0.0, "playing": false, "valid": false}


func _process(_delta: float) -> void:
	if lines.is_empty():
		return
	var frames := PackedVector2Array()
	if _capture != null and _keep_first():
		frames = _capture.get_buffer(_capture.get_frames_available())
	var h := heard()
	for line: Line in lines.values():
		line.feed(frames)
		line.tick(h)


func _exit_tree() -> void:
	_tap(false)


## The copy of the mix: a capture at the head of the Mix bus while anyone is listened to.
func _tap(on: bool) -> void:
	var at := AudioServer.get_bus_index(Ears.MIX)
	if at < 0:
		return
	if on and _capture == null:
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(at, _capture, 0)
	elif not on and _capture != null:
		for i in AudioServer.get_bus_effect_count(at):
			if AudioServer.get_bus_effect(at, i) == _capture:
				AudioServer.remove_bus_effect(at, i)
				break
		_capture = null


## Whether the capture is still first on the Mix bus, ahead of the headphones' gain (Ears), which
## goes in at the head too: put back there if not.
func _keep_first() -> bool:
	var at := AudioServer.get_bus_index(Ears.MIX)
	if at < 0:
		return false
	if AudioServer.get_bus_effect_count(at) > 0 and AudioServer.get_bus_effect(at, 0) == _capture:
		return true
	for i in AudioServer.get_bus_effect_count(at):
		if AudioServer.get_bus_effect(at, i) == _capture:
			AudioServer.remove_bus_effect(at, i)
			break
	AudioServer.add_bus_effect(at, _capture, 0)
	_capture.clear_buffer()
	return false


## One performer's monitor: the delayed backing on a generator, their notes on a synth, both on
## the performer's bus.
class Line extends Node:
	var peer := 0
	## How far behind this machine's own mix the copy is held, in seconds: what it is meant to be.
	var delay := START_S
	## Notes waiting for the backing to reach them: [song, kind, pitch, velocity, rest], in the
	## order they were played; `rest` on their last note-off, which puts the wheel back to rest.
	## A control waits among them as [song, CONTROL, controller, value, false].
	var waiting: Array = []
	## How far the latest late note missed by, for the suite and the tablet: 0 when none has.
	var last_late := 0.0
	## What has been played on this line, for the suite: [kind, pitch].
	var sounded: Array = []
	## The controls played on this line, for the suite: [controller, value].
	var controlled: Array = []
	## What of theirs has each pitch down (TheirMonitor.play).
	var down := KeysDown.new()
	var synth: MonitorSynth
	var _player: AudioStreamPlayer = null
	var _playback: AudioStreamGeneratorPlayback = null
	var _capacity := 0
	## Silence still to go into the line ahead of the copy: the delay, and any growth of it.
	var _owed := 0

	func start() -> void:
		var bus := TheirMonitor.bus_of(peer)
		if AudioServer.get_bus_index(bus) < 0:
			var at := AudioServer.bus_count
			AudioServer.add_bus(at)
			AudioServer.set_bus_name(at, bus)
			AudioServer.set_bus_send(at, &"Master")
		synth = MonitorSynth.new()
		synth.name = "Keys"
		synth.allow_native = false
		synth.bus = bus
		synth.volume_db = Session.guest_midi.monitor_db if Session.guest_midi != null else -6.0
		add_child(synth)
		synth.start()
		if not MonitorSynth.available():
			return
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = AudioServer.get_mix_rate()
		stream.buffer_length = MOST_S + 0.5
		_player = AudioStreamPlayer.new()
		_player.name = "Backing"
		_player.bus = bus
		_player.stream = stream
		add_child(_player)
		_player.play()
		_playback = _player.get_stream_playback()
		_capacity = _playback.get_frames_available()
		_owed = int(delay * stream.mix_rate)

	func stop() -> void:
		if synth != null:
			synth.stop()
		queue_free()

	## How long what goes into the line now takes to come out: what is queued in it, or the
	## delay it is meant to have where there is no line to measure (no sound here).
	func held_seconds() -> float:
		if _playback == null:
			return delay
		return float(_capacity - _playback.get_frames_available() + _owed + CAPTURE_LAG_FRAMES) \
				/ AudioServer.get_mix_rate()

	## The song position the delayed backing is at now, for `h` what this machine hears.
	func position(h: Dictionary) -> float:
		return float(h["seconds"]) - held_seconds()

	## The mix as it was just played here, into the line, behind whatever silence is owed.
	func feed(frames: PackedVector2Array) -> void:
		if _playback == null:
			return
		var room := _playback.get_frames_available()
		if _owed > 0 and room > 0:
			var gap := PackedVector2Array()
			gap.resize(mini(_owed, room))
			_playback.push_buffer(gap)
			_owed -= gap.size()
			room -= gap.size()
		if frames.size() > 0 and room > 0:
			_playback.push_buffer(frames if frames.size() <= room else frames.slice(0, room))

	## A note of theirs, `song` the position they played it to, as `h` this machine hears now:
	## kept for the backing to reach it, or, if the backing is past it already, played now and the
	## line made that much longer, so the next one is in time.
	func arrive(kind: int, pitch: int, velocity: int, song: float, h: Dictionary, rest := false) -> void:
		if song < 0.0 or not (h["valid"] and h["playing"]):
			_sound(kind, pitch, velocity, rest)
			return
		var due := song - synth_latency()
		var late := position(h) - due
		if late > MOST_S or -late > AHEAD_S:
			_sound(kind, pitch, velocity, rest)
			return
		if late > 0.0 and kind == CONTROL:
			# Behind the backing already, and so ahead of everything waiting: played now. A control
			# does not grow the line; it may be a resend, or one of a stream that drops some.
			_sound(kind, pitch, velocity, rest)
			return
		if late > 0.0:
			last_late = late
			var grow := minf(late + MARGIN_S, MOST_S - delay)
			if grow > 0.0:
				delay += grow
				_owed += int(grow * AudioServer.get_mix_rate())
			# Behind it, nothing waiting can be due any later than this.
			for w in waiting:
				_sound(w[1], w[2], w[3], w[4])
			waiting.clear()
			_sound(kind, pitch, velocity, rest)
			return
		waiting.append([due, kind, pitch, velocity, rest])

	## The notes the backing has reached, played, in order.
	func tick(h: Dictionary) -> void:
		if waiting.is_empty():
			return
		if not (h["valid"] and h["playing"]):
			for w in waiting:
				_sound(w[1], w[2], w[3], w[4])
			waiting.clear()
			return
		var at := position(h)
		while not waiting.is_empty() and float(waiting[0][0]) <= at:
			var w: Array = waiting.pop_front()
			_sound(w[1], w[2], w[3], w[4])

	func synth_latency() -> float:
		return synth.latency_seconds() if synth != null else 0.0

	func _sound(kind: int, pitch: int, velocity: int, rest := false) -> void:
		if kind == CONTROL:
			controlled.append([pitch, velocity])
			if synth != null:
				synth.control(pitch, velocity)
			return
		sounded.append([kind, pitch])
		if synth == null:
			return
		match kind:
			Session.Note.ON: synth.note_on(pitch, velocity)
			Session.Note.OFF:
				synth.note_off(pitch)
				if rest:
					synth.rest_controls()
			Session.Note.PEDAL_DOWN: synth.sustain(true)
			Session.Note.PEDAL_UP: synth.sustain(false)
