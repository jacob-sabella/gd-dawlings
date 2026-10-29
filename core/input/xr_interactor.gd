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
	# A hand closed round a shaker is not pinching anything, whatever the runtime reads off a fist.
	if controller == null or fingers_play or fist_holding:
		return false
	return controller.is_button_pressed(press_action)


# --- readings ------------------------------------------------------------------------------
#
# A bare hand answers from its HandGestures; a controller is the same hand with buttons for
# fingers and its grip for a palm (docs/spatial_loop.md slice 7). A controller is held thumb up on
# its top face with the palm round its side, facing in toward the other hand: OpenXR's grip pose
# puts its X axis through the palm, so the palm faces -X in the right hand and +X in the left.
# Held normally it faces sideways; turned a quarter outward, the forearm's own easy turn, it is
# palm up. Its tilt is its aim's.

## This hand's readings while it is a tracked bare hand: set by the rig.
var gestures: HandGestures = null
## The buttons the ring and little fingers press: A or X, and B or Y. The left hand's B/Y is the
## rig's calibration button too, which it leaves alone while this hand's fingers play (XRRig).
@export var ring_action: StringName = &"ax_button"
@export var little_action: StringName = &"by_button"
## How far the trigger and the grip are in, 0..1: how fast a fingertip note's press came.
@export var trigger_travel_action: StringName = &"trigger"
@export var grip_travel_action: StringName = &"grip"


func _reads_hand() -> bool:
	return gestures != null and is_instance_valid(gestures) and gestures.tracked


func finger_pinches() -> int:
	if _reads_hand():
		return gestures.pinched
	if controller == null or bare_hand():
		return 0
	return HandPose.mask_of(controller.is_button_pressed(press_action),
			controller.is_button_pressed(grip_action), controller.is_button_pressed(ring_action),
			controller.is_button_pressed(little_action))


func palm_up() -> bool:
	if _reads_hand():
		return gestures.palm_up
	if controller == null or bare_hand():
		return false
	return HandPose.faces_up(-hand_side() * aim().basis.x)


## A bare hand's palm toward the eyes; a controller in the hand has no palm the runtime reads.
func faces_head() -> bool:
	return _reads_hand() and gestures.faces_head


## A bare hand by its curls (HandPose.is_open); a controller with no finger button down.
func hand_open() -> bool:
	if _reads_hand():
		return gestures.open
	if controller == null or bare_hand():
		return false
	return finger_pinches() == 0


## A bare hand's fingers' gaps to the thumb; a controller's trigger and grip travel (the index and
## the middle), its A/X and B/Y buttons with none to read.
func finger_travel() -> PackedFloat32Array:
	if _reads_hand():
		return gestures.travel
	if controller == null or bare_hand():
		return PackedFloat32Array()
	return PackedFloat32Array([controller.get_float(trigger_travel_action),
			controller.get_float(grip_travel_action), NAN, NAN])


## What a clap reads of this hand (Clap.reading): [the middle of the palm, the way it faces] for a
## tracked bare hand, [the grip point, Vector3.ZERO] for a controller, whose palm is round its
## grip and not read; empty for a bare hand out of tracking.
func clap_palm() -> Array:
	if _reads_hand():
		return [gestures.palm(), HandPose.palm_normal(gestures.joints, gestures.side)]
	if controller == null or bare_hand() or not controller.is_inside_tree():
		return []
	return [controller.global_position, Vector3.ZERO]


## -1 for the left hand's controller, 1 for the right (HandPose's `side`), from its tracker.
func hand_side() -> int:
	return -1 if controller != null and controller.tracker == &"left_hand" else 1


func tilt() -> Vector2:
	if _reads_hand():
		return gestures.tilt
	if controller == null or bare_hand():
		return Vector2.ZERO
	return HandPose.tilt_of(aim().basis.orthonormalized())


## A bare hand's palm, unclamped; NAN while it is out of tracking. A controller's aim, read held
## thumb up as level (where a bare hand is level palm down): a bend is the roll since its note
## began, so either start bends the same.
func tilt_angles() -> Vector2:
	if _reads_hand():
		return gestures.angles
	if controller == null or bare_hand():
		return Vector2(NAN, NAN)
	return HandPose.angles_of(aim().basis.orthonormalized())


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


## The thumbstick nudges whatever this hand hovers or holds (ControlAffordance.nudge), a notch a
## flick, as the mouse wheel does what the cursor is on: forward is more. Past FLICK_PAST it
## flicks; held there it flicks again every FLICK_REPEAT; it flicks again from rest only once it
## has come back under FLICK_BACK, so a stick let go and springing back is not a second notch.
## A bare hand has no stick, so anything that nudges has buttons a finger can press as well.
@export var stick_action: StringName = &"primary"
const FLICK_PAST := 0.6
const FLICK_BACK := 0.3
const FLICK_REPEAT := 0.25

