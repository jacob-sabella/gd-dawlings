class_name RoomAnchor
extends Node3D

## The shared physical frame. Everything ROOM-anchored hangs under this node.
##
## THE PROBLEM. Two people in passthrough headsets standing in the same studio do not share a
## coordinate system. Each runtime picked its own origin when it started, somewhere near where
## that headset was switched on, facing wherever it happened to face. Put a console at (0, 0, -1)
## in each and they appear in two different places a metre or two apart -- and the whole premise
## of co-located mixing is that when one person points at the kick fader, the other sees them
## pointing at the kick fader.
##
## THE FIX, and why it is this one. Both people mark the SAME TWO PHYSICAL POINTS -- opposite
## corners of a desk, two bits of tape on the floor. That is enough to pin a frame completely,
## because gravity supplies the third axis for free: every XR runtime knows which way is down to
## within a fraction of a degree, so only position and YAW are actually unknown, and two points
## on a plane determine exactly those.
##
## By convention the first point is the session origin and the direction to the second is session
## +X. Mark the same tape in the same order, get the same frame. No marker tracking, no cloud
## anchors, no vendor lock-in, and it works for a screen participant too: they type the distance
## between the two points and get a studio laid out to the real room's dimensions.
##
## The measured distance between the two points is the HONESTY CHECK. Everyone marking the same
## tape should agree on how far apart it is; if two headsets disagree by 8cm, one of them has
## drifted and the right response is to re-mark, not to average two wrong frames together.

signal calibrated(agreed_span: float)
signal calibration_drift(local_span: float, expected_span: float)

## Tolerated disagreement, in metres, between this participant's measured span and the session's.
## 3cm is about the width of a fader cap: beyond that, two people reaching for the same control
## are reaching for different ones.
const SPAN_TOLERANCE := 0.03

var is_calibrated := false
## Distance between the two marks, as the session agreed it. Set by the first participant to
## calibrate; later ones are checked against it.
var session_span: float = 0.0

var _mark_a := Vector3.ZERO
var _has_mark_a := false


## Record the first physical point, in this headset's own tracking space.
func mark_origin(point_in_world: Vector3) -> void:
	_mark_a = point_in_world
	_has_mark_a = true


## Record the second physical point and commit the frame.
func mark_forward(point_in_world: Vector3) -> bool:
	if not _has_mark_a:
		push_warning("RoomAnchor: mark_origin() first.")
		return false

	var span_vec := point_in_world - _mark_a
	# Flattened against gravity before anything else. The two marks are rarely at exactly the
	# same height -- a hand placing them is a couple of centimetres out -- and letting that tilt
	# the frame would rotate the whole studio by a degree or two about the horizontal.
	var flat := Vector3(span_vec.x, 0.0, span_vec.z)
	var span := flat.length()
	if span < 0.25:
		push_warning("RoomAnchor: marks are %.2fm apart; too close to fix a direction." % span)
		return false

	if session_span > 0.0 and absf(span - session_span) > SPAN_TOLERANCE:
		# Deliberately still calibrates. Refusing would leave a participant with no frame at all,
		# which is worse than a slightly wrong one -- but the disagreement is reported so the
		# session can be told to re-mark.
		calibration_drift.emit(span, session_span)
	else:
		session_span = span

	var x_axis := flat.normalized()
	var y_axis := Vector3.UP
	var z_axis := x_axis.cross(y_axis).normalized()
	# Right-handed, and rebuilt rather than assumed: x.cross(up) gives -Z for Godot's handedness,
	# so X is recomputed from the other two instead of trusting the order.
	x_axis = y_axis.cross(z_axis).normalized()

	# This node IS world_from_session: parent a console at session (0,0,0) and it lands on the
	# first piece of tape.
	transform = Transform3D(Basis(x_axis, y_axis, z_axis), _mark_a)
	is_calibrated = true
	calibrated.emit(session_span)
	return true


## A screen or remote-VR participant has no physical room to mark. They get the session frame
## outright, which places them in the same layout everyone else is standing in.
func adopt_virtual_frame(span: float) -> void:
	session_span = span
	transform = Transform3D.IDENTITY
	is_calibrated = true
	calibrated.emit(span)


func session_from_world(point: Vector3) -> Vector3:
	return global_transform.affine_inverse() * point


func world_from_session(point: Vector3) -> Vector3:
	return global_transform * point
