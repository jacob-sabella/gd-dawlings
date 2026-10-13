class_name XRRig
extends XROrigin3D

## The headset and the two hands, plus the gesture that tells this participant's rig where the
## real room is.
##
## WHY THE RIG OWNS CALIBRATION. In a co-located session every headset wakes up with its own
## tracking origin, decided by wherever the runtime happened to think "front" was. Those origins
## are unrelated, so two people looking at the same console see it in two different places --
## which is the one failure that makes a shared room worse than no room at all. The fix is for
## each rig to measure the SAME two physical marks and solve for its own offset, and the rig is
## where that has to live because the controller tip is the only thing in the system that can
## touch a spot on the actual floor.
##
## Gravity supplies the third axis, so two marks are enough: the unknowns are a position and a
## yaw, and a pair of points on the floor pins both. Asking for a third mark would be asking for
## a measurement the solve does not use.
##
## THE GESTURE, on the left controller's `by_button`:
##   press once   mark the origin -- touch the controller tip to the first floor mark
##   press again  mark forward -- touch it to the second
## A third press starts over, because the most likely thing after a bad calibration is wanting
## to do it again, not wanting to find a menu.

signal calibration_step(step: int, total: int)

## The tip of the controller, not its tracked centre. A controller's pose is reported somewhere
## around the user's fist; the point they will actually press against a floor mark is ahead of
## it and below it, and calibrating against the fist puts the whole room off by a hand.
const TIP_OFFSET := Vector3(0, -0.015, -0.075)

const CALIBRATE_ACTION := &"by_button"
const PRESS_ACTION := &"trigger_click"

## Set by the studio before the rig enters the tree when there is no headset (--xr-sim): the
## rig then starts where a standing person's head and hands would, since no runtime is there
## to report them and the simulator only moves them from wherever they begin.
var simulated := false
const SIM_EYE_HEIGHT := 1.6
const SIM_HAND := Vector3(0.22, 1.25, -0.35)

var head: XRCamera3D
var left: XRController3D
var right: XRController3D
var room_anchor: RoomAnchor

var _marks_taken := 0
var _calibrate_was_down := false


func _ready() -> void:
	head = XRCamera3D.new()
	head.name = "Head"
	# Near plane tight: in a headset your own hands come well inside the 0.02 a desk camera can
	# get away with, and a hand clipping through its own controller is very hard to unsee.
	head.near = 0.02
	# Everything but your own ghost, which only mirrors draw. See core/venues/mirror.gd.
	head.cull_mask = Mirror.MAIN_VIEW_MASK
	if simulated:
		head.position.y = SIM_EYE_HEIGHT
	add_child(head)

	left = _build_hand(&"left_hand", "LeftHand")
	right = _build_hand(&"right_hand", "RightHand")


func _build_hand(tracker: StringName, node_name: String) -> XRController3D:
	var controller := XRController3D.new()
	controller.name = node_name
	controller.tracker = tracker
	if simulated:
		controller.position = SIM_HAND * Vector3(1.0 if tracker == &"right_hand" else -1.0, 1.0, 1.0)
	add_child(controller)

	# A short stub rather than a model: this project does not ship controller meshes, and an
	# untextured generic blob reads worse than an honest pointer. What a hand needs to convey is
	# where it is aiming, and that is the ray.
	var ray := MeshInstance3D.new()
	var ray_mesh := CylinderMesh.new()
	ray_mesh.top_radius = 0.0012
	ray_mesh.bottom_radius = 0.0012
	ray_mesh.height = Interactor.RAY_LENGTH
	ray_mesh.radial_segments = 6
	ray.mesh = ray_mesh
	# Cylinders stand along Y; the aim ray is -Z.
	ray.rotation_degrees = Vector3(-90, 0, 0)
	ray.position = Vector3(0, 0, -Interactor.RAY_LENGTH * 0.5)
	var ray_mat := StandardMaterial3D.new()
	ray_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ray_mat.albedo_color = Color(0.45, 0.72, 1.0, 0.5)
	ray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ray_mat.emission_enabled = true
	ray_mat.emission = Color(0.3, 0.6, 1.0)
	ray_mat.emission_energy_multiplier = 1.6
	ray.material_override = ray_mat
	ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	controller.add_child(ray)

	var tip := MeshInstance3D.new()
	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = 0.006
	tip_mesh.height = 0.012
	tip_mesh.radial_segments = 10
	tip_mesh.rings = 6
	tip.mesh = tip_mesh
	tip.position = TIP_OFFSET
	tip.material_override = ray_mat
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	controller.add_child(tip)

	# The interactor is a CHILD of the controller rather than the controller itself, so a
	# hand-tracked pinch and a trigger pull are the same code with a different action name.
	var hand := XRInteractor.new()
	hand.name = "Interactor"
	hand.controller = controller
	hand.press_action = PRESS_ACTION
	controller.add_child(hand)

	return controller


## Where this controller would touch the floor: its tip, in world space.
func tip_of(controller: XRController3D) -> Vector3:
	return controller.global_transform * TIP_OFFSET


func _process(_delta: float) -> void:
	if left == null or room_anchor == null:
		return
	var down := left.is_button_pressed(CALIBRATE_ACTION)
	# Edge-triggered. A held button is one press; polling the level would take forty marks in
	# the time it takes to lift a thumb.
	if down and not _calibrate_was_down:
		_take_mark()
	_calibrate_was_down = down


func _take_mark() -> void:
	match _marks_taken:
		0:
			room_anchor.mark_origin(tip_of(left))
			_marks_taken = 1
		1:
			# A refused second mark means the two points were too close to fix a direction. The
			# rig stays on step 1 so the next press retries it, rather than silently accepting
			# a frame built from a guess.
			if room_anchor.mark_forward(tip_of(left)):
				_marks_taken = 2
		_:
			room_anchor.mark_origin(tip_of(left))
			_marks_taken = 1
	calibration_step.emit(_marks_taken, 2)