## The stick's click: on the chord hand, what turns the chord stick on and off (ChordHand).
@export var stick_click_action: StringName = &"primary_click"
## The chord stick is on (docs/spatial_loop.md part two, slice 32): the stick picks this player's
## chord (ChordHand.stick_step), so it nudges nothing meanwhile.
var chord_stick := false
## The chord stick went off with the stick still out: it nudges again once it has come back.
var _chords_spent := false

## The way the stick is flicked now (1 forward, -1 back), 0 when it is back and ready.
var _flicked := 0
var _flick_wait := 0.0


## This hand points by its stick click, held: the hand that is not the chord hand (its click is
## the chord stick's), set by the studio (docs/spatial_loop.md part two, "Gestures do not collide").
## A bare hand points by its pose, either hand (HandPose.pointing).
var points_by_stick := false


## This frame's `pointing`: a tracked bare hand by HandPose.pointing (held on by the index alone
## once it points), a controller by its stick click while `points_by_stick`; nothing else points.
func read_pointing() -> void:
	if _reads_hand():
		pointing = HandPose.pointing(gestures.joints, gestures.side, pointing)
	elif controller != null and not bare_hand() and points_by_stick:
		pointing = stick_clicked()
	else:
		pointing = false


## The thumbstick, -1..1 each way; nothing for a bare hand.
func stick() -> Vector2:
	if controller == null:
		return Vector2.ZERO
	return controller.get_vector2(stick_action)


## Whether the stick is clicked down now; never for a bare hand.
func stick_clicked() -> bool:
	if controller == null or bare_hand():
		return false
	return controller.is_button_pressed(stick_click_action)


## One frame of the stick at `along` (its forward reading), `delta` seconds on: the notches it
## nudged, signed, 0 for none or when nothing took them. None while the stick picks chords
## (`chord_stick`); a push held as it goes off is not a flick until it has come back.
func flick(along: float, delta: float) -> int:
	if chord_stick or _chords_spent:
		_flicked = 0
		_chords_spent = chord_stick or absf(along) >= FLICK_BACK
		return 0
	if _flicked == 0:
		if absf(along) < FLICK_PAST:
			return 0
		_flicked = 1 if along > 0.0 else -1
		_flick_wait = FLICK_REPEAT
		return _nudge_by_stick(_flicked)
	if along * _flicked < FLICK_BACK:
		_flicked = 0
		return 0
	if along * _flicked < FLICK_PAST:
		# Eased off but not let go: no repeats, and the next push past starts the wait afresh.
		_flick_wait = FLICK_REPEAT
		return 0
	_flick_wait -= delta
	if _flick_wait > 0.0:
		return 0
	_flick_wait += FLICK_REPEAT
	return _nudge_by_stick(_flicked)


func _nudge_by_stick(notches: int) -> int:
	_forget_freed()
	# A tool that takes the stick (`tool_stick`) has it first, whatever the hand is over.
	if tool.is_valid() and tool_stick.is_valid() and tool_stick.call(self, notches, fine()):
		return notches
	var target: ControlAffordance = held if held != null else hovered
	if target != null and target.nudge(self, notches, fine()):
		return notches
	return 0


func _physics_process(delta: float) -> void:
	_steady_aim(delta)
	_count_roll()
	read_pointing()
	super(delta)
	flick(stick().y, delta)
	var now := Time.get_ticks_msec() / 1000.0
	_trail.append([now, aim().origin])
	while _trail.size() > 2 and now - float(_trail[0][0]) > FLICK_WINDOW:
		_trail.pop_front()
	step_hold(delta)
	var gripping := controller != null and controller.is_button_pressed(grip_action)
	# A closed bare hand's own fist reads as the grip too; what it holds is let go by `step_hold`.
	if _gripping and not gripping and carrying != null and is_instance_valid(carrying) and not fingers_play \
			and not fist_holding:
		var moving := hand_velocity()
		if moving.length() > FLICK_SPEED:
			throw_item(moving, aim().basis.x * -moving.length() * 1.5)
		else:
			put_down()
	_gripping = gripping


func catch_reach() -> float:
	return CATCH_REACH


## A cassette pushed into a lane's face, a strip or a voice pastes there (docs/spatial_loop.md part
## two, slice 24), as the trigger does while the grip holds it.
func pushes_to_paste() -> bool:
	return true


