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
func grab_begin(by: Node, at: Vector3) -> void:
	if held_by != null and held_by != by:
		# Two people reaching for one fader. First hand wins and the second is simply told no,
		# rather than the two averaging into a value neither person asked for.
		return
	held_by = by
	_on_grab_begin(at)
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


func _on_grab_begin(_at: Vector3) -> void: pass
func _on_grab_move(_at: Vector3) -> void: pass
func _on_grab_end() -> void: pass
func _on_value_changed() -> void: pass
