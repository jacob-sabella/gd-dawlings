class_name FingertipNotes
extends Node

## Your fingertips are notes (docs/spatial_loop.md slice 8; idea #36): with them on, thumb to
## index plays the song's chord's root, to the middle its third, to the ring its fifth and to the
## little finger its top, voiced at centre 60 (`Harmony.voiced`), held as long as the pinch.
##
## One per local hand (`hand`, an Interactor), read through the hand's readings, so a bare hand,
## a controller and the desktop's keys play the same way: a bare hand's pinches, a controller's
## trigger, grip, A/X and B/Y, and on a desktop J K L ; (MouseInteractor.finger_pinches, from the
## fingertips' KeyCatcher).
##
## On and off. A bare hand or a controller turns them on by being held empty and open, palm up,
## nothing pinched and not toward the eyes, for HOLD seconds, and off by the same again: a
## controller is turned palm up a quarter outward (XRInteractor.palm_up). They play with the palm
## down or on its side, like an air piano, and a pinch made while the palm is up or faces the
## head (HandPose.faces_head) plays nothing: that is Quest's own menu pinch, which the runtime
## takes whatever the app wants, so playing never opens it and it never plays. On a desktop the
## fingertips are on while their KeyCatcher (`catcher`) has the keyboard: T gives it, and a click
## anywhere, Esc or T again takes it, so the keys and the mouse's grab go back together.
##
## While on, the hand's `fingers_play` is set (it grabs nothing: its pinches are notes) and
## `&"fingertips"` is in GuestMidi.instruments, so the synth is up before the first note and a
## run of notes is one take. The notes are the player's keys (`keys`), with source SOURCE: heard
## at once, sent to everyone and taken down on the armed track. The chord is read at the pinch's
## own stamp, the one song position its note is pitched by, recorded at and sent with, so a held
## note keeps its pitch through a chord change and the next pinch takes the new chord.
##
## How hard: from how fast the pinch closed (`Interactor.finger_travel`: a bare hand's gap to the
## thumb, a controller's trigger or grip travel), KEY_VELOCITY where there is nothing to read (a
## button, a key).
##
## Bent by the hand itself (docs/spatial_loop.md part two, slice 15): tipped from where its first
## note began, its roll bends what its fingers hold and its shake wobbles it (`wobble`); on a
## desktop the mouse's wiggle and Alt with the mouse moving up or down. A held finger's letter
## says by how much (Glove.bent: `E4 +1.3`).
##
## Shown, not coloured: the hand's fingertips are lettered with the notes they play and the chord
## over the palm (Interactor.finger_names, finger_chord, drawn on the mouse's glove; and the
## tracked hand's HandSkeleton, `skeleton`). A controller's hand is not drawn, and turning it over
## by chance takes its trigger's grab away, so over a controller playing them a row of its fingers'
## notes rides it, the chord over them and how to get the grab back under them (`pad_letters`),
## and the rig takes its pinch ray away while it plays (XRRig._show_hands): a ray that grabs
## nothing is not drawn as if it did.

## What these notes say they came from (Session.send_note's `source`, GuestMidi.instruments).
const SOURCE := &"fingertips"
const GROUP := &"fingertip_notes"
## How long the hand is held open and palm up to turn the notes on or off (s).
const HOLD := 0.4
## The pitch the chord is voiced round: C4 (Harmony.voiced).
const CENTRE := 60
## How hard a pinch plays with no travel to read it by: a key, or a controller's button.
const KEY_VELOCITY := 96
## The softest and hardest a pinch plays, and the closing speed (travel a second) that is hardest.
const SOFTEST := 30
const HARDEST := 127
const FULL_SPEED := 10.0
## How far back a pinch's closing speed is measured over (s).
const SPEED_WINDOW := 0.06
## Over a controller playing them (m): its fingers' notes in a row across the view, PAD_SPREAD
## apart and PAD_ABOVE over it, low to high left to right; the chord over them, and under them
## PAD_HINT, the way back to the trigger's grab.
const PAD_ABOVE := 0.075
const PAD_SPREAD := 0.03
const PAD_CHORD_ABOVE := 0.11
const PAD_HINT_ABOVE := 0.045
const PAD_HINT := "palm up 0.4 s: grab again"

