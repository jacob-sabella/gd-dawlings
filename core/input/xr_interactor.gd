class_name XRInteractor
extends Interactor

## One tracked controller or hand.
##
## Reads the pose off an XRController3D rather than being one, so that a hand-tracked pinch and a
## controller trigger are the same interactor with a different `press_action`. Parent this under
## the controller node.

@export var controller: XRController3D
## OpenXR action name. "trigger_click" for a controller; hand tracking reports a pinch through
## the same action map, so both arrive here identically.
@export var press_action: StringName = &"trigger_click"


func aim() -> Transform3D:
	return controller.global_transform if controller else global_transform


func is_pressing() -> bool:
	if controller == null:
		return false
	return controller.is_button_pressed(press_action)


## The grip, squeezed and let go while carrying something, lets go of it: a flick throws it at the
## speed the hand was moving, anything slower puts it down where the hand is pointing.
@export var grip_action: StringName = &"grip_click"
## Slower than this as the grip opens and it is put down, not thrown (m/s).
## How near the palm a throw has to pass to be caught (m): a hand's span, open.
const CATCH_REACH := 0.16
## How near your eyes a hand has to be to be at your head: a hand at the ear counts, and one
## held out to a fader is further off than this.
const HEAD_REACH := 0.22
## How near a hip, or over the shoulder, it reaches into a pocket (m).
const POCKET_REACH := 0.16
const FLICK_SPEED := 1.4
## How far back the hand's speed is measured over, so one jittery frame is not a throw.
const FLICK_WINDOW := 0.08

var _gripping := false
var _trail: Array = []


func _physics_process(delta: float) -> void:
	super(delta)
	var now := Time.get_ticks_msec() / 1000.0
	_trail.append([now, aim().origin])
	while _trail.size() > 2 and now - float(_trail[0][0]) > FLICK_WINDOW:
		_trail.pop_front()
	var gripping := controller != null and controller.is_button_pressed(grip_action)
	if _gripping and not gripping and carrying != null and is_instance_valid(carrying):
		var moving := hand_velocity()
		if moving.length() > FLICK_SPEED:
			throw_item(moving, aim().basis.x * -moving.length() * 1.5)
		else:
			put_down()
	_gripping = gripping


func catch_reach() -> float:
	return CATCH_REACH


## The trigger, with an empty hand up by your ear, takes off what you have on your head.
func head_reach() -> float:
	return HEAD_REACH


## A hand at a hip, or reached back over the shoulder, with the trigger: into the pocket there, or
## out of it.
func pocket_reach() -> float:
	return POCKET_REACH


## Where the pockets are, from the head: the hips below it either side, the back over the
## shoulder of this hand's side, behind it. Turned with the head's yaw, not its pitch: looking
## down does not move your hips.
func pocket_point(slot: int) -> Vector3:
	var head := head_point()
	var forward := Vector3.FORWARD
	var origin := controller.get_parent() if controller != null else null
	if origin != null:
		for child in origin.get_children():
			if child is XRCamera3D:
				forward = -(child as XRCamera3D).global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP)
	match slot:
		0:
			return head - Vector3.UP * 0.7 - right * 0.2
		1:
			return head - Vector3.UP * 0.7 + right * 0.2
	return head - Vector3.UP * 0.1 - forward * 0.18


func head_point() -> Vector3:
	var origin := controller.get_parent() if controller != null else null
	if origin != null:
		for child in origin.get_children():
			if child is XRCamera3D:
				return (child as XRCamera3D).global_position
	return super()


## How fast the hand has been moving, over the last FLICK_WINDOW.
func hand_velocity() -> Vector3:
	if _trail.size() < 2:
		return Vector3.ZERO
	var first: Array = _trail[0]
	var last: Array = _trail[-1]
	var span := float(last[0]) - float(first[0])
	return (last[1] - first[1]) / span if span > 0.0001 else Vector3.ZERO
