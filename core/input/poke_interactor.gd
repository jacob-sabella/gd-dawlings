class_name PokeInteractor
extends Interactor

## A tracked hand's index fingertip, touching the gear directly: press a button by pressing it,
## put a fingertip on a fader cap and slide it, the way the real desk is played. The pinch ray
## (XRInteractor) is for what is out of reach; this is for what is under your hand, and it is
## the fine one -- the cap goes exactly where the finger goes, with no lever arm to magnify the
## tremor of a hand held out in the air.
##
## Reads the hand's joints from its XRHandTracker, not from a controller pose, so it only exists
## while the headset is tracking a bare hand: pick a controller up and the tracker has no data,
## and this hand neither hovers nor presses until it is put down again.
##
## THE CONTACT. A short ray is cast along the finger from a little behind the tip. The tip at a
## control's face (within TOUCH of it) presses; once pressed it holds until the finger comes back
## off that face by LIFT, measured from where it touched, so the slight drift of a fingertip
## resting on a fader does not let go of it, and pushing on through the cap never does either.

## The joint tracker for this hand: "/user/hand_tracker/left" or "/user/hand_tracker/right".
@export var tracker_name: StringName = &"/user/hand_tracker/right"
## Tracking space: the XROrigin3D the joints are reported in.
var origin: Node3D

## How far behind the tip the ray starts, and how far past it it reaches.
const BEHIND := 0.03
const AHEAD := 0.02
## The tip within this of a face touches it.
const TOUCH := 0.004
## Back off the face by this, from where it touched, and it lets go.
const LIFT := 0.02

const TIP := XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP
const DISTAL := XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_DISTAL

var _pressing := false
## The touched face's normal, turned toward where the finger came from, and how far in front of
## the control's origin the tip was along it when it touched.
var _face := Vector3.ZERO
var _touched_at := 0.0
var _tip := Vector3.ZERO
var _pointing := Vector3.FORWARD
var _tracked := false


func _physics_process(delta: float) -> void:
	_read_hand()
	_update_contact()
	super(delta)


## Whether the hand is tracked this frame, with a tip and a finger to point along.
func tracked() -> bool:
	return _tracked


func tip() -> Vector3:
	return _tip


func aim() -> Transform3D:
	# Held: straight down the held control's face onto the tip, so where the control is moved to
	# (Interactor._plane_point) is the tip itself, whichever way the finger happens to be bent.
	if _pressing and held != null and _face != Vector3.ZERO:
		return _looking(_tip + _face * 0.05, -_face)
	return _looking(_tip - _pointing * BEHIND, _pointing)


func reach() -> float:
	return BEHIND + AHEAD if _tracked else 0.0


func is_pressing() -> bool:
	return _pressing


func touches_directly() -> bool:
	return true


## A fingertip has no fine-adjust: it is already one to one.
func fine() -> bool:
	return false


## The glove and the carrying are the pinch's; a finger only touches.
func carry_pose() -> Transform3D:
	return Transform3D(Basis.IDENTITY, _tip)


func _read_hand() -> void:
	var hand := XRServer.get_tracker(tracker_name) as XRHandTracker
	_tracked = false
	if hand == null or not hand.has_tracking_data:
		return
	var valid := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID
	if hand.get_hand_joint_flags(TIP) & valid == 0 or hand.get_hand_joint_flags(DISTAL) & valid == 0:
		return
	var space := origin.global_transform if origin != null and origin.is_inside_tree() \
			else Transform3D.IDENTITY
	var tip_at := space * hand.get_hand_joint_transform(TIP).origin
	var knuckle := space * hand.get_hand_joint_transform(DISTAL).origin
	if tip_at.distance_to(knuckle) < 0.001:
		return
	_tip = tip_at
	_pointing = (tip_at - knuckle).normalized()
	_tracked = true


func _update_contact() -> void:
	if not _tracked or not is_inside_tree():
		_pressing = false
		return
	if _pressing:
		if not is_instance_valid(held):
			_pressing = false
			return
		var lifted := _face.dot(_tip - held.global_position) - _touched_at
		if lifted > LIFT:
			_pressing = false
		return
	var from := _tip - _pointing * BEHIND
	var hit := _cast(from, _pointing)
	var control: ControlAffordance = hit["control"]
	if control == null:
		return
	var depth: float = from.distance_to(hit["point"]) - BEHIND
	if depth > TOUCH:
		return
	var normal := control.global_transform.basis.z.normalized()
	if normal.dot(from - control.global_position) < 0.0:
		normal = -normal
	_face = normal
	_touched_at = _face.dot(_tip - control.global_position)
	_pressing = true


static func _looking(from: Vector3, direction: Vector3) -> Transform3D:
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	return Transform3D(Basis.looking_at(direction, up), from)
