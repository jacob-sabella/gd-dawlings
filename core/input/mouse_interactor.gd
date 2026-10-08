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
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _physics_process(delta: float) -> void:
	super(delta)
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
	_card.show_for(held if held != null else hovered, pointer())
