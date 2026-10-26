class_name MouseInteractor
extends Interactor

## The screen participant's hand: a ray from the camera through the cursor.
##
## This exists so that a monitor is not a second-class way to be in the session. The engineer at
## the desk with a mouse is driving the same ControlAffordance objects, through the same grab
## contract, as the person standing in the room pinching the same fader.

## P with nothing in this hand (docs/spatial_loop.md slice 6): for the studio, which steps this
## player's own keys' jack on (`unplug` false), or with Shift takes out every jack that goes into
## this player (`unplug` true).
signal bare_jack(unplug: bool)

@export var camera: Camera3D

var _card: HoverCard
## A pointer position to use instead of the mouse, for captures. Negative is "use the mouse".
var pointer_override := Vector2(-1, -1)
## The left button, for captures: -1 reads the mouse, 0 is up, 1 is down. With the pointer
## override this lets a capture DRAG something through the same path a hand on the mouse does,
## rather than poking the control directly and photographing a result no person could produce.
var press_override := -1
## The fingertips' keys (a KeyCatcher, J K L ;): the one reader of them. While it has the
## keyboard its keys down are this hand's pinches (`finger_pinches`), and the studio's
## FingertipNotes turns `fingers_play` on and off with its focus. This hand reads no keys for it.
var finger_source: KeyCatcher = null
## The button was down as the fingers stopped playing: it is not a press until it has come up,
## so the click that gave the keys back does not also grab what it landed on.
var _press_spent := false


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


## Low on the right of the view, the left's mirror: the right hand, which plays the fingertips
## while they are on (docs/spatial_loop.md slice 8). It rides with the camera and the wiggle.
## High enough that its fingertips' letters clear the bottom of the screen.
const FINGERS_AT := Vector3(0.2, -0.12, -0.5)
## The field of view FINGERS_AT is placed for (the room's, Studio.ROOM_FOV, degrees). Zoomed in
## with the wheel the view narrows, and the glove is drawn in toward the middle and smaller by as
## much (`view_scale`), so it stays where it was on the screen and the size it was, letters and
## all, rather than swelling off the bottom corner.
const FINGERS_FOV := 58.0
## Turned in toward the middle of the view, so it is seen from its side and its cuff does not
## hide its fingers, and tipped down at them, palm down: the back of the hand faces you.
const FINGERS_TURN := 0.35
const FINGERS_TIP := -1.0


func finger_pose() -> Transform3D:
	if camera == null:
		return global_transform
	var view := camera.global_transform.orthonormalized()
	var turned := view.basis * Basis(Vector3.UP, FINGERS_TURN) * Basis(Vector3.RIGHT, FINGERS_TIP)
	var k := view_scale()
	var at := FINGERS_AT + _wiggle
	return Transform3D(turned, view * Vector3(at.x * k, at.y * k, at.z))


func finger_glove_size() -> float:
	return super() * view_scale()


## How much smaller what rides the view is drawn at the camera's field of view than at
## FINGERS_FOV's: 1 there, under 1 zoomed in.
func view_scale() -> float:
	if camera == null or camera.fov <= 0.0:
		return 1.0
	return tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(FINGERS_FOV) * 0.5)


## The fingers stopped: a button down now is the click that stopped them, spent until it comes up.
func _fingers_stopped() -> void:
	_press_spent = true


## The fingertips' keys down, as fingers: J the index, K the middle, L the ring, ; the little.
func finger_pinches() -> int:
	if finger_source == null or not is_instance_valid(finger_source) or not finger_source.is_active():
		return 0
	var mask := 0
	for finger in finger_source.held():
		if int(finger) >= 0 and int(finger) < HandPose.FINGER_BITS.size():
			mask |= HandPose.FINGER_BITS[int(finger)]
	return mask


# --- shaking -------------------------------------------------------------------------------
#
# An instrument in the hand is shaken by moving the mouse: the hand follows the cursor's
# movement a little way and springs back, so a wiggle of the mouse is a shake of the shaker, and
# each stroke that stops is a hit (InstrumentItem). Only while an instrument (or the keytar) is
# carried, while the fingers play (docs/spatial_loop.md slice 7), or while the cursor rests on
# something that plays under it with no grab (the harp's strings, `plays_under_cursor`; part two,
# slice 15): a duck rides still while the cursor points at things. The wiggle is the desktop's
# tilt as well (`tilt`, `tilt_angles`), so a bend and a wobble read from a tipped hand in a
# headset are read from the mouse on a desk (Wobble).
#
# Alt with the mouse moving up or down is the desktop's pitch wheel (`bend_wheel`): BEND_PIXELS a
# semitone up or down, at most Wobble.BEND_MOST, springing back to the middle as Alt is let go.
# It bends whatever of this player's is sounding: the instrument's own Wobble adds it, and the
# plain keys (a MIDI keyboard, the computer's piano) have one of their own here (`_keys_wobble`).

## How far the hand moves for a pixel of the cursor's, and the most it moves (m).
const WIGGLE_PER_PIXEL := 0.0007
const WIGGLE_MOST := 0.07
## How quickly the hand comes back to its place once the mouse stops (s).
const WIGGLE_SETTLE := 0.09

var _wiggle := Vector3.ZERO
var _wiggle_anchor := Vector2(-1, -1)


func shake_point() -> Vector3:
	return _wiggle


