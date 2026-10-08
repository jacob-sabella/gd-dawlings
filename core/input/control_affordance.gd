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
## Somebody ELSE in the session has their hand on this -- on their own copy of it, in their own
## room. Set from outside (core/session/presence.gd), from the host's table of who holds what,
## and refused like a second local hand. Not `held_by`: a local hold also stops the control
## listening to the mix, and a fader somebody else is moving must keep moving under your eyes.
var claimed_by: Object = null

## How long after a hand lets go the control keeps its own value against older echoes.
##
## A guest's fader writes go to the host and come back, and the replies still in flight at the
## moment of release describe where the fader WAS -- so a released fader jumped back down its
## travel and then up again as the queue drained, which reads as the desk refusing the move.
## For this long, an echo that is not the value the hand left is held back; the one that is
## ends the wait early; and when the wait runs out the newest held-back value is applied, so a
## mix that really did settle somewhere else (Reaper clamps, quantises) still has the last word.
const SETTLE_MSEC := 450

var _settle_until := 0
var _settle_value := 0.0
var _settle_pending := NAN


const GROUP := &"controls"


func _enter_tree() -> void:
	add_to_group(GROUP)


func is_held() -> bool:
	return held_by != null


## The name this control goes by across the session: how one participant's "I am holding
## this" is matched to the same control on everyone else's desk. Stable across machines by
## construction, because it is what the control SAYS it is -- "KICK  VOLUME" -- and not where it
## sits in a scene tree that each participant has arranged differently. Override where the
## title is about the pointer rather than the control.
func network_key() -> String:
	return title()


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
	if claimed_by != null:
		return
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
	_hold_against_echoes()
	grab_ended.emit(by)
	value_committed.emit(value)


## Reaper says this control is now at `v`. Honoured unless a hand is on it.
func apply_remote(v: float) -> void:
	if is_held():
		return
	if Time.get_ticks_msec() < _settle_until:
		if absf(v - _settle_value) < 0.0005:
			_settle_until = 0
			_settle_pending = NAN
		else:
			_settle_pending = v
			return
	value = v
	_on_value_changed()


## Take `v` now, past the echo wait: for when the control has been pointed at a different
## value altogether (a strip flipped to show a send), so what it was waiting for is moot.
func snap_to(v: float) -> void:
	if is_held():
		return
	_settle_until = 0
	_settle_pending = NAN
	apply_remote(v)


func is_settling() -> bool:
	return Time.get_ticks_msec() < _settle_until


func _hold_against_echoes() -> void:
	_settle_value = value
	_settle_pending = NAN
	_settle_until = Time.get_ticks_msec() + SETTLE_MSEC
	if is_inside_tree():
		get_tree().create_timer(SETTLE_MSEC / 1000.0 + 0.01).timeout.connect(_echo_wait_over)


func _echo_wait_over() -> void:
	if not is_instance_valid(self) or is_held() or is_settling():
		return
	if not is_nan(_settle_pending):
		var v := _settle_pending
		_settle_pending = NAN
		apply_remote(v)


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


# --- nudging ---------------------------------------------------------------------------------

## A relative adjustment with no position: a scroll-wheel notch, a thumbstick flick.
##
## The mouse's best gesture and the one this contract was missing. Over a knob in any DAW the
## wheel turns the knob; here it zoomed the camera, which is the kind of thing that makes
## a person stop trusting the wheel at all. It is a member of the contract, not a mouse path
## beside it, for the reason dwell is: it is another way to say "set this", to the same control,
## and a headset's thumbstick says it too.
##
## Returns whether the control took it. A button has no "a bit more", and the wheel should go on
## meaning zoom over one rather than doing nothing.
##
## Refused while someone ELSE holds the control, for the same reason a second grab is: their
## hand is the value until they let go.
func nudge(by: Node, notches: int, fine: bool) -> bool:
	if notches == 0 or claimed_by != null or (held_by != null and held_by != by):
		return false
	if not _on_nudge(notches, fine):
		return false
	_hold_against_echoes()
	# A nudge is a whole gesture, so it commits like the end of one. Whatever records history
	# listens to this, and a wheel turn that it never heard of would be a change nobody can undo.
	value_committed.emit(value)
	return true


## Override to accept nudges. Move `value`, write it wherever a drag would, return true.
func _on_nudge(_notches: int, _fine: bool) -> bool:
	return false


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
