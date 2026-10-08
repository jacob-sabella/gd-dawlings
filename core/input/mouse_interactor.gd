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


func is_pressing() -> bool:
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