## The wiggle over WIGGLE_MOST: right is rolled right, up is pitched up, the most of either a
## hand tipped HandPose.TILT_MOST.
func tilt() -> Vector2:
	return Vector2(_wiggle.x, _wiggle.y) / WIGGLE_MOST


## The same, in radians: WIGGLE_MOST is a hand tipped HandPose.TILT_MOST.
func tilt_angles() -> Vector2:
	return tilt() * deg_to_rad(HandPose.TILT_MOST)


## Whether the mouse's movement is a shake now: an instrument or the keytar carried, the fingers
## playing, or the cursor resting, ungrabbed, on something that plays under it.
func wiggles() -> bool:
	if carrying is InstrumentItem or carrying is KeytarItem or fingers_play:
		return true
	return held == null and hovered != null and is_instance_valid(hovered) and hovered.plays_under_cursor()


## The hand's wiggle for where the cursor is now, `delta` seconds on.
func wiggle(at: Vector2, delta: float) -> void:
	if not wiggles():
		_wiggle = Vector3.ZERO
		_wiggle_anchor = Vector2(-1, -1)
		return
	if _wiggle_anchor.x < 0.0:
		_wiggle_anchor = at
	_wiggle_anchor = _wiggle_anchor.lerp(at, 1.0 - exp(-delta / WIGGLE_SETTLE))
	var d := (at - _wiggle_anchor) * WIGGLE_PER_PIXEL
	_wiggle = Vector3(clampf(d.x, -WIGGLE_MOST, WIGGLE_MOST), clampf(-d.y, -WIGGLE_MOST, WIGGLE_MOST), 0)


## Semitones a pixel of Alt's mouse travel bends: 100 pixels a semitone.
const BEND_PIXELS := 100.0
## How quickly the Alt bend comes back to the middle once Alt is let go (s).
const BEND_SETTLE := 0.06

## Alt as the bend wheel's key, for the suite: -1 reads the keyboard, 0 is up, 1 is down.
var alt_override := -1
## Where Alt's bend wheel stands (semitones, up positive).
var _bend := 0.0
## The plain keys' own wobble: no tilt, only the Alt bend (`bend_wheel`), for a MIDI keyboard or
## the computer's piano, whose notes no instrument here plays. With the keytar in hand its plain
## keys are the keytar's, which bends them itself (KeytarItem).
var _keys_wobble: Wobble = null


func bend_wheel() -> float:
	return _bend


## Whether Alt is down: the bend wheel's key.
func alt_down() -> bool:
	return alt_override == 1 if alt_override >= 0 else Input.is_key_pressed(KEY_ALT)


## The mouse moved `up` pixels up (down negative) with Alt held: the bend wheel turned by as much.
func bend_by(up: float) -> void:
	_bend = clampf(_bend + up / BEND_PIXELS, -Wobble.BEND_MOST, Wobble.BEND_MOST)


## Alt let go: the bend wheel springs back to the middle, `delta` seconds on.
func _spring_bend(delta: float) -> void:
	if alt_down() or _bend == 0.0:
		return
	_bend *= exp(-delta / BEND_SETTLE)
	if absf(_bend) < 0.01:
		_bend = 0.0


## The plain keys' wobble, one frame on: bent by Alt alone.
func _bend_plain_keys(delta: float) -> void:
	var keys := Session.guest_midi
	if keys == null or not is_instance_valid(keys):
		return
	if _keys_wobble == null:
		_keys_wobble = Wobble.new(keys, [&""], self)
		_keys_wobble.tilts = false
	_keys_wobble.keys = keys
	_keys_wobble.sources = [] if keys.keytar else [&""]
	_keys_wobble.step(delta)


func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and alt_down():
		bend_by(-motion.relative.y)


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
##
## P steps the jack of the instrument this hand carries on, and Shift+P back (JackSocket): the
## cursor's own ray never reaches that socket, so the key is the desktop's other hand. With
## nothing in the hand, P is the player's own keys' jack, which a headset wears on the wrist, and
## Shift+P unplugs everything going into the player (`bare_jack`).
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_P:
		if step_own_jack(-1 if key.shift_pressed else 1):
			get_viewport().set_input_as_handled()
		elif not is_instance_valid(carrying):
			bare_jack.emit(key.shift_pressed)
			get_viewport().set_input_as_handled()
		return
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


## The carried instrument's jack one step on (`way` 1) or back (-1): P and Shift+P. False with no
## instrument in this hand.
func step_own_jack(way: int) -> bool:
	var jack := own_jack()
	if jack == null or not (carrying as Item).in_hand():
		return false
	return jack.step(way)


func is_pressing() -> bool:
	var down := press_override == 1 if press_override >= 0 \
			else Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _press_spent and not down:
		_press_spent = false
	if fingers_play or _press_spent:
		return false
	if press_override >= 0:
		return down
	# A click on a panel is a click on the panel. Without this, pressing a button in the
	# session panel also grabbed whatever fader happened to be behind it in the room.
	if held == null and _over_gui():
		return false
	return down


func _over_gui() -> bool:
	var vp := get_viewport()
	return vp != null and vp.gui_get_hovered_control() != null


func _physics_process(delta: float) -> void:
	super(delta)
	if camera != null or pointer_override.x >= 0.0:
		wiggle(pointer(), delta)
	_spring_bend(delta)
	if camera != null:
		_bend_plain_keys(delta)
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
