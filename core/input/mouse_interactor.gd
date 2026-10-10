class_name MouseInteractor
extends Interactor

## The screen participant's hand: a ray from the camera through the cursor.
##
## This exists so that a monitor is not a second-class way to be in the session. The engineer at
## the desk with a mouse is driving the same ControlAffordance objects, through the same grab
## contract, as the person standing in the room pinching the same fader.

@export var camera: Camera3D

var _card: HoverCard
## A pointer position to use instead of the mouse, for captures. Negative is "use the mouse".
var pointer_override := Vector2(-1, -1)
## The left button, for captures: -1 reads the mouse, 0 is up, 1 is down. With the pointer
## override this lets a capture DRAG something through the same path a hand on the mouse does,
## rather than poking the control directly and photographing a result no person could produce.
var press_override := -1


func reach() -> float:
	return 12.0


func pointer() -> Vector2:
	if pointer_override.x >= 0.0:
		return pointer_override
	return camera.get_viewport().get_mouse_position()


func aim() -> Transform3D:
	if camera == null:
		return global_transform
	var mouse := pointer()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	return Transform3D(Basis.looking_at(direction, Vector3.UP), origin)


## What is under the cursor this moment, not as of the last physics tick: {"control", "point"}.
## A file dragged in from the desktop moves no cursor the game sees until it is let go.
func under_cursor() -> Dictionary:
	var at := aim()
	return _cast(at.origin, -at.basis.z)


## Low on the left of the view, under half a metre out: the left hand, since the cursor is the
## right. It rides with the camera, not the cursor, so it stays put while you point at things.
const CARRY_AT := Vector3(-0.19, -0.15, -0.5)
## Tipped toward you, the way you hold something up to look at it: level with the view, the palm
## is edge-on and whatever sits on it seems to float past the fingers.
const CARRY_TIP := 0.25


func carry_pose() -> Transform3D:
	if camera == null:
		return global_transform
	var view := camera.global_transform.orthonormalized()
	# Drawn back over the shoulder as a throw winds up, and tipped back with it.
	var wound := charge()
	var at := CARRY_AT + Vector3(0.04, 0.07, 0.16) * wound + _wiggle
	return Transform3D(view.basis * Basis(Vector3.RIGHT, CARRY_TIP - 0.6 * wound), view * at)


# --- shaking -------------------------------------------------------------------------------
#
# An instrument in the hand is shaken by moving the mouse: the hand follows the cursor's
# movement a little way and springs back, so a wiggle of the mouse is a shake of the shaker, and
# each stroke that stops is a hit (InstrumentItem). Only while an instrument is carried: a duck
# rides still while the cursor points at things.

## How far the hand moves for a pixel of the cursor's, and the most it moves (m).
const WIGGLE_PER_PIXEL := 0.0007
const WIGGLE_MOST := 0.07
## How quickly the hand comes back to its place once the mouse stops (s).
const WIGGLE_SETTLE := 0.09

var _wiggle := Vector3.ZERO
var _wiggle_anchor := Vector2(-1, -1)


func shake_point() -> Vector3:
	return _wiggle


## The hand's wiggle for where the cursor is now, `delta` seconds on.
func wiggle(at: Vector2, delta: float) -> void:
	if not (carrying is InstrumentItem):
		_wiggle = Vector3.ZERO
		_wiggle_anchor = Vector2(-1, -1)
		return
	if _wiggle_anchor.x < 0.0:
		_wiggle_anchor = at
	_wiggle_anchor = _wiggle_anchor.lerp(at, 1.0 - exp(-delta / WIGGLE_SETTLE))
	var d := (at - _wiggle_anchor) * WIGGLE_PER_PIXEL
	_wiggle = Vector3(clampf(d.x, -WIGGLE_MOST, WIGGLE_MOST), clampf(-d.y, -WIGGLE_MOST, WIGGLE_MOST), 0)


# --- throwing ------------------------------------------------------------------------------
#
# Hold R to wind up, let go to throw where the cursor is. The longer it is held, the harder the
# throw, up to CHARGE_SECONDS; a tap is a lob. The hand draws back as it winds up, so you can see
# how hard it is going to be.

