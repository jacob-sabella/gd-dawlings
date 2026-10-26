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
## to do it again, not wanting to find a menu. Not while the left hand's fingers play, when that
## button is its little finger (`watch_calibration`).

signal calibration_step(step: int, total: int)
## The way out of whatever has been put in front of your face: the menu button on a controller,
## or both bare hands made into fists and held there for ESCAPE_HOLD. What Escape is on a
## keyboard (studio.gd), because a panel pinned to the face whose handle you cannot find is a
## panel you cannot otherwise get rid of.
signal escape_requested
## The menu button held down for MENU_HOLD: the 2D view, up in front of you or put away. A tap
## is still the way out (above), and comes first, so whatever is in the way is gone before the
## panel arrives.
signal flat_requested

## The tip of the controller, not its tracked centre. A controller's pose is reported somewhere
## around the user's fist; the point they will actually press against a floor mark is ahead of
## it and below it, and calibrating against the fist puts the whole room off by a hand.
const TIP_OFFSET := Vector3(0, -0.015, -0.075)

const CALIBRATE_ACTION := &"by_button"
const PRESS_ACTION := &"trigger_click"
const MENU_ACTION := &"menu_button"
const FIST_ACTION := &"grip_click"
const ESCAPE_HOLD := 0.5
const MENU_HOLD := 0.8
## Where each bare hand's joints are reported.
const HAND_TRACKERS := {&"left_hand": &"/user/hand_tracker/left", &"right_hand": &"/user/hand_tracker/right"}

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
var _menu_was_down := false
var _fists_for := 0.0
var _menu_for := 0.0
## Per hand (the controller node): its fingertip and its drawn joints.
var pokes: Dictionary = {}
var skeletons: Dictionary = {}
## Per hand (the controller node): its pinch ray (XRInteractor) and its readings (HandGestures).
var interactors: Dictionary = {}
var gestures: Dictionary = {}


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
	controller.set_meta(&"ray", ray)
	controller.set_meta(&"ray_tip", tip)

	# A bare hand, as well: its fingertip touches the gear directly (PokeInteractor), and its
	# joints are drawn so you can see it is being tracked. Both sit idle while a controller is
	# held, when the joint tracker has no data.
	var poke := PokeInteractor.new()
	poke.name = node_name + "Fingertip"
	poke.tracker_name = HAND_TRACKERS[tracker]
	poke.origin = self
	add_child(poke)
	pokes[controller] = poke
	var skeleton := HandSkeleton.new()
	skeleton.name = node_name + "Joints"
	skeleton.tracker_name = HAND_TRACKERS[tracker]
	add_child(skeleton)
	skeletons[controller] = skeleton
	var reading := HandGestures.new()
	reading.name = node_name + "Gestures"
	reading.tracker_name = HAND_TRACKERS[tracker]
	reading.side = -1 if tracker == &"left_hand" else 1
	reading.origin = self
	reading.head = head
	add_child(reading)
	gestures[controller] = reading
	hand.gestures = reading
	interactors[controller] = hand

	return controller


## Where this controller would touch the floor: its tip, in world space.
func tip_of(controller: XRController3D) -> Vector3:
	return controller.global_transform * TIP_OFFSET


func _process(delta: float) -> void:
	_show_hands()
	_watch_escape(delta)
	if left == null or room_anchor == null:
		return
	watch_calibration(left.is_button_pressed(CALIBRATE_ACTION))


## One frame of the calibration button, `down` or not. Edge-triggered: a held button is one
## press; polling the level would take forty marks in the time it takes to lift a thumb.
##
## The left hand's B/Y is its little finger while that hand's fingers play (fingertip notes), so
## no press then is a mark. The button is still followed all the while, so a Y held down as the
## fingers stop playing is not a fresh press either: only one pressed after it is.
func watch_calibration(down: bool) -> void:
	if down and not _calibrate_was_down and not left_fingers_play():
		_take_mark()
	_calibrate_was_down = down


## Whether the left hand's fingers are playing (Interactor.fingers_play), on its pinch ray.
func left_fingers_play() -> bool:
	var hand: XRInteractor = interactors.get(left) as XRInteractor if left != null else null
	return hand != null and is_instance_valid(hand) and hand.fingers_play


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


## A fingertip on something lights its tip, and the pinch ray of that hand goes away while it is:
## a ray sticking out past the fader you are touching says you are pointing at what is behind it.
## It goes too while the hand's fingers play (fingertip notes, Interactor.fingers_play): its
## pinches and trigger are notes then and grab nothing, and a ray would say they still did.
## The ray's ball, the controller's tip, is not drawn on a bare hand, which has no tip there.
func _show_hands() -> void:
	for controller in pokes:
		var poke: PokeInteractor = pokes[controller]
		var touching := poke.tracked() and (poke.held != null or poke.hovered != null)
		(skeletons[controller] as HandSkeleton).touching = poke.held != null
		var ray := controller.get_meta(&"ray") as Node3D
		var hand := interactors.get(controller) as Interactor
		var playing := hand != null and is_instance_valid(hand) and hand.fingers_play
		ray.visible = not touching and not playing
		(controller.get_meta(&"ray_tip") as Node3D).visible = not poke.tracked()


func _watch_escape(delta: float) -> void:
	var menu := false
	var fists := 0
	for controller in [left, right]:
		if controller == null:
			continue
		menu = menu or controller.is_button_pressed(MENU_ACTION)
		if (pokes[controller] as PokeInteractor).tracked() and controller.is_button_pressed(FIST_ACTION):
			fists += 1
	if menu and not _menu_was_down:
		escape_requested.emit()
	_menu_was_down = menu
	if menu:
		_menu_for += delta
		if _menu_for >= MENU_HOLD and _menu_for - delta < MENU_HOLD:
			flat_requested.emit()
	else:
		_menu_for = 0.0
	if fists == 2:
		_fists_for += delta
		if _fists_for >= ESCAPE_HOLD and _fists_for - delta < ESCAPE_HOLD:
			escape_requested.emit()
	else:
		_fists_for = 0.0
