class_name ModularTake
extends RefCounted

## A take played through the modular wall, kept as what was played rather than as sound
## (docs/spatial_loop.md part two, slice 52; idea #25): the patch as it stood when the take began,
## and every event after it with the song position it was made at. The notes and the wheel of the
## player's keys, the knobs as they were streamed (whoever turned them), and the cables put in and
## pulled out (the room's verbs). Its sound is `render`: Modular.render of the starting patch and
## the events from the take's start for its span, so a sweep lands where it was turned, not where
## it reached anyone, and the same take renders the same samples on every machine that holds it.
##
## The player keeps one of their own as they play (ModularTakes.mine), and the host keeps one for
## each player recording through the modular from what reaches it, reliable and stamped: the notes
## on Session.KEYS_CHANNEL, the knobs on Session.GESTURE_CHANNEL and the cables as the room's asks.
## When the take ends the host renders its own and places the WAV (`write`), so no file is ever sent.
##
## The world's sockets (slice 53) are in it too: once the take has ended, what the world played into
## them over its span (ModularWorld.for_take, worked out from the song clock and the rows, the same
## on every machine) is put in beside what was played (`hear_world`), once.
##
## A wheel at rest is part of the take as it is of GuestMidi's: at the player's last note-off every
## end puts the bend back to the centre itself (`note`), so no reset has to arrive.

## Events stamped with no song position (-1: the song was not playing) are not the take's: there
## is nowhere on the timeline to put them.
const NO_SONG := 0.0

## The song position the take begins at, and the furthest it has reached.
var start := 0.0
var end := 0.0
## The patch as it stood at `start` ({cables, knobs}, Modular.clean).
var patch := Modular.default_patch()
## Render's events, [song, Modular.Event, a, b], in the order they reached this take.
var events: Array = []
## Its keys held now, {pitch: true}: the last let go rests the wheel.
var _held := {}
## Where the wheel stands in it now: a bend to where it is already is not kept.
var _bend := 0
## Whether the world's events are in it yet.
var _world := false


## Begun at song position `at` with the patch as it stands (`from`), and the keys `held` down
## already ({pitch: velocity}) sounding from its first moment.
func begin(from: Dictionary, at: float, held := {}) -> ModularTake:
	start = maxf(at, 0.0)
	end = start
	patch = Modular.clean(from)
	events.clear()
	_held.clear()
	_bend = 0
	_world = false
	var pitches: Array = held.keys()
	pitches.sort()
	for pitch: int in pitches:
		note(Session.Note.ON, pitch, int(held[pitch]), start)
	return self


## The take has heard this far.
func reach(at: float) -> void:
	if is_finite(at) and at > end:
		end = at


## A note on or off (Session.Note's ON, OFF) of the player's keys at song position `song`. The
## last held let go puts the wheel back to rest there, as GuestMidi does on every end.
func note(kind: int, pitch: int, velocity: int, song: float) -> void:
	if not _stamped(song):
		return
	if kind == Session.Note.ON:
		_held[pitch] = true
		events.append([song, Modular.Event.ON, clampi(pitch, 0, 127), clampi(velocity, 1, 127)])
	elif kind == Session.Note.OFF:
		events.append([song, Modular.Event.OFF, clampi(pitch, 0, 127), 0])
		if _held.erase(pitch) and _held.is_empty():
			events.append([song, Modular.Event.BEND, 0, 0])
			_bend = 0
	reach(song)


## The pitch wheel, -8192 to 8191, at `song`. Whether it was kept: a move, not the wheel's resend
## of where it stands (GuestMidi sends that again every CONTROL_EVERY), so the player's take and
## the host's, fed the same moves in the same order, keep the same events.
func bend(value: int, song: float) -> bool:
	value = clampi(value, -8192, 8191)
	if not _stamped(song) or value == _bend:
		return false
	_bend = value
	events.append([song, Modular.Event.BEND, value, 0])
	return true


## Knob `id` at `v` at `song`: a turn as it was streamed, or one let go.
func knob(id: StringName, v: float, song: float) -> void:
	if _stamped(song) and Modular.KNOBS.has(id) and is_finite(v):
		events.append([song, Modular.Event.KNOB, id, clampf(v, 0.0, 1.0)])


## A cable from `from` into `to`, or with `to` empty the cable at `from` pulled, at `song`.
func cable(from: StringName, to: StringName, song: float) -> void:
	if _stamped(song):
		events.append([song, Modular.Event.PATCH, from, to])


## What the world played into the modular's sockets over the take (ModularWorld.for_take: WORLD and
## TRIG events, each with its song), put in once: a second call changes nothing.
func hear_world(list: Array) -> void:
	if _world:
		return
	_world = true
	for e: Variant in list:
		if e is Array and (e as Array).size() == 4 and int(e[1]) in [Modular.Event.WORLD, Modular.Event.TRIG] \
				and Modular.is_world(StringName(e[2])) and _stamped(float(e[0])):
			events.append([float(e[0]), int(e[1]), StringName(e[2]), float(e[3])])


## Whether the world's events are in it.
func heard_world() -> bool:
	return _world


func _stamped(song: float) -> bool:
	return is_finite(song) and song >= NO_SONG


## How many frames of sound the take is: its span at Modular.RATE.
func frames() -> int:
	return maxi(roundi((end - start) * Modular.RATE), 0)


func seconds() -> float:
	return float(frames()) / Modular.RATE


## Whether any note was played into it: a take of knobs alone is silence, and not placed.
func has_notes() -> bool:
	return events.any(func(e: Array) -> bool: return int(e[1]) == Modular.Event.ON)


## The take's sound, mono at Modular.RATE, from `start` for its span: the starting patch and every
## event (those stamped before `start` at its first block). Pure: the same take, the same samples.
func render() -> PackedFloat32Array:
	return Modular.render(patch, events, start, frames())


## The take's sound as 16-bit mono (AudioTake's), from `render`'s samples.
static func pcm(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size() * 2)
	for i in samples.size():
		out.encode_s16(i * 2, int(round(clampf(samples[i], -1.0, 1.0) * 32767.0)))
	return out


## The take's sound written as a WAV in the project's media folder (AudioTake.DIR) under
## `file_name`, finished, or null if the file cannot be made. `samples`: the render, if it has been
## made already (on a worker thread, ModularTakes).
func write(file_name: String, samples := PackedFloat32Array()) -> AudioTake:
	var sound := samples if samples.size() == frames() else render()
	var take := AudioTake.create(file_name)
	if take == null:
		return null
	take.append(pcm(sound))
	take.finish()
	return take
