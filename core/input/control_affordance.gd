class_name ControlAffordance
extends StaticBody3D

## Anything a hand or a cursor can take hold of: a fader cap, a knob, a button, a patch point.
##
## One contract for every input medium. A mouse ray, a tracked controller and a pinching hand all
## arrive here as the same three calls, which is the only reason the console works identically on
## a monitor and in passthrough. The temptation to give the mouse its own path -- because a mouse
## has a scroll wheel and a hand does not -- is what ends with two divergent control sets.
##
## GRABBED VALUES ARE PROVISIONAL. While held, a control shows the HAND's value and writes it to
## Reaper, and it ignores what Reaper echoes back about itself. On release it stops ignoring and
## snaps to whatever Reaper actually settled on. That gap is not a bug to hide: Reaper may clamp
## or quantise a value, and the fader should end up where the mix really is rather than where the
## hand left it.

signal grab_started(by: Node)
signal grab_ended(by: Node)
signal value_committed(value: float)

## 0..1 in the control's own terms, whatever it drives.
@export var value: float = 0.0

var held_by: Node = null


func is_held() -> bool:
	return held_by != null


## `at` is the contact point in global space -- the ray hit, or the fingertip.
## Can this control be worked by looking at it, without a press?
##
## False by default, and the default is the careful one. Dwell is the alternative to a press for
## anyone who cannot hold a trigger steady, cannot pinch, or is working one-handed with a cable
## in the other -- but it fires from ATTENTION, and attention lands on things by accident all
## the time. A momentary button that gets dwelt on fires a command the person can undo; a fader
## that gets dwelt on takes a mix somewhere they did not ask for and cannot easily get back.
## So controls opt in, and only the ones where a mistaken activation is cheap do.
func dwell_activates() -> bool:
	return false


## How far through its dwell this control is, 0 to 1. Override to show it.
##
## Not optional in practice. A timer that fires with no indication of how long is left is the
## interaction equivalent of an unlabelled button: the first thing anyone does is look away in
## case it goes off, which defeats the mechanism.
func set_dwell_progress(_fraction: float) -> void:
	pass


func grab_begin(by: Node, at: Vector3) -> void:
	if held_by != null and held_by != by:
		# Two people reaching for one fader. First hand wins and the second is simply told no,
		# rather than the two averaging into a value neither person asked for.
		return
	held_by = by
	_on_grab_begin(at)
	# After the handler, so a control whose sound depends on where it was grabbed has been told
	# where that was. Before the signal, because the signal is what the rest of the scene reacts
	# to and the noise the object makes should not arrive after its consequences.
	Foley.play(self, _foley_contact(), contact_volume_db)
	grab_started.emit(by)


func grab_move(by: Node, at: Vector3) -> void:
	if held_by != by:
		return
	_on_grab_move(at)


func grab_end(by: Node) -> void:
	if held_by != by:
		return
	_on_grab_end()
	held_by = null
	grab_ended.emit(by)
	value_committed.emit(value)


## Reaper says this control is now at `v`. Honoured unless a hand is on it.
func apply_remote(v: float) -> void:
	if is_held():
		return
	value = v
	_on_value_changed()


## What this control sounds like when a hand closes on it, or null for the ones that are silent.
##
## The MECHANISM lives here and the SOUND does not, which is the whole point: in a headset every
## control needs to be able to say "you have me" at the instant it is true, so no control should
## have to grow its own player to do it. But a fader cap does not click and a patch point does
## not tick, and a base class that invented a generic noise for everything would be worse than
## silence -- it would make four different objects feel like the same object.
func _foley_contact() -> AudioStream:
	return null


## Trimmed per control, because these are not equally loud in life. A button is the loudest thing
## on a desk and a knob detent is near the floor of what you can hear over a monitor mix.
var contact_volume_db: float = 0.0


# --- saying what it is ----------------------------------------------------------------------
#
# A hand on a fader knows it is on the fader. A cursor over one does not: it has no weight, no
# contact, nothing but a picture of an arrow on top of a picture of a desk. On a monitor the
# only way to know what you are about to move is for the thing to say so, and to say what it is
# set to in the units the mix is made of, not as a position.
#
# Set by whoever BUILDS the control, because that is what knows the meaning. A knob does not
# know it is the kick's pan; the strip that put it there does. The defaults are only what the
# control can say about itself without being told.

## () -> String. What this is: "KICK  PAN", "REACOMP  THRESHOLD".
var describe_title: Callable = Callable()
## (value: float) -> String. What it is set to, in its own units: "-4.2 dB", "L 30".
var describe_value: Callable = Callable()

var _hovered_by: Array[Node] = []

signal hover_changed(hovered: bool)


func title() -> String:
	if describe_title.is_valid():
		return describe_title.call()
	return _default_title()


func readout() -> String:
	if describe_value.is_valid():
		return describe_value.call(value)
	return _default_readout()


## What can be done to it, in words, for anyone who has not been told. Kept short: this sits
## under the value on the hover card and is read once, then ignored, which is the point.
func hint() -> String:
	return ""


func is_hovered() -> bool:
	return not _hovered_by.is_empty()


## Counted per interactor, not a flag. Two hands, or a hand and a cursor in a hybrid session,
## can rest on one control, and the first to leave must not switch the highlight off under
## the second.
func hover_enter(by: Node) -> void:
	if by in _hovered_by:
		return
	_hovered_by.append(by)
	if _hovered_by.size() == 1:
		hover_changed.emit(true)


func hover_exit(by: Node) -> void:
	if not by in _hovered_by:
		return
	_hovered_by.erase(by)
	if _hovered_by.is_empty():
		hover_changed.emit(false)


func _default_title() -> String:
	return String(name).to_upper()


func _default_readout() -> String:
	return "%d%%" % roundi(value * 100.0)


func _on_grab_begin(_at: Vector3) -> void: pass
func _on_grab_move(_at: Vector3) -> void: pass
func _on_grab_end() -> void: pass
func _on_value_changed() -> void: pass