## The hand these fingertips are: its readings, and its `fingers_play`.
var hand: Interactor
## Where the notes are played: this player's keys. Session.guest_midi unless told otherwise.
var keys: GuestMidi = null
## On a desktop, the fingertips' keys: the notes are on while it has the keyboard.
var catcher: KeyCatcher = null
## A tracked hand's drawing, to letter its fingertips; null for none.
var skeleton: HandSkeleton = null
## This hand's bend and wobble on what its fingers hold (Wobble): made at its first frame on.
var wobble: Wobble = null

## Whether the fingertips play now.
var on := false
## Finger (0 index .. 3 little) -> the pitch it has down.
var _notes := {}
## The fingers pinched last frame, as a mask.
var _was := 0
## When this hand last pinched a note, in pinches on any hand here (`_pinches`): the newest bends.
var _pinch_order := 0
static var _pinches := 0
## How long the hand has been held in the turning pose, and whether this hold has turned it yet:
## one turn a hold, so a hand left palm up does not flicker on and off.
var _held_for := 0.0
var _turned := false
## The time on this hand's own clock, and [time, travel] for the last SPEED_WINDOW of frames.
var _clock := 0.0
var _trail: Array = []
## The controller's lettering (`_letter_pad`): made at its first, riding it top level, turned to
## the head; hidden while off.
var _pad: Node3D = null
var _pad_letters: Array[Label3D] = []
var _pad_chord: Label3D
var _pad_hint: Label3D


func _ready() -> void:
	if keys == null:
		keys = Session.guest_midi
	if catcher != null:
		# The keys are read as they come, not a physics frame later; and the focus going (a click,
		# Esc) turns the fingers off before the mouse's next frame can grab with that click.
		catcher.note_on.connect(func(_finger: int, _velocity: int) -> void: step(0.0))
		catcher.note_off.connect(func(_finger: int) -> void: step(0.0))
		catcher.active_changed.connect(func(_active: bool) -> void: step(0.0))


func _enter_tree() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	set_on(false)
	if _pad != null and is_instance_valid(_pad):
		_pad.queue_free()
	_pad = null


func _physics_process(delta: float) -> void:
	step(delta)


## One frame of the hand, `delta` seconds on: turned on or off, its pinches played or let go, and
## its fingers lettered.
func step(delta: float) -> void:
	if hand == null or not is_instance_valid(hand):
		set_on(false)
		return
	_clock += delta
	var travel := hand.finger_travel()
	_trail.append([_clock, travel])
	while _trail.size() > 2 and _clock - float(_trail[0][0]) > SPEED_WINDOW:
		_trail.pop_front()
	var mask := hand.finger_pinches()
	if catcher != null:
		set_on(catcher.is_active())
	else:
		_watch_turn(delta, mask)
	if on:
		_play(mask)
		_bend(delta)
	elif wobble != null:
		wobble.hand = null
	_was = mask
	_letter(mask)


## The hand, one frame on, bending what its fingers hold, while they hold something and no
## other hand's fingertips here pinched since (the wheel is one, and both hands' notes are SOURCE):
## the newest pinch's hand bends, as the newest note owns the wheel. Not bending, it is let go,
## and measures again from its next note.
func _bend(delta: float) -> void:
	if keys == null:
		return
	if wobble == null:
		wobble = Wobble.new(keys, [SOURCE])
	wobble.keys = keys
	if _notes.is_empty() or _pinched_since():
		wobble.hand = null
		return
	wobble.hand = hand
	wobble.step(delta)


## Whether another hand's fingertips on these keys have a note down from a pinch newer than this
## hand's newest.
func _pinched_since() -> bool:
	if not is_inside_tree():
		return false
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as FingertipNotes
		if other != null and other != self and other.keys == keys and not other._notes.is_empty() \
				and other._pinch_order > _pinch_order:
			return true
	return false


## The turning pose (an empty open hand, palm up, unpinched, not toward the eyes) held for HOLD
## turns the notes on or off, once a hold.
func _watch_turn(delta: float, mask: int) -> void:
	var empty := not is_instance_valid(hand.carrying) and hand.held == null
	if empty and mask == 0 and hand.hand_open() and hand.palm_up() and not hand.faces_head():
		_held_for += delta
		if _held_for >= HOLD and not _turned:
			_turned = true
			set_on(not on)
	else:
		_held_for = 0.0
		_turned = false


