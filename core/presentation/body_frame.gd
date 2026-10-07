class_name BodyFrame
extends Node3D

## The frame things are placed in when they are placed FOR A PERSON rather than in a room.
##
## The naive version of "the gear comes to you" is to parent it to the head, and it is wrong in
## a way that is unpleasant rather than merely imperfect. Head-locked content cannot be looked
## AT: it moves exactly as much as your eye does, so you can never bring a different part of it
## to the centre of your vision, and after a minute or two of that most people feel ill. It also
## destroys the one thing the room was good at, which is that you can glance away.
##
## What a person actually has is a torso. Your gear sits in front of your body; you turn your
## HEAD to look along it, and it stays where it was; you turn your BODY and it comes with you.
## That is what this reproduces:
##
##   * POSITION follows the head, because when you walk, your desk comes with you. Immediately,
##     since nobody is disoriented by their own footsteps.
##   * YAW follows the head only once the head has turned past a deadzone, and then catches up
##     smoothly rather than snapping. Inside the deadzone you are looking around your own
##     workspace and it must hold still.
##   * PITCH AND ROLL are never followed. Looking down at a fader must not tip the room, and a
##     head tilt must not roll it. This is the single biggest comfort item in the file.
##
## The deadzone is also an accessibility control, not only a comfort one: someone who cannot
## turn their head far sets a small one and the workspace follows them readily, while someone
## who works by sweeping their gaze across a wide arc sets a large one and it stays put.

## How far the head may turn before the frame starts to follow, in degrees. Default is a little
## inside Ergonomics.head_turn, so the comfortable sweep is entirely inside the deadzone and the
## frame only moves when you meant it to.
var deadzone_degrees := 42.0
## Seconds to close the remaining gap, roughly. Slow on purpose -- a frame that snaps as you
## cross the deadzone is the same lurch head-locking gives you, just less often.
var follow_seconds := 0.65
## 0 pins the frame where it was placed and never follows. For anyone who gets motion sick, and
## for a screen user who would rather drive the camera themselves.
var follow_scale := 1.0

var head: Node3D

var _yaw := 0.0
var _started := false


## Stop following, and stand still where you are.
##
## For looking at your own workspace from outside it, which is not a pose a person can take and
## is exactly what a screenshot of body-relative placement needs: with the rig riding the
## camera, every attempt to photograph the arrangement moves the arrangement. It is also what a
## second viewer in the room sees of YOUR gear, so this is not only a camera trick.
func detach() -> void:
	head = null


func _process(delta: float) -> void:
	if head == null:
		return
	var head_yaw := _yaw_of(head.global_transform.basis)
	if not _started:
		_started = true
		_yaw = head_yaw
	elif follow_scale > 0.0:
		_yaw = follow_yaw(_yaw, head_yaw, deadzone_degrees, follow_seconds, delta * follow_scale)
	# Position is taken whole and rotation is taken yaw-only, which is the entire trick.
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), head.global_position)


## Where the frame's yaw should be after `delta`, given where the head is looking.
##
## Pure and static so the deadzone can be tested without a head, a camera or a frame of engine
## time -- the behaviour here is a comfort guarantee, and a comfort guarantee that is only
## verified by someone putting a headset on is not verified.
static func follow_yaw(current: float, target: float, deadzone: float,
		seconds: float, delta: float) -> float:
	var error := angle_difference(current, target)
	var slack := deg_to_rad(maxf(deadzone, 0.0))
	if absf(error) <= slack:
		return current
	# Chase the EDGE of the deadzone, not the head. Chasing the head would park the workspace
	# dead ahead every time you turned, so the deadzone would vanish the moment it was crossed
	# and you could never look along your own desk again.
	var wanted := target - signf(error) * slack
	if seconds <= 0.0 or delta <= 0.0:
		return wanted
	# Frame-rate independent exponential approach. A plain lerp by delta/seconds is not, and
	# this runs at 72Hz in a headset and several hundred on a desktop.
	var closed := 1.0 - exp(-delta / seconds)
	return current + angle_difference(current, wanted) * closed


static func _yaw_of(basis: Basis) -> float:
	var forward := -basis.z
	if absf(forward.x) < 1e-6 and absf(forward.z) < 1e-6:
		# Looking straight up or down: the yaw of the forward vector is undefined, so take it
		# from the up vector instead, which in that pose is the one lying in the floor plane.
		forward = basis.y * (-1.0 if basis.z.y > 0.0 else 1.0)
	return atan2(-forward.x, -forward.z)
