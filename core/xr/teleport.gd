class_name Teleport
extends Node3D

## Going anywhere on the floor with a bare hand (2026-10-30: "I dont have a way to move in VR mode
## when i dont have controllers"): point the hand's pinch ray down at the floor, pinch on nothing,
## and a ring stands where the ray meets it; let go and you are there, the play space put down so
## your head is over the ring (XRRig.travel, a cut behind the veil, never a glide). Where a person
## does not fit (`fits`: off the floor, in a wall, inside the desk) the ring is red and letting go
## goes nowhere. A pinch that took hold of something, or began on something, is that thing's.
##
## The stations' board and plaques still go to a station's own seat; this is for everywhere else.

## The rig whose hands point, and whose play space goes.
var rig: XRRig
## The frame the floor is measured in (the venue's), and whether a person fits at a point in it
## (Walker.fits); the height of the floor there (Walker.ground_of the venue's solids).
var frame: Callable
var fits: Callable
var ground: Callable
## Why travel is refused here ("" when it is not): Studio.travel_refusal.
var refusal: Callable
## Gone somewhere: the studio forgets the station it was at.
signal went(to: Vector3)

## How far down from level the ray must point to aim at the floor, and how far it reaches.
const DOWN_AT_LEAST := 0.12
const REACH := 10.0
## How long a pinch is held aimed before letting go goes: a pinch that only missed a button is
## not a trip.
const AIMED_FOR := 0.25

## Per hand (its XRInteractor): {armed, for, point, ok}.
var _aims := {}
var ring: MeshInstance3D
var _ring_paint: StandardMaterial3D


func _ready() -> void:
	# After the hands have read their pinch and taken hold of whatever they were on.
	process_physics_priority = 10
	ring = MeshInstance3D.new()
	ring.name = "TeleportRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.26
	ring.mesh = torus
	_ring_paint = StandardMaterial3D.new()
	_ring_paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = _ring_paint
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)


func _physics_process(delta: float) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var shown := false
	for controller in rig.interactors:
		var hand := rig.interactors[controller] as XRInteractor
		if hand == null or not is_instance_valid(hand):
			continue
		var aim: Dictionary = _aims.get(hand, {"armed": false, "for": 0.0, "ok": false, "point": Vector3.ZERO, "was": false})
		var g: HandGestures = rig.gestures.get(controller)
		var bare := g != null and g.tracked
		# The runtime's pinch where it reports one, else the joints' own: a headset streaming bare
		# hands without an interaction profile for them still pinches.
		var pressed := bare and (hand.is_pressing() or (g.pinched & HandPose.INDEX) != 0)
		if pressed and not aim["was"]:
			aim["armed"] = hand.hovered == null and hand.held == null and not is_instance_valid(hand.carrying) \
					and not hand.tool.is_valid() and not hand.fingers_play
			aim["for"] = 0.0
			aim["ok"] = false
		if pressed and aim["armed"]:
			if hand.held != null or is_instance_valid(hand.carrying):
				aim["armed"] = false
			else:
				var at := floor_point(hand_aim(hand, g))
				aim["for"] += delta
				aim["ok"] = at.is_finite() and fits.is_valid() and bool(fits.call(_plan(at)))
				aim["point"] = at
				if at.is_finite():
					_show_ring(at, aim["ok"])
					shown = true
		elif not pressed and aim["was"] and aim["armed"]:
			if aim["ok"] and aim["for"] >= AIMED_FOR:
				go(aim["point"])
			aim["armed"] = false
		aim["was"] = pressed
		_aims[hand] = aim
	if not shown:
		ring.visible = false


## Where a bare hand points: its pinch ray where the runtime gives one, else along the hand from
## the wrist through its knuckles.
static func hand_aim(hand: XRInteractor, g: HandGestures) -> Transform3D:
	if hand.controller != null and hand.controller.get_has_tracking_data():
		return hand.aim()
	var basis := HandPose.frame(g.joints, g.side)
	return Transform3D(basis, g.joints[HandPose.PALM])


## Where a ray from `aim` (its -Z) meets the floor within REACH, on top of anything stepped up onto
## there; INF where it points level or up, or meets it further off.
func floor_point(aim: Transform3D) -> Vector3:
	var origin := aim.origin
	var direction := -aim.basis.z.normalized()
	if direction.y > -DOWN_AT_LEAST:
		return Vector3.INF
	var level := _frame().origin.y
	var t := (level - origin.y) / direction.y
	if t <= 0.0 or t > REACH:
		return Vector3.INF
	var at := origin + direction * t
	if ground.is_valid():
		at.y = level + float(ground.call(_plan(at)))
	return at


## Put the play space down so the head stands over `point` (global), facing as it faces now.
## Refused, the room says why and nobody goes.
func go(point: Vector3) -> bool:
	var no: String = refusal.call() if refusal.is_valid() else ""
	if no != "":
		Session.notice.emit("Not here: %s." % no)
		return false
	var head := rig.head.position if rig.head != null else Vector3.ZERO
	var off := rig.global_basis * Vector3(head.x, 0.0, head.z)
	off.y = 0.0
	rig.travel(Transform3D(rig.global_basis, point - off))
	went.emit(point)
	return true


func _frame() -> Transform3D:
	return frame.call() if frame.is_valid() else Transform3D.IDENTITY


func _plan(at: Vector3) -> Vector2:
	var local := _frame().affine_inverse() * at
	return Vector2(local.x, local.z)


func _show_ring(at: Vector3, ok: bool) -> void:
	ring.visible = true
	ring.global_transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.01, 0))
	_ring_paint.albedo_color = Color(0.45, 0.95, 0.6, 0.85) if ok else Color(0.95, 0.35, 0.3, 0.6)
