class_name SessionPlay
extends RefCounted

## The notes, controls and jack events a player sends to everyone else, with the host's checks on what a guest may
## send. Moved out of `core/session/session.gd` without change of behaviour; the state stays on the autoload, which keeps a
## one-line delegate (with its `@rpc` line where it has one) for each name another file, a string or the network reaches.

var session: Session


func _init(of: Session) -> void:
	session = of


func _note_up(kind: int, pitch: int, velocity: int, song: float, source: StringName) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if session.role != session.Role.HOST or not session._is_member(from):
		return
	if String(source).length() > session.NOTE_SOURCE_MAX:
		source = &""
	session.note_played.emit(kind, pitch, velocity, from, song, source)
	for id in session.admitting._audience():
		if id != from:
			session._note.rpc_id(id, kind, pitch, velocity, from, song, source)


func _note(kind: int, pitch: int, velocity: int, from: int, song: float, source: StringName) -> void:
	session.note_played.emit(kind, pitch, velocity, from, song, source)


## A control on my keys (`kind` one of CONTROL_KINDS), to everyone else, as it moves, with the
## song position it went with and what moved it (`source`, as `send_note`'s). On a channel of its
## own (CONTROLS_CHANNEL), unreliable and ordered: GuestMidi sends one off rest again at least
## every GuestMidi.CONTROL_EVERY, so a lost one costs a few tens of milliseconds and never a note.
## Sent as it is asked: the host is the one that refuses and clamps (`_pass_control`).
func send_control(kind: int, value: int, song := -1.0, source := &"") -> void:
	if not session._connected():
		return
	if session.role == session.Role.HOST:
		_pass_control(kind, value, song, source, session.local_peer_id)
	else:
		session._control_up.rpc_id(1, kind, value, song, source)


func _control_up(kind: int, value: int, song: float, source: StringName) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if session.role != session.Role.HOST or not session._is_member(from):
		return
	_pass_control(kind, value, song, source, from)


## Host: `from`'s control, refused unless it is one of CONTROL_KINDS, its value clamped by kind,
## heard here (unless it is the host's own) and passed on to everyone else. Whether it passed.
func _pass_control(kind: int, value: int, song: float, source: StringName, from: int) -> bool:
	if not session.CONTROL_KINDS.has(kind):
		session.controls_refused += 1
		return false
	value = control_value(kind, value)
	if not is_finite(song) or song < 0.0:
		song = -1.0
	if String(source).length() > session.NOTE_SOURCE_MAX:
		source = &""
	if from != session.local_peer_id:
		session.control_played.emit(kind, value, from, song, source)
	for id in session.admitting._audience():
		if id != from:
			session._control.rpc_id(id, kind, value, from, song, source)
	return true


func _control(kind: int, value: int, from: int, song: float, source: StringName) -> void:
	session.control_played.emit(kind, value, from, song, source)


## `value` kept in bounds for a control of `kind`: the pitch wheel -8192 to 8191, a controller 0
## to 127.
static func control_value(kind: int, value: int) -> int:
	if kind == DawKitClip.PITCH_BEND:
		return clampi(value, int(DawKitClip.BEND_MIN), int(DawKitClip.BEND_MAX))
	return clampi(value, 0, 127)


## Where a control of `kind` rests, as a keyboard sits untouched: the wheel at its centre, the mod
## wheel down, expression full. What every end puts it back to at a player's last note-off.
static func control_rest(kind: int) -> int:
	return 127 if kind == 11 else 0


## An event down `source`'s jack into player `to`'s instrument, at song position `song` (-1 for
## not known): up to the host, which checks it (`jack_refusal`) and passes it on to `to` alone.
## Reliable, on the keys' channel with the notes, because a lost note-off is a note that never
## stops. docs/spatial_loop.md slice 6.
func send_jack(to: int, source: StringName, kind: int, pitch: int, velocity: int, song := -1.0) -> void:
	if not session._connected():
		return
	if session.role == session.Role.HOST:
		_pass_jack(to, source, kind, pitch, velocity, song, session.local_peer_id)
	else:
		session._jack_up.rpc_id(1, to, source, kind, pitch, velocity, song)


func _jack_up(to: int, source: StringName, kind: int, pitch: int, velocity: int, song: float) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if session.role != session.Role.HOST or not session._is_member(from):
		return
	_pass_jack(to, source, kind, pitch, velocity, song, from)


## Host: `from`'s jack event, checked, and passed on to `to` (or played here, when `to` is the
## host). Its numbers are kept in bounds by its kind before anyone plays them, and a CC that is
## not one of CONTROL_KINDS is refused. A CHORD goes only down a chord hand's jack and nothing
## else does (part two, slice 33), and one naming no quality there is is refused. Whether it passed.
func _pass_jack(to: int, source: StringName, kind: int, pitch: int, velocity: int, song: float,
		from: int) -> bool:
	var chord_hand := Jack.chord_player(source) > 0
	if kind < Jack.Kind.NOTE_ON or kind > Jack.Kind.CHORD or jack_refusal(to, source, from) != "" \
			or (kind == Jack.Kind.CC and not session.CONTROL_KINDS.has(pitch)) \
			or (kind == Jack.Kind.CHORD) != chord_hand \
			or (kind == Jack.Kind.CHORD and (velocity < 0 or velocity > Jack.quality_count())):
		session.jacks_refused += 1
		return false
	# Clamped by kind: a note's pitch and velocity are MIDI's 0-127, a control's `pitch` is its
	# controller and its `velocity` its value, the bend's -8192 to 8191 (`control_value`), and a
	# chord's `pitch` its root, a pitch class.
	if kind == Jack.Kind.CC:
		velocity = control_value(pitch, velocity)
	elif kind == Jack.Kind.CHORD:
		pitch = clampi(pitch, 0, 11)
	else:
		pitch = clampi(pitch, 0, 127)
		velocity = clampi(velocity, 0, 127)
	if not is_finite(song) or song < 0.0:
		song = -1.0
	if to == session.local_peer_id:
		session.jack_played.emit(source, kind, pitch, velocity, from, song)
	else:
		session._jack.rpc_id(to, source, kind, pitch, velocity, from, song)
	return true


## Host: why `from`'s event down `source`'s jack may not go into `to`, or empty if it may. Both
## are in the room, they are not the same player, and the room's patch and who plays the source
## say so (`jack_check`).
func jack_refusal(to: int, source: StringName, from: int) -> String:
	if not session._is_member(to):
		return "player %d is not in the room" % to
	if not session._is_member(from):
		return "player %d is not in the room" % from
	if to == from:
		return "a jack goes into a bandmate, not into yourself"
	if not Jack.valid_source(source):
		return "there is no such jack"
	if not session.jack_check.is_valid():
		return "there is no room here to say where it goes"
	return str(session.jack_check.call(to, source, from))


func _jack(source: StringName, kind: int, pitch: int, velocity: int, from: int, song: float) -> void:
	session.jack_played.emit(source, kind, pitch, velocity, from, song)
