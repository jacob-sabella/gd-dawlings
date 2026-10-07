class_name MouseInteractor
extends Interactor

## The screen participant's hand: a ray from the camera through the cursor.
##
## This exists so that a monitor is not a second-class way to be in the session. The engineer at
## the desk with a mouse is driving the same ControlAffordance objects, through the same grab
## contract, as the person standing in the room pinching the same fader.

@export var camera: Camera3D


func aim() -> Transform3D:
	if camera == null:
		return global_transform
	var mouse := camera.get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	return Transform3D(Basis.looking_at(direction, Vector3.UP), origin)


func is_pressing() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