## Turn the fingertips on or off. Off lets go of every note they have down.
func set_on(play: bool) -> void:
	if play == on:
		return
	on = play
	if not on:
		for finger in _notes.keys():
			_stop(finger)
	if hand != null and is_instance_valid(hand):
		hand.fingers_play = on
		if not on:
			hand.finger_names = PackedStringArray()
			hand.finger_chord = ""
	if skeleton != null and is_instance_valid(skeleton) and not on:
		skeleton.letter(PackedStringArray(), "")
	if _pad != null and is_instance_valid(_pad) and not on:
		_pad.visible = false
	_reach()


## `&"fingertips"` in the keys' reach while any hand's fingertips here are on: each hand turns
## its own on and off, and the name is one.
func _reach() -> void:
	if keys == null or not is_instance_valid(keys):
		return
	var any := on
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(GROUP):
			var other := node as FingertipNotes
			any = any or (other != null and other.on and other.keys == keys)
	keys.reach(SOURCE, any)


## A pinch closed this frame plays its finger's tone, unless the palm is up or faces the head; one
## opened lets go of what its finger had down.
func _play(mask: int) -> void:
	var allowed := not hand.palm_up() and not hand.faces_head()
	for f in HandPose.FINGER_BITS.size():
		var bit: int = HandPose.FINGER_BITS[f]
		if mask & bit and not _was & bit:
			if allowed:
				_start(f)
		elif not mask & bit and _notes.has(f):
			_stop(f)


## [the song position a note played now takes, and whether the song is playing to it], from one
## read of the keys' clock, as the harp reads it (ChordHarp._moment).
func _moment() -> Array:
	var song := keys.song() if keys != null else -1.0
	if song >= 0.0:
		return [song, true]
	return [DAW.state.position_seconds if DAW.state != null else 0.0, false]


## The four tones the fingers play at `seconds`, index to little: root, third, fifth, top.
static func tones_at(seconds: float) -> PackedInt32Array:
	return Harmony.voiced(Harmony.at(DAW.state, seconds), CENTRE, HandPose.FINGER_BITS.size())


func _start(f: int) -> void:
	if keys == null:
		return
	var moment := _moment()
	var seconds: float = moment[0]
	var pitch: int = tones_at(seconds)[f]
	var sounding := _sounding(pitch)
	_notes[f] = pitch
	_pinches += 1
	_pinch_order = _pinches
	# A pitch another finger here already has down (after a chord change, or the other hand's) is
	# one note: it sounds until the last finger on it lets go.
	if not sounding:
		keys.note_on(pitch, velocity_of(f), 0, 0.0, false, SOURCE, seconds if moment[1] else NAN)


func _stop(f: int) -> void:
	var pitch: int = _notes.get(f, -1)
	_notes.erase(f)
	if pitch < 0 or keys == null or _sounding(pitch):
		return
	keys.note_off(pitch, 0, 0.0, false, SOURCE)


## Whether any finger, on any hand here playing these keys, has `pitch` down.
func _sounding(pitch: int) -> bool:
	if pitch in _notes.values():
		return true
	if not is_inside_tree():
		return false
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as FingertipNotes
		if other != null and other != self and other.keys == keys and pitch in other._notes.values():
			return true
	return false


## How hard finger `f`'s pinch, closing now, plays: from how fast its travel rose over the last
## SPEED_WINDOW, KEY_VELOCITY with none to read.
func velocity_of(f: int) -> int:
	if _trail.size() < 2:
		return KEY_VELOCITY
	var first: Array = _trail[0]
	var last: Array = _trail[-1]
	var was: PackedFloat32Array = first[1]
	var now: PackedFloat32Array = last[1]
	var span := float(last[0]) - float(first[0])
	if was.size() <= f or now.size() <= f or is_nan(was[f]) or is_nan(now[f]) or span <= 0.0:
		return KEY_VELOCITY
	return velocity_for((now[f] - was[f]) / span)


## How hard a pinch closing at `speed` (travel a second) plays.
static func velocity_for(speed: float) -> int:
	return roundi(lerpf(SOFTEST, HARDEST, clampf(speed / FULL_SPEED, 0.0, 1.0)))


## What each finger plays now, index to little, in words: the note it has down, or the one it
## would play, at the keys' clock.
func names() -> PackedStringArray:
	var h := Harmony.at(DAW.state, _moment()[0])
	var now := Harmony.voiced(h, CENTRE, HandPose.FINGER_BITS.size())
	var out := PackedStringArray()
	for f in now.size():
		out.append(h.note_name(int(_notes.get(f, now[f]))))
	return out


