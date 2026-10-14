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
	if _steadied:
		return _steady
	return controller.global_transform if controller else global_transform


## A bare hand's pinch ray, steadied. A hand held out in the air trembles, and a three metre ray
## turns a millimetre of it into centimetres on the gear; a controller is braced in the fist and
## does not need it. Adaptive: still, it is smoothed hard (an aim you can rest on a single
## button); moving, hardly at all, so a sweep across the room does not lag behind the hand.
const STEADY_SLOW := 6.0
const STEADY_FAST := 40.0
## How fast (m/s at the hand, or rad/s of the ray) counts as moving on purpose.
const MOVING_SPEED := 0.35
const TURNING_SPEED := 1.2

var _steady := Transform3D.IDENTITY
var _steadied := false
## The roll counted so far (twist), and the hand's sideways axis it was last counted from.
var _roll := 0.0
var _roll_from := Vector3.ZERO


func twist() -> float:
	return _roll


## On from last frame by however far the hand has rolled about where it points, clockwise as
## seen from behind it. Counted frame to frame rather than read as an angle, so turning past
## half a turn keeps counting instead of jumping back.
func _count_roll() -> void:
	var at := aim()
	var forward := -at.basis.z.normalized()
	var side := at.basis.x - forward * at.basis.x.dot(forward)
	if side.length() < 0.001:
		return
	side = side.normalized()
	if _roll_from != Vector3.ZERO:
		var was := _roll_from - forward * _roll_from.dot(forward)
		if was.length() > 0.001:
			_roll += was.normalized().signed_angle_to(side, forward)
	_roll_from = side


func bare_hand() -> bool:
	if controller == null:
		return false
	var tracker := XRServer.get_tracker(controller.tracker) as XRPositionalTracker
	return tracker != null and String(tracker.profile).contains("hand_interaction")


func _steady_aim(delta: float) -> void:
	if not bare_hand() or controller == null or not controller.is_inside_tree():
		_steadied = false
		return
	var raw := controller.global_transform
	if not _steadied:
		_steady = raw
		_steadied = true
		return
	_steady = steadied(_steady, raw, delta)


## One step of the steadying from `was` toward `raw` over `delta`.
static func steadied(was: Transform3D, raw: Transform3D, delta: float) -> Transform3D:
	if delta <= 0.0:
		return was
	var moving := was.origin.distance_to(raw.origin) / delta / MOVING_SPEED
	var turning := (-was.basis.z).angle_to(-raw.basis.z) / delta / TURNING_SPEED
	var rate := lerpf(STEADY_SLOW, STEADY_FAST, clampf(maxf(moving, turning), 0.0, 1.0))
	var t := 1.0 - exp(-rate * delta)
	var q := was.basis.get_rotation_quaternion().slerp(raw.basis.get_rotation_quaternion(), t)
	return Transform3D(Basis(q), was.origin.lerp(raw.origin, t))


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
	_steady_aim(delta)
	_count_roll()
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
