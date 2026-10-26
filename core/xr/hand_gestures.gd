class_name HandGestures
extends Node

## One tracked bare hand's readings, every physics frame: its size, its curls, the fingers its
## thumb is pinching, whether its palm is up or faces the head, and its tilt (HandPose, read off
## the joint tracker; docs/spatial_loop.md slice 7).
##
## One per hand under the XRRig, beside its HandSkeleton, reading the same tracker. It keeps the
## pinch mask from frame to frame, since a pinch lets go further apart than it closes. Its hand's
## XRInteractor answers `finger_pinches`, `palm_up` and `tilt` from here while the hand is
## tracked; the chord harp is strummed by its index and middle tips (`local_tips`).
##
## Hand poses never cross the wire: what they play does.

const GROUP := &"hand_gestures"

## The joint tracker for this hand.
@export var tracker_name: StringName = &"/user/hand_tracker/right"
## -1 the left hand, 1 the right (HandPose's `side`).
var side := 1
## Tracking space: the XROrigin3D the joints are reported in. Null reads them as global.
var origin: Node3D
## Where the eyes are, for `faces_head`: the rig's head. Null, and the palm faces no head.
var head: Node3D

## Whether a whole hand was read this frame. Everything below is its last reading while it was,
## and let go (no pinch, level, nothing up) while it is not.
var tracked := false
## Tracked, and every joint seen rather than guessed (the runtime's POSITION_TRACKED, not only
## VALID): a hand half out of view, its joints inferred, is tracked but not confident. What a held
## shaker's letting go and its throw are read from (XRInteractor), so a guess is never a throw.
var confident := false
## Closed round something (HandPose.closed): three fingers past HOLD_CURL.
var closed := false
## The joints, in global space.
var joints := PackedVector3Array()
var size := 0.0
var curls := PackedFloat32Array()
var pinched := 0
## How far each finger has come in toward the thumb, index to little, 0..1 (HandPose.travel).
var travel := PackedFloat32Array()
## Held open: four fingers out, none pinched (HandPose.is_open).
var open := false
var palm_up := false
var faces_head := false
var tilt := Vector2.ZERO
## Its roll and pitch in radians, unclamped (HandPose.angles): what a bend is measured by (Wobble).
var angles := Vector2.ZERO


func _ready() -> void:
	# Ahead of the interactors, so a hand's readings are this frame's when they ask.
	process_physics_priority = -1


func _enter_tree() -> void:
	add_to_group(GROUP)


func _physics_process(_delta: float) -> void:
	read(XRServer.get_tracker(tracker_name) as XRHandTracker)


## This frame's readings from `hand`: all of them let go if it is not tracking, or any joint's
## position is not valid (as HandSkeleton draws it), since a pinch read off a joint that is a
## guess plays a note nobody made.
func read(hand: XRHandTracker) -> void:
	if hand == null or not hand.has_tracking_data:
		_lose()
		return
	var valid := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID
	var seen := XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
	var space := origin.global_transform if origin != null and origin.is_inside_tree() \
			else Transform3D.IDENTITY
	var at := PackedVector3Array()
	at.resize(XRHandTracker.HAND_JOINT_MAX)
	var all_seen := true
	for j in XRHandTracker.HAND_JOINT_MAX:
		var flags := hand.get_hand_joint_flags(j)
		if flags & valid == 0:
			_lose()
			return
		all_seen = all_seen and flags & seen != 0
		at[j] = space * hand.get_hand_joint_transform(j).origin
	take(at, all_seen)


## The readings of a hand whose joints are `at`, global space; `sure` false for joints the runtime
## only guessed at (`confident`).
func take(at: PackedVector3Array, sure := true) -> void:
	if not HandPose.whole(at) or HandPose.size(at) < 0.01:
		_lose()
		return
	tracked = true
	confident = sure
	joints = at
	size = HandPose.size(at)
	curls = HandPose.curls(at)
	pinched = HandPose.pinches(at, pinched, Ergonomics.current.finger_scale)
	travel = HandPose.travel(at, Ergonomics.current.finger_scale)
	open = HandPose.is_open(at, pinched)
	closed = HandPose.closed(at)
	palm_up = HandPose.palm_up(at, side)
	faces_head = head != null and head.is_inside_tree() \
			and HandPose.faces_head(at, head.global_position, side)
	angles = HandPose.angles(at, side)
	tilt = HandPose.tilt_of(HandPose.frame(at, side))


func _lose() -> void:
	tracked = false
	confident = false
	closed = false
	pinched = 0
	travel = PackedFloat32Array()
	open = false
	palm_up = false
	faces_head = false
	tilt = Vector2.ZERO
	angles = Vector2.ZERO


## The middle of the palm (its PALM joint), global space, while it is tracked: where a bare hand
## shakes what it holds from (XRInteractor.shake_point), so a wrist's shake is a stroke.
func palm() -> Vector3:
	return joints[HandPose.PALM] if tracked else Vector3.INF


## The palm as a pose, global space, while it is tracked: at its middle, faced as HandPose.frame
## (+Y out of the back of the hand, -Z along it). Where a closed hand carries what it holds.
func palm_pose() -> Transform3D:
	if not tracked:
		return Transform3D.IDENTITY
	return Transform3D(HandPose.frame(joints, side), joints[HandPose.PALM])


## This hand's index and middle fingertips, global space, while it is tracked: {&"index",
## &"middle"}. What it strums the harp with.
func tips() -> Dictionary:
	if not tracked:
		return {}
	return {&"index": joints[HandPose.TIPS[0]], &"middle": joints[HandPose.TIPS[1]]}


## Every local tracked hand's strumming tips in `tree`, {[hand, finger]: Vector3}: keyed so one
## tip is the same key from frame to frame (ChordHarp.tips). Only this player's hands are here: a
## bandmate's ghost has no joints, and its strums arrive as notes.
static func local_tips(tree: SceneTree) -> Dictionary:
	var out := {}
	if tree == null:
		return out
	for node in tree.get_nodes_in_group(GROUP):
		var hand := node as HandGestures
		if hand == null:
			continue
		var mine := hand.tips()
		for finger in mine:
			out[[hand.get_instance_id(), finger]] = mine[finger]
	return out


## The readings in words, one to a line, for a shot of them.
func describe() -> String:
	if not tracked:
		return "NOT TRACKED"
	var curled: PackedStringArray = []
	for c in curls:
		curled.append("%.2f" % c)
	return "\n".join([
		"SIZE %d mm" % roundi(size * 1000.0),
		"CURLS %s" % " ".join(curled),
		"PINCH %s" % HandPose.pinch_words(pinched),
		"PALM %s%s" % ["UP" if palm_up else "NOT UP", ", FACES HEAD" if faces_head else ""],
		"TILT roll %+d  pitch %+d" % [roundi(tilt.x * HandPose.TILT_MOST), roundi(tilt.y * HandPose.TILT_MOST)],
	])
