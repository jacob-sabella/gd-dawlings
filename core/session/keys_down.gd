class_name KeysDown
extends RefCounted

## The pitches one player has down, counted by what is holding each: their keys can be played
## by several instruments at once (GuestMidi.instruments), and two of them can hold the same
## pitch. A pitch is up only when the last of them lets it go, so a harp's A4 dying away does not
## stop a fingertip's A4 still held. Wherever a player's notes are sounded on one synth -- their
## own monitor (GuestMidi), a plug in their keys (TheirKeys) or in their monitor (TheirMonitor) --
## a note-off is sounded only when `let_go` says the pitch is up.
##
## A source is the instrument's name (`&"harp"`), `&""` for plain keys.

## {pitch: {source: velocity}}
var _by := {}


## `source` put `pitch` down.
func press(pitch: int, source: StringName, velocity := 100) -> void:
	if not _by.has(pitch):
		_by[pitch] = {}
	# Taken out and put back, so the latest to put it down is last.
	_by[pitch].erase(source)
	_by[pitch][source] = velocity


## `source` let `pitch` go: whether the pitch is up now, so its note-off is to be sounded. A
## pitch nobody held is up already, and its note-off is sounded as one always was; one still held
## by something else is not.
func let_go(pitch: int, source: StringName) -> bool:
	var by: Dictionary = _by.get(pitch, {})
	by.erase(source)
	if by.is_empty():
		_by.erase(pitch)
		return true
	return false


## Whether `source` has `pitch` down.
func holds(pitch: int, source: StringName) -> bool:
	return _by.has(pitch) and (_by[pitch] as Dictionary).has(source)


## Whether anything has `pitch` down.
func is_down(pitch: int) -> bool:
	return _by.has(pitch)


## What has `pitch` down, the latest to put it down last.
func sources_of(pitch: int) -> Array:
	return (_by.get(pitch, {}) as Dictionary).keys()


## The pitches `source` has down.
func held_by(source: StringName) -> Array:
	var out: Array = []
	for pitch in _by:
		if (_by[pitch] as Dictionary).has(source):
			out.append(pitch)
	return out


## Every pitch down: {pitch: velocity}, the latest velocity it went down at.
func pitches() -> Dictionary:
	var out := {}
	for pitch in _by:
		var by: Dictionary = _by[pitch]
		out[pitch] = by[by.keys()[-1]]
	return out


func clear() -> void:
	_by.clear()