## A tracked bare hand pastes by its push alone: it has no trigger to pull.
func paste_press_words() -> String:
	return "a push in" if bare_hand() else super()


## A bare hand's push counts only while it is tracked with every joint seen (HandGestures.confident),
## this frame and the last. A controller holds still where it was last seen while its tracking is
## lost, and the jump when it comes back is longer than a push (PUSH_MAX_STEP).
func push_tracked() -> bool:
	if not bare_hand() and not _reads_hand():
		return true
	return gestures != null and is_instance_valid(gestures) and gestures.tracked and gestures.confident


## The trigger, with an empty hand up by your ear, takes off what you have on your head.
func head_reach() -> float:
	return HEAD_REACH


## How much further than HEAD_REACH a cassette at the ear goes before it is away from it (m), so a
## hand that wavers at the edge does not start and stop it.
const EAR_LEAVE := 0.06
var _at_ear := false


## A cassette held up by the head (docs/spatial_loop.md part two, slice 25): its middle within
## HEAD_REACH of the eyes, as headphones are put on; away again past HEAD_REACH + EAR_LEAVE.
func cassette_at_ear() -> CassetteItem:
	var c := _ear_cassette()
	if c == null:
		_at_ear = false
		return null
	var d := c.middle().distance_to(head_point())
	_at_ear = d < (HEAD_REACH + EAR_LEAVE if _at_ear else HEAD_REACH)
	return c if _at_ear else null


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


# --- a closed bare hand round hand percussion (docs/spatial_loop.md slice 17) ----------------
#
# A tracked bare hand takes hold of a shaker or a tambourine (InstrumentItem.held_in_fist) by
# closing round it, as a hand holds one: three fingers past HandPose.HOLD_CURL with the middle of
# the palm within HandPose.GRIP_REACH of its grip, not a pinch. It keeps it while it is closed, or
# half closed, and lets go only once the hand has been open (HandPose.is_open) for LET_GO_AFTER
# with every joint seen (HandGestures.confident). A hand still tracked but with some joints only
# guessed -- fingers hidden inside a fist, or blurred by a fast shake, are just when a runtime
# infers them -- goes on carrying it at its palm and playing its strokes; only letting go and the
# throw wait for confident frames. A hand that drops out of tracking altogether keeps it where it
# was last seen for LOST_HOLD, and sends it home after that, never on the first lost frame. A
# throw is only ever from how fast the palm went over confident frames (`_palm_trail`), so a hand
# that vanishes on one side and reappears on the other throws nothing. A pinch still carries one
# too, the way it did.

## Open, and seen, this long (s) before a closed hand lets go of what it holds.
const LET_GO_AFTER := 0.1
## Out of tracking this long (s) while holding, and what it held goes home. A hand tracked with
## guessed joints is not out of tracking.
const LOST_HOLD := 0.4
## How much further a held instrument's end swings than the middle of the palm does
## (`shake_lever`): a wrist's shake turns the hand, and the shaker's far end goes further.
const PALM_LEVER := 1.6
## Where a closed hand carries what it holds: this far into the fist from the middle of the palm (m).
const FIST_DEPTH := 0.02

## Whether what this hand carries is held by a closed bare hand (`step_hold`).
var fist_holding := false
## Whether the hand was closed when last tracked (confidently or not): a hold is taken as the hand
## closes, not by a fist already made and moved past the shelf, even through a guess or a dropout.
var _closed_was := false
var _open_for := 0.0
var _lost_for := 0.0
## Where the closed hand was last seen, as `carry_pose`: what it holds rides there while it is lost.
var _fist_seen := Transform3D.IDENTITY
## [time, palm] of the closed hand's confident frames over FLICK_WINDOW, for its throw.
var _palm_trail: Array = []
var _hold_clock := 0.0


func carry_pose() -> Transform3D:
	if fist_holding:
		return _fist_seen
	return super()


## A bare hand's palm (HandGestures.palm), where its wrist's shake is felt; while a closed hand is
## out of tracking, where it was last seen. A controller's own pose otherwise.
func shake_point() -> Vector3:
	if _reads_hand():
		return gestures.palm()
	if fist_holding:
		return _fist_seen.origin
	return super()


## A bare hand's palm is seen while the hand is tracked at all, guessed joints or not: a fast shake
## is just when a runtime infers some, and it is still the hand's shake.
func shake_tracked() -> bool:
	if gestures != null and is_instance_valid(gestures) and (fist_holding or gestures.tracked or bare_hand()):
		return gestures.tracked
	return true


func shake_lever() -> float:
	return PALM_LEVER if _reads_hand() or fist_holding else 1.0


