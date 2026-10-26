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
## The play space has just been put somewhere else (`travel`), or back `home`: the moment of the
## cut, under the veil, so whatever follows the head (the body frame) can take the new place
## whole rather than chase it.
signal travelled(home: bool)

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

## GOING SOMEWHERE (docs/spatial_loop.md part two, slice 11). A play space is about two metres
## square and the live room's instruments are several metres behind the desk, so a headset player
## cannot walk to them. `travel(to)` moves the whole play space instead: the rig (this
## XROrigin3D) is put with its centre on `to`'s floor point, its forward along `to`'s, so where
## the player stands and faces inside their own play space is kept. The calibration is not
## touched: RoomAnchor holds where the session's frame is, and the floor marks are taken in the
## play space as it stood at `home` (`untravelled`), so marking the floor is the same wherever
## the player has gone.
##
## It is a cut, never a glide: a view that moves while the body stands still is what makes
## people sick. The cut happens behind a veil, a black sphere round the head, that closes over
## FADE and opens again over FADE; a fade of 0 is a plain cut (Ergonomics.motion_scale at 0).
const FADE := 0.15
## The veil's radius round the eye: inside the hands, and drawn over everything regardless.
const VEIL_RADIUS := 0.25
## Where the play space stands when it has gone nowhere, in the parent's frame. Taken from the
## rig's own transform as it enters the tree, and set by whoever knows where home is (`settle`):
## the studio puts a VR player's at the mix position, in front of the desk.
var home := Transform3D.IDENTITY
## Whether the play space is somewhere other than `home`.
var away := false
var _veil: MeshInstance3D
var _veil_material: StandardMaterial3D
var _trip: Tween

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
	home = transform
	_build_veil()

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
	# Where the tip is in the play space as it stands at home: a mark is a spot on the real floor,
	# and the real floor did not move when the play space travelled.
	var tip := untravelled(tip_of(left))
	match _marks_taken:
		0:
			room_anchor.mark_origin(tip)
			_marks_taken = 1
		1:
			# A refused second mark means the two points were too close to fix a direction. The
			# rig stays on step 1 so the next press retries it, rather than silently accepting
			# a frame built from a guess.
			if room_anchor.mark_forward(tip):
				_marks_taken = 2
		_:
			room_anchor.mark_origin(tip)
			_marks_taken = 1
	calibration_step.emit(_marks_taken, 2)


# --- going somewhere --------------------------------------------------------------------------

## Put the play space's centre at `to` (global; its floor point and the way it faces, levelled:
## only its yaw is taken), behind the veil, over `fade` seconds each way, or at once with a fade
## of 0. A travel already under way is overtaken from wherever its veil has got to.
func travel(to: Transform3D, fade := FADE) -> void:
	var ahead := -to.basis.z
	ahead.y = 0.0
	if ahead.length() < 0.001:
		ahead = Vector3.FORWARD
	var put := Transform3D(Basis.looking_at(ahead.normalized(), Vector3.UP), Vector3(to.origin.x, 0.0, to.origin.z))
	var parent := get_parent() as Node3D
	if parent != null and parent.is_inside_tree():
		put = parent.global_transform.affine_inverse() * put
	_go(put, true, fade)


## Back to `home`, the mix position, the same way.
func travel_home(fade := FADE) -> void:
	_go(home, false, fade)


## Make `at` (in the parent's frame) home, and put the play space there now unless it is away,
## at once and without the veil: this is where it starts, not a trip. Floor marks taken from
## here on are where they are with the play space standing here (`untravelled`), which is the
## same real floor for everyone who marks it from a home of their own.
func settle(at: Transform3D) -> void:
	home = at
	if not away:
		transform = at


## Whether the veil is closing or opening on a travel.
func travelling() -> bool:
	return _trip != null and _trip.is_valid() and _trip.is_running()


## How closed the veil is, 0 (open, not drawn) to 1 (black).
func veil() -> float:
	return _veil_material.albedo_color.a if _veil_material != null and _veil.visible else 0.0


## `point` (global) as it would be with the play space at home: what a floor mark taken here is
## in the room's own terms.
func untravelled(point: Vector3) -> Vector3:
	if not away:
		return point
	var at_home := home
	var parent := get_parent() as Node3D
	if parent != null and parent.is_inside_tree():
		at_home = parent.global_transform * home
	return at_home * (global_transform.affine_inverse() * point)


func _go(to: Transform3D, away_after: bool, fade: float) -> void:
	if _trip != null and _trip.is_valid():
		_trip.kill()
	if fade <= 0.0 or not is_inside_tree():
		_arrive(to, away_after)
		_show_veil(0.0)
		return
	var from := veil()
	_trip = create_tween()
	_trip.tween_method(_show_veil, from, 1.0, fade * (1.0 - from))
	_trip.tween_callback(_arrive.bind(to, away_after))
	_trip.tween_method(_show_veil, 1.0, 0.0, fade)


func _arrive(to: Transform3D, away_after: bool) -> void:
	transform = to
	away = away_after
	travelled.emit(not away_after)


func _show_veil(closed: float) -> void:
	if _veil == null:
		return
	_veil_material.albedo_color.a = clampf(closed, 0.0, 1.0)
	_veil.visible = closed > 0.0


## A black sphere round the eye, drawn last and through everything: the hands too, which are
## outside it, since a hand left lit in the dark is the one thing that would show the room moving.
## Never in a mirror (Mirror.NOT_REFLECTED), where it would be a black ball on your ghost's head.
func _build_veil() -> void:
	_veil = MeshInstance3D.new()
	_veil.name = "Veil"
	var ball := SphereMesh.new()
	ball.radius = VEIL_RADIUS
	ball.height = VEIL_RADIUS * 2.0
	ball.radial_segments = 16
	ball.rings = 8
	_veil.mesh = ball
	_veil_material = StandardMaterial3D.new()
	_veil_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_veil_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_veil_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_veil_material.no_depth_test = true
	_veil_material.render_priority = Material.RENDER_PRIORITY_MAX
	_veil_material.albedo_color = Color(0, 0, 0, 0)
	_veil.material_override = _veil_material
	_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_veil.layers = Mirror.NOT_REFLECTED
	_veil.visible = false
	head.add_child(_veil)


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
		if escape_fist((pokes[controller] as PokeInteractor).tracked(), controller.is_button_pressed(FIST_ACTION),
				interactors.get(controller) as Interactor):
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
	watch_fists(fists, delta)


## Whether a hand counts toward the two-fists escape: a tracked bare hand made into a fist, and
## carrying nothing. A shaker held in a closed hand is a fist too (XRInteractor.step_hold), and
## shaking it with both hands, or holding it in one while the other makes a fist, is not a way out.
static func escape_fist(tracked: bool, fist: bool, hand: Interactor) -> bool:
	return tracked and fist and not (hand != null and is_instance_valid(hand) and is_instance_valid(hand.carrying))


## `fists` hands counting toward the escape this frame, `delta` on: both, held for ESCAPE_HOLD,
## is the way out, said once a hold.
func watch_fists(fists: int, delta: float) -> void:
	if fists == 2:
		_fists_for += delta
		if _fists_for >= ESCAPE_HOLD and _fists_for - delta < ESCAPE_HOLD:
			escape_requested.emit()
	else:
		_fists_for = 0.0