const CHARGE_SECONDS := 0.9
## A tap's throw, and a full wind-up's (m/s). A lob lands a couple of metres off; a full throw
## crosses the live room.
const THROW_SLOWEST := 2.2
const THROW_FASTEST := 8.0
## Above the cursor, because a throw aimed straight at something falls short of it: about the
## lift a person gives a throw without thinking.
const LOFT := 0.16
## How fast it tumbles end over end, at a full throw (rad/s).
const TUMBLE := 11.0
## How near your head a throw has to come to be caught (m): about the reach of two hands put up.
const CATCH_REACH := 0.45

var _charge_from := -1


## Start winding up a throw, if this hand is carrying something.
func begin_throw() -> void:
	if carrying != null and is_instance_valid(carrying) and _charge_from < 0:
		_charge_from = Time.get_ticks_msec()


## How wound up the throw is, 0 to 1; 0 when there is none.
func charge() -> float:
	if _charge_from < 0:
		return 0.0
	return clampf((Time.get_ticks_msec() - _charge_from) / (CHARGE_SECONDS * 1000.0), 0.0, 1.0)


## Let go: thrown along the cursor's ray, a little above it, as hard as it was wound up.
func release_throw() -> void:
	if _charge_from < 0:
		return
	var wound := charge()
	_charge_from = -1
	throw_with(wound)


## A throw wound up to `wound` (0..1), along the cursor's ray.
func throw_with(wound: float) -> void:
	var a := aim()
	var toward := (a.basis * Basis(Vector3.RIGHT, LOFT)) * Vector3.FORWARD
	var speed := lerpf(THROW_SLOWEST, THROW_FASTEST, wound)
	var item := carrying as Item
	var room := ItemRoom.of(item)
	if item != null and room != null and item.aim_scatter(wound) >= 0.0:
		# Aimed: lobbed from the hand to land where the cursor is, give or take a wobble.
		var target := room.aim_point(a)
		var wobble := item.aim_scatter(wound)
		target += a.basis.x * randfn(0.0, wobble) + a.basis.y * randfn(0.0, wobble)
		throw_item(ItemRoom.lob(carry_pose().origin, target, lerpf(4.0, 9.0, wound)), Vector3.ZERO)
		return
	throw_item(toward * speed, a.basis.x * -TUMBLE * (0.3 + 0.7 * wound))


## A ball thrown at your face is caught, not walked through: a screen has no hand to put up,
## so the catch is round your head, a little ahead of it.
func catch_reach() -> float:
	return CATCH_REACH


func catch_point() -> Vector3:
	var head := camera.global_transform if camera != null else global_transform
	return head.origin - head.basis.z * 0.25 - head.basis.y * 0.1


func draws_own_hand() -> bool:
	return camera != null


func drag_reading() -> float:
	return pointer().y


func fine() -> bool:
	return Input.is_key_pressed(KEY_SHIFT)


## The wheel adjusts whatever the cursor is on, and only falls through to the camera when that
## is nothing adjustable. Handled here, before the studio sees it, because this is a child of
## the studio and children get input first -- which is the order wanted: the thing under the
## pointer has the stronger claim on what the wheel meant.
func _unhandled_input(event: InputEvent) -> void:
	var wheel := event as InputEventMouseButton
	if wheel == null or not wheel.pressed:
		return
	var notches := 0
	if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
		notches = 1
	elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		notches = -1
	if notches == 0:
		return
	var target: ControlAffordance = held if held != null else hovered
	if target != null and is_instance_valid(target) and target.nudge(self, notches, fine()):
		get_viewport().set_input_as_handled()


func is_pressing() -> bool:
	if press_override >= 0:
		return press_override == 1
	# A click on a panel is a click on the panel. Without this, pressing a button in the
	# session panel also grabbed whatever fader happened to be behind it in the room.
	if held == null and _over_gui():
		return false
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _over_gui() -> bool:
	var vp := get_viewport()
	return vp != null and vp.gui_get_hovered_control() != null


func _physics_process(delta: float) -> void:
	super(delta)
	if camera != null or pointer_override.x >= 0.0:
		wiggle(pointer(), delta)
	if _card == null:
		_card = HoverCard.new()
		_card.name = "HoverCard"
		add_child(_card)
	# Not while orbiting: the right button is moving the camera, the cursor is not pointing at
	# anything on purpose, and a card flickering across every control the view swings past is
	# noise at exactly the moment the person is trying to find their bearings.
	if camera == null or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_card.hide_card()
		return
	_forget_freed()
	_card.show_for(held if held != null else hovered, pointer())