## One frame of a closed bare hand round hand percussion, `delta` on: taking hold as the hand
## closes round one, keeping it, letting go of it, holding it through a dropout. Called each
## physics frame; the suite steps it itself.
func step_hold(delta: float) -> void:
	_hold_clock += delta
	var g := gestures if gestures != null and is_instance_valid(gestures) else null
	var seen := g != null and g.tracked
	var sure := seen and g.confident
	if fist_holding:
		if not is_instance_valid(carrying) or carrying.carried_by != self or not carrying.in_hand():
			# Taken by the host for somebody else, or put away some other way: not ours to hold.
			_end_hold()
			return
		if seen:
			# Tracked, if only guessed at in places: still carried at the palm, still held.
			_lost_for = 0.0
			_fist_seen = _fist_pose(g)
			if not sure:
				# A guess neither opens the hand nor goes into a throw.
				_open_for = 0.0
				_palm_trail.clear()
				return
			_palm_trail.append([_hold_clock, g.palm()])
			while _palm_trail.size() > 2 and _hold_clock - float(_palm_trail[0][0]) > FLICK_WINDOW:
				_palm_trail.pop_front()
			_open_for = _open_for + delta if g.open else 0.0
			if _open_for >= LET_GO_AFTER - 0.0001:
				_let_go_of_fist()
			return
		# Lost: held where it was last seen, and no throw from what follows.
		_open_for = 0.0
		_palm_trail.clear()
		_lost_for += delta
		if _lost_for >= LOST_HOLD - 0.0001:
			var item := carrying
			_end_hold()
			var room := ItemRoom.of(item)
			if room != null:
				room.send_home(item)
			else:
				item.go_home()
		return
	# The closing edge is read off every tracked frame, guessed joints or not: fingers closing round
	# a grip are just the ones a runtime hides, and a guess on the way must not make a fist already
	# made look newly closed. Lost altogether, the hand is as it was last seen.
	if not seen:
		return
	var closing := g.closed and not _closed_was
	_closed_was = g.closed
	if not closing or carrying != null or held != null or fingers_play:
		return
	var item := grippable(g.joints)
	if item == null:
		return
	# Pose first: the item hops to where the hand is, not to the pinch ray's.
	_fist_seen = _fist_pose(g)
	fist_holding = true
	pick_up(item)
	if carrying != item:
		fist_holding = false
		return
	_open_for = 0.0
	_lost_for = 0.0
	_palm_trail = [[_hold_clock, g.palm()]]


## The hand percussion a hand posed as `joints` (global space) is closed round: the nearest whose
## grip (InstrumentItem.grip_point) it grips (HandPose.grips), on a shelf or the floor and not in
## anyone's hand or the air. Null for none.
func grippable(joints: PackedVector3Array) -> InstrumentItem:
	if not is_inside_tree() or not HandPose.closed(joints):
		return null
	var best: InstrumentItem = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(Item.ITEMS):
		var item := node as InstrumentItem
		if item == null or not item.held_in_fist() or item.state == Item.State.HELD or item.is_flying() \
				or not item.may_hold():
			continue
		var grip := item.grip_point()
		if not HandPose.grips(joints, grip):
			continue
		var d := joints[HandPose.PALM].distance_to(grip)
		if d < best_d:
			best = item
			best_d = d
	return best


## The closed hand's carry: the palm's pose, FIST_DEPTH in toward the fingers.
func _fist_pose(g: HandGestures) -> Transform3D:
	var palm := g.palm_pose()
	return Transform3D(palm.basis, palm.origin - palm.basis.y * FIST_DEPTH)


## The closed hand has opened: thrown at the palm's speed over its last confident frames if that
## is a flick, put down where the hand points otherwise.
func _let_go_of_fist() -> void:
	var moving := palm_velocity()
	if moving.length() > FLICK_SPEED:
		throw_item(moving, _fist_seen.basis.x * -moving.length() * 1.5)
	else:
		put_down()
	_end_hold()


## How fast the closed hand's palm went over its last confident frames (FLICK_WINDOW); nothing
## while it is lost or has been seen only once since.
func palm_velocity() -> Vector3:
	if _palm_trail.size() < 2:
		return Vector3.ZERO
	var first: Array = _palm_trail[0]
	var last: Array = _palm_trail[-1]
	var span := float(last[0]) - float(first[0])
	return (last[1] - first[1]) / span if span > 0.0001 else Vector3.ZERO


func _end_hold() -> void:
	fist_holding = false
	_open_for = 0.0
	_lost_for = 0.0
	_palm_trail.clear()
	# The hand that let go is still closed, or about to be: it takes hold again only by closing anew.
	_closed_was = true
