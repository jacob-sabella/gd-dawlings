class_name GuestPlay
extends Node

## A guest's keys, sounded live on the host's instrument plugin.
##
## A guest's notes already reach the host as they are played (Session.note_played) and again as a
## take when the guest's recording ends. This is the live half: the guest tells the host which
## track its keys play into (Session.send_play_track), and the host plays each note on that
## track's instrument plugin (DAW.track_instrument, the built-in engine's), so the room hears the
## guest play the instrument as they play it. The take is what is recorded; nothing here is kept,
## so a note is not played twice when the take is placed.
##
## Their pitch wheel, mod wheel and expression (Session.control_played) go to the same plugin, and
## at their last note-off every one they moved is put back at rest, as GuestMidi does on their end,
## so no reset ever has to arrive.
##
## Only plain keys (no `source`): the harp, the strings and the modular have their own voices.

## {peer id: {pitch: the plugin it went on}}: let go on the plugin it began on, though the guest's
## track has moved on since.
var _held: Dictionary = {}
## {peer id: {control kind: the plugin it was moved on}}: what to put back at rest.
var _moved: Dictionary = {}


func _ready() -> void:
	Session.note_played.connect(_on_note)
	Session.control_played.connect(_on_control)
	Session.play_track_changed.connect(_on_track)


func _exit_tree() -> void:
	release_all()


func _on_note(kind: int, pitch: int, velocity: int, from: int, _song: float, source := &"") -> void:
	if Session.role != Session.Role.HOST or from == Session.local_peer_id or source != &"":
		return
	var down: Dictionary = _held.get(from, {})
	match kind:
		Session.Note.ON:
			var plugin = DAW.track_instrument(int(Session.play_tracks.get(from, 0)))
			if plugin == null:
				return
			if down.has(pitch):
				down[pitch].note_off(pitch, 0)
			plugin.note_on(pitch, velocity, 0)
			down[pitch] = plugin
			_held[from] = down
		Session.Note.OFF:
			if down.has(pitch):
				down[pitch].note_off(pitch, 0)
				down.erase(pitch)
				if down.is_empty():
					_rest(from)
		Session.Note.PEDAL_DOWN, Session.Note.PEDAL_UP:
			var plugin = DAW.track_instrument(int(Session.play_tracks.get(from, 0)))
			if plugin != null:
				plugin.control(64, 127 if kind == Session.Note.PEDAL_DOWN else 0, 0)


func _on_control(kind: int, value: int, from: int, _song := -1.0, source := &"") -> void:
	if Session.role != Session.Role.HOST or from == Session.local_peer_id or source != &"":
		return
	var plugin = DAW.track_instrument(int(Session.play_tracks.get(from, 0)))
	if plugin == null:
		return
	_apply(plugin, kind, value)
	var moved: Dictionary = _moved.get(from, {})
	moved[kind] = plugin
	_moved[from] = moved


## As GuestMidi._sound_control sounds a control on the track's plugin.
func _apply(plugin: Object, kind: int, value: int) -> void:
	if kind != DawKitClip.PITCH_BEND:
		plugin.control(kind, value, 0)
	elif plugin.has_method(&"pitch_bend"):
		plugin.pitch_bend(value)


## Every control `peer` moved, back where an untouched keyboard has it.
func _rest(peer: int) -> void:
	var moved: Dictionary = _moved.get(peer, {})
	for kind: int in moved:
		_apply(moved[kind], kind, Session.control_rest(kind))
	_moved.erase(peer)


## A guest moved their keys to another track, or left: what they held is let go where it sounds.
func _on_track(peer: int, _track: int) -> void:
	_release(peer)


func _release(peer: int) -> void:
	_rest(peer)
	var down: Dictionary = _held.get(peer, {})
	for pitch: int in down:
		down[pitch].note_off(pitch, 0)
	_held.erase(peer)


func release_all() -> void:
	for peer: int in _held.keys():
		_release(peer)


## How many keys of `peer`'s sound now.
func held_count(peer: int) -> int:
	return (_held.get(peer, {}) as Dictionary).size()


## How many controls of `peer`'s are off rest on a plugin now.
func moved_count(peer: int) -> int:
	return (_moved.get(peer, {}) as Dictionary).size()
