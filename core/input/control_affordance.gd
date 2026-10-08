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


func _on_grab_begin(_at: Vector3) -> void: pass
func _on_grab_move(_at: Vector3) -> void: pass
func _on_grab_end() -> void: pass
func _on_value_changed() -> void: pass