## The chord the fingers are in, in words: NO KEY SET with no bracket to say one.
func chord_name() -> String:
	var h := Harmony.at(DAW.state, _moment()[0])
	return h.chord_name if h.named else "NO KEY SET"


func _letter(mask: int) -> void:
	if not on:
		return
	var said := names()
	var chord := chord_name()
	if wobble != null and wobble.engaged():
		for f in said.size():
			if _notes.has(f):
				said[f] = Glove.bent(said[f], wobble.semitones)
	hand.finger_names = said
	hand.finger_chord = chord
	if skeleton != null and is_instance_valid(skeleton):
		skeleton.letter(said, chord, mask)
	_letter_pad(said, chord, mask)


## The controller this hand is, while it is one: null for a bare hand, whose HandSkeleton is
## lettered instead, and for a mouse, whose glove is.
func _controller() -> XRController3D:
	var xr := hand as XRInteractor
	if xr == null or xr.controller == null or not is_instance_valid(xr.controller) \
			or not xr.controller.is_inside_tree() or xr.bare_hand():
		return null
	if xr.gestures != null and is_instance_valid(xr.gestures) and xr.gestures.tracked:
		return null
	return xr.controller


## Letter the controller this hand is (`_controller`) with what its fingers play, a pinched one
## grown as on the glove; hidden for a hand that is not one.
func _letter_pad(said: PackedStringArray, chord: String, mask: int) -> void:
	var controller := _controller()
	if controller == null:
		if _pad != null and is_instance_valid(_pad):
			_pad.visible = false
		return
	if _pad == null or not is_instance_valid(_pad) or _pad.get_parent() != controller:
		if _pad != null and is_instance_valid(_pad):
			_pad.queue_free()
		_make_pad(controller)
	_pad.visible = true
	var at := controller.global_position
	var away := at - hand.head_point()
	away.y = 0.0
	# Its row across the view from the head, level; a controller right under the eyes faces -Z.
	var facing := Basis.looking_at(away) if away.length() > 0.05 else Basis.IDENTITY
	_pad.global_transform = Transform3D(facing, at)
	for f in _pad_letters.size():
		var l := _pad_letters[f]
		l.visible = f < said.size() and said[f] != ""
		if l.visible:
			l.text = said[f]
		l.scale = Vector3.ONE * (Glove.PINCHED_GROWS if mask & HandPose.FINGER_BITS[f] else 1.0)
	_pad_chord.visible = chord != ""
	_pad_chord.text = chord


func _make_pad(controller: XRController3D) -> void:
	_pad = Node3D.new()
	_pad.name = "FingertipLetters"
	# Its own frame: it rides the controller's place, not its roll, so the row stays level.
	_pad.top_level = true
	controller.add_child(_pad)
	_pad_letters.clear()
	var count := HandPose.FINGER_BITS.size()
	for f in count:
		var l := HandSkeleton.letter_label(48)
		l.position = Vector3((f - (count - 1) * 0.5) * PAD_SPREAD, PAD_ABOVE, 0.0)
		_pad.add_child(l)
		_pad_letters.append(l)
	_pad_chord = HandSkeleton.letter_label(64)
	_pad_chord.position = Vector3(0.0, PAD_CHORD_ABOVE, 0.0)
	_pad.add_child(_pad_chord)
	_pad_hint = HandSkeleton.letter_label(40)
	_pad_hint.position = Vector3(0.0, PAD_HINT_ABOVE, 0.0)
	_pad_hint.text = PAD_HINT
	_pad_hint.visible = true
	_pad.add_child(_pad_hint)


## What the controller's lettering shows now: each finger's note, index to little ("" for one
## hidden), then the chord and the way back to grabbing; empty while it is not shown. For the suite.
func pad_letters() -> PackedStringArray:
	var out := PackedStringArray()
	if _pad == null or not is_instance_valid(_pad) or not _pad.visible or not _pad.is_inside_tree():
		return out
	for l in _pad_letters:
		out.append(l.text if l.visible else "")
	out.append(_pad_chord.text if _pad_chord.visible else "")
	out.append(_pad_hint.text if _pad_hint.visible else "")
	return out
