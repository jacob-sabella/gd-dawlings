class_name HandPose
extends RefCounted

## What a bare hand is doing, read from where its joints are: how big it is, how far each finger
## is curled, which fingers the thumb is pinching, which way the palm faces and how far the hand
## is tipped (docs/spatial_loop.md slice 7).
##
## Static and pure over the 26 joint positions, in XRHandTracker's order and any one space, so
## the suite can test it with hands it poses itself (`posed`) and no headset. HandGestures reads
## a tracker into it each physics frame; instruments read only what comes out, through
## Interactor's readings, so a controller and a mouse can give the same answers.
##
## A hand's positions alone cannot say which hand it is: a left hand is a mirrored right one, and
## the palm faces the other way. So what depends on the palm's facing takes `side`, -1 for the
## left hand and 1 for the right, as a Glove does.

## The hand everything is sized against: wrist to the middle finger's knuckle (its proximal
## joint), on an adult's hand.
const REFERENCE_SIZE := 0.095
## A pinch closes when thumb tip and fingertip come within PINCH_IN, and opens only once they
## are PINCH_OUT apart, at the reference size: the gap between them is what keeps a held pinch
## from flickering while the hand trembles. Both scale with the hand and with Ergonomics'
## `finger_scale`.
const PINCH_IN := 0.018
const PINCH_OUT := 0.030
## How far apart thumb tip and fingertip are, at the reference size, for a finger to count as all
## the way open in its `travel`: a relaxed open hand's gap.
const TRAVEL_FROM := 0.09
## A finger curled less than this is open, for `is_open` (0 open to 1 curled tight).
const OPEN_CURL := 0.3
## A finger curled past this is closed round something, for `closed` and `grips`: a hand holding
## a shaker, not a fist clenched tight (docs/spatial_loop.md slice 17).
const HOLD_CURL := 0.6
## How many of the four fingers have to be past HOLD_CURL for the hand to be closed: three, so a
## little finger left out, or one the runtime reads wrong, still holds.
const HOLD_FINGERS := 3
## How near the middle of the palm a thing's grip has to be for a closed hand to hold it (m).
const GRIP_REACH := 0.06
## The palm's normal within this of straight up is palm up (degrees).
const PALM_UP_WITHIN := 35.0
## The palm's normal within this of the way to the eyes faces the head (degrees). On Quest the
## runtime takes a pinch made like that for its own menu, so nothing here is played that way.
const FACES_HEAD_WITHIN := 60.0
## The most a tilt reads, either way, in pitch and in roll (degrees): tipped this far is 1.
const TILT_MOST := 45.0

## The pinch mask: one bit a finger, the thumb pinching it.
const INDEX := 1
const MIDDLE := 2
const RING := 4
const LITTLE := 8
const FINGER_BITS: Array[int] = [INDEX, MIDDLE, RING, LITTLE]

const WRIST := XRHandTracker.HAND_JOINT_WRIST
const PALM := XRHandTracker.HAND_JOINT_PALM
const THUMB_TIP := XRHandTracker.HAND_JOINT_THUMB_TIP
const INDEX_PROXIMAL := XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL
const MIDDLE_PROXIMAL := XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_PROXIMAL
const LITTLE_PROXIMAL := XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL
## Each fingertip, index to little, in FINGER_BITS' order.
const TIPS: Array[int] = [XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP,
		XRHandTracker.HAND_JOINT_RING_FINGER_TIP, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP]
## Each digit's joints from the base of its metacarpal out to its tip, thumb first. A curl is the
## bending along one of these.
const CHAINS: Array = [
	[2, 3, 4, 5],
	[6, 7, 8, 9, 10],
	[11, 12, 13, 14, 15],
	[16, 17, 18, 19, 20],
	[21, 22, 23, 24, 25],
]
## How much a digit bends along its chain curled tight, in degrees: the thumb at its two joints,
## a finger at its three (about 90 at the knuckle, 100 at the middle joint, 60 at the last).
const CURL_FULL: Array[float] = [130.0, 250.0, 250.0, 250.0, 250.0]


## Whether `joints` is a whole hand: one position for every joint.
static func whole(joints: PackedVector3Array) -> bool:
	return joints.size() == XRHandTracker.HAND_JOINT_MAX


## How big this hand is: wrist to the middle finger's knuckle (m).
static func size(joints: PackedVector3Array) -> float:
	return joints[WRIST].distance_to(joints[MIDDLE_PROXIMAL])


## How far each digit is curled, thumb to little, 0 open to 1 curled tight: the bending at each of
## its joints added up along it, against how much a fist bends it. The first bend is against the
## palm itself (its metacarpal), so a finger bent back at the knuckle reads as bent too, never
## as less than open.
static func curls(joints: PackedVector3Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for d in CHAINS.size():
		var chain: Array = CHAINS[d]
		var bent := 0.0
		for k in range(1, chain.size() - 1):
			var a: Vector3 = joints[chain[k]] - joints[chain[k - 1]]
			var b: Vector3 = joints[chain[k + 1]] - joints[chain[k]]
			if a.length() > 0.0001 and b.length() > 0.0001:
				bent += a.angle_to(b)
		out.append(clampf(rad_to_deg(bent) / CURL_FULL[d], 0.0, 1.0))
	return out


## How much a pinch's distances are scaled for this hand: its size against the reference, and
## the person's own `finger_scale` (Ergonomics) on top.
static func pinch_scale(joints: PackedVector3Array, finger_scale: float = 1.0) -> float:
	return size(joints) / REFERENCE_SIZE * maxf(finger_scale, 0.05)


## Which fingers the thumb is pinching now, as a mask (INDEX, MIDDLE, RING, LITTLE), given the
## mask `was` from the frame before. A finger not pinched closes under PINCH_IN; one pinched lets
## go only past PINCH_OUT, both scaled by `pinch_scale`.
static func pinches(joints: PackedVector3Array, was: int, finger_scale: float = 1.0) -> int:
	var k := pinch_scale(joints, finger_scale)
	var thumb := joints[THUMB_TIP]
	var out := 0
	for f in FINGER_BITS.size():
		var bit := FINGER_BITS[f]
		var gap := thumb.distance_to(joints[TIPS[f]])
		if gap < (PINCH_OUT if was & bit else PINCH_IN) * k:
			out |= bit
	return out


## How far each finger has come in toward the thumb, index to little, 0 apart by TRAVEL_FROM or
## more to 1 as near as a pinch closes (PINCH_IN), both scaled as `pinches` scales them. How fast
## it rises is how fast a pinch closed: what a fingertip note's velocity comes from.
static func travel(joints: PackedVector3Array, finger_scale: float = 1.0) -> PackedFloat32Array:
	var k := pinch_scale(joints, finger_scale)
	var near := PINCH_IN * k
	var far := TRAVEL_FROM * k
	var out := PackedFloat32Array()
	for f in FINGER_BITS.size():
		var gap := joints[THUMB_TIP].distance_to(joints[TIPS[f]])
		out.append(clampf((far - gap) / maxf(far - near, 0.0001), 0.0, 1.0))
	return out


## Whether the hand is held open: its four fingers each curled under OPEN_CURL and none pinched.
## The thumb is left out, since an open hand's thumb lies where it likes.
static func is_open(joints: PackedVector3Array, pinched: int) -> bool:
	if pinched != 0:
		return false
	var curled := curls(joints)
	for d in range(1, curled.size()):
		if curled[d] >= OPEN_CURL:
			return false
	return true


## Whether the hand is closed round something: HOLD_FINGERS of its four fingers curled past
## HOLD_CURL. Not a pinch: the thumb is left out, as it lies along a shaker or across a hoop.
static func closed(joints: PackedVector3Array) -> bool:
	var curled := curls(joints)
	var past := 0
	for d in range(1, curled.size()):
		if curled[d] > HOLD_CURL:
			past += 1
	return past >= HOLD_FINGERS


## Whether the hand is closed round a grip at `point` (same space): `closed`, with the middle of
## the palm within GRIP_REACH of it.
static func grips(joints: PackedVector3Array, point: Vector3) -> bool:
	return closed(joints) and joints[PALM].distance_to(point) <= GRIP_REACH


## The hand's own frame, from its joints: +X across it to the little finger's side of a right
## hand (its right, held palm down), +Y out of its back and -Z along it, wrist to knuckles. Its
## up is the back of the hand, so the palm faces -Y.
static func frame(joints: PackedVector3Array, side: int) -> Basis:
	var along := (joints[MIDDLE_PROXIMAL] - joints[WRIST]).normalized()
	var across := joints[INDEX_PROXIMAL] - joints[LITTLE_PROXIMAL]
	var back := along.cross(across) * float(signi(side) if side != 0 else 1)
	back = (back - along * back.dot(along)).normalized()
	return Basis(along.cross(back), back, -along)


## The way the palm faces, out of it, in the joints' space.
static func palm_normal(joints: PackedVector3Array, side: int) -> Vector3:
	return -frame(joints, side).y


## A palm facing `normal` is palm up: within PALM_UP_WITHIN of straight up. A controller's palm
## is the underside of its grip, so it answers through here too.
static func faces_up(normal: Vector3) -> bool:
	return normal.length() > 0.0001 and rad_to_deg(normal.angle_to(Vector3.UP)) <= PALM_UP_WITHIN


static func palm_up(joints: PackedVector3Array, side: int) -> bool:
	return faces_up(palm_normal(joints, side))


## Whether the palm faces the eyes at `head`: its normal within FACES_HEAD_WITHIN of the way from
## the middle of the palm to the head. A palm up held in close at the chest faces the head by
## this; held out at arm's length it does not.
static func faces_head(joints: PackedVector3Array, head: Vector3, side: int) -> bool:
	var toward := head - joints[PALM]
	if toward.length() < 0.0001:
		return false
	return rad_to_deg(palm_normal(joints, side).angle_to(toward)) <= FACES_HEAD_WITHIN


## How far the hand is tipped from level, read -1..1 each way: x its roll (positive rolled
## clockwise as its person sees it from behind, its right side down) and y its pitch (positive
## the fingers up), each clamped to TILT_MOST.
static func tilt(joints: PackedVector3Array, side: int) -> Vector2:
	return tilt_of(frame(joints, side))


## The same of any basis held the way a hand is (-Z along it, +Y out of its back): a hand's
## `frame`, or a controller's aim. Roll is measured round the way it points, from the up that is
## level there; pointing straight up or down it has no roll. `angles_of`, clamped and over
## TILT_MOST.
static func tilt_of(basis: Basis) -> Vector2:
	var most := deg_to_rad(TILT_MOST)
	var angles := angles_of(basis)
	return Vector2(clampf(angles.x, -most, most) / most, clampf(angles.y, -most, most) / most)


## How far a hand's own frame is tipped from level, x its roll and y its pitch, as `tilt_of` reads
## them, in radians and unclamped: roll -PI..PI, pitch -PI/2..PI/2. A bend is measured from the
## roll a note began at (Wobble), so it must not saturate for a hand that starts past TILT_MOST, a
## hand plucking the harp palm sideways (docs/spatial_loop.md part two, "A tilt is measured from
## where the note began, unclamped").
static func angles_of(basis: Basis) -> Vector2:
	var along := (-basis.z).normalized()
	var back := basis.y.normalized()
	var pitch := asin(clampf(along.y, -1.0, 1.0))
	var level := Vector3.UP - along * along.y
	var top := back - along * back.dot(along)
	var roll := 0.0
	if level.length() > 0.001 and top.length() > 0.001:
		roll = level.normalized().signed_angle_to(top.normalized(), along)
	return Vector2(roll, pitch)


## `angles_of` a hand's joints.
static func angles(joints: PackedVector3Array, side: int) -> Vector2:
	return angles_of(frame(joints, side))


## A controller's buttons as fingers: the trigger is the index, the grip the middle, A or X the
## ring and B or Y the little finger.
static func mask_of(trigger: bool, grip: bool, ax: bool, by: bool) -> int:
	return (INDEX if trigger else 0) | (MIDDLE if grip else 0) | (RING if ax else 0) | (LITTLE if by else 0)


## The mask's fingers in words, for a card or a shot: `INDEX + RING`, or `none`.
static func pinch_words(mask: int) -> String:
	var names: PackedStringArray = []
	for f in FINGER_BITS.size():
		if mask & FINGER_BITS[f]:
			names.append(["INDEX", "MIDDLE", "RING", "LITTLE"][f])
	return " + ".join(names) if not names.is_empty() else "none"


# --- posing a hand ---------------------------------------------------------------------------
#
# A hand made rather than tracked, for the suite and the shot rig: the readings above are what is
# under test, so the hand they read is built from what it should read as.

## Where each joint of a right hand of the reference size sits, open and palm down: +X its right
## (the little finger's side), +Y its back, -Z its fingers, the middle of the palm at the origin.
const _KNUCKLES: Array[Vector3] = [Vector3(-0.022, 0, -0.045), Vector3(0, 0, -0.0475),
		Vector3(0.02, 0, -0.044), Vector3(0.038, 0, -0.038)]
const _BASES: Array[Vector3] = [Vector3(-0.018, 0, 0.034), Vector3(0, 0, 0.036),
		Vector3(0.012, 0, 0.035), Vector3(0.022, 0, 0.032)]
## Each finger's three bones, knuckle out (m).
const _BONES: Array = [[0.040, 0.024, 0.022], [0.045, 0.028, 0.024], [0.042, 0.026, 0.023],
		[0.032, 0.019, 0.021]]
## How a finger's full bend is shared between its three joints.
const _SHARE: Array[float] = [0.36, 0.40, 0.24]
const _THUMB_BASE := Vector3(-0.02, -0.01, 0.03)
const _THUMB_BONES: Array[float] = [0.04, 0.032, 0.028]
const _THUMB_WAY := Vector3(-0.62, -0.12, -0.78)
## Where a pinch meets, under the index and middle fingers ahead of the palm.
const _PINCH_AT := Vector3(-0.014, -0.034, -0.08)


## A hand posed: digit d curled `curls[d]` (thumb first; a missing one is open), the fingers in
## the mask `pinched` bent to meet the thumb `gap` short of touching it (their tips that far off
## its tip, out toward the back of the hand), `palm` its place and facing (as `frame` reads: +Y
## out of its back, -Z along it; the origin the middle of the palm), `scale` its size against the
## reference, and `side` -1 for a left hand (the right one mirrored). 26 positions in `palm`'s
## space.
static func posed(curl: Array, pinched: int, palm: Transform3D, scale: float = 1.0,
		side: int = 1, gap: float = 0.0) -> PackedVector3Array:
	var at := PackedVector3Array()
	at.resize(XRHandTracker.HAND_JOINT_MAX)
	at[PALM] = Vector3.ZERO
	at[WRIST] = Vector3(0, 0, 0.0475)
	# The thumb, bending in across the palm.
	var thumb_curl := float(curl[0]) if curl.size() > 0 else 0.0
	var way := _THUMB_WAY.normalized()
	var p := _THUMB_BASE
	at[2] = p
	p += way * _THUMB_BONES[0]
	at[3] = p
	var inward := Vector3(0.75, -0.66, 0.0).normalized()
	var axis := way.cross(inward).normalized()
	for k in 2:
		way = way.rotated(axis, deg_to_rad(CURL_FULL[0] * thumb_curl * 0.5))
		p += way * _THUMB_BONES[k + 1]
		at[4 + k] = p
	if pinched != 0:
		# The thumb reaches to where the pinch meets.
		at[THUMB_TIP] = _PINCH_AT
		at[4] = at[3].lerp(_PINCH_AT, 0.5) + Vector3(-0.006, -0.006, 0)
	# The fingers, each from its base through its knuckle, bending toward the palm.
	for f in 4:
		var chain: Array = CHAINS[f + 1]
		at[chain[0]] = _BASES[f]
		at[chain[1]] = _KNUCKLES[f]
		var bones: Array = _BONES[f]
		var along := (_KNUCKLES[f] - _BASES[f]).normalized()
		var bend := along.cross(Vector3.DOWN).normalized()
		if pinched & FINGER_BITS[f]:
			var tip := _PINCH_AT + Vector3.UP * gap / maxf(scale, 0.01)
			var knuckle := _KNUCKLES[f]
			at[chain[2]] = knuckle.lerp(tip, 0.45) + Vector3(0, 0.012, 0)
			at[chain[3]] = knuckle.lerp(tip, 0.75) + Vector3(0, 0.006, 0)
			at[chain[4]] = tip
			continue
		var c := float(curl[f + 1]) if curl.size() > f + 1 else 0.0
		var q := _KNUCKLES[f]
		var dir := along
		for k in 3:
			dir = dir.rotated(bend, deg_to_rad(CURL_FULL[f + 1] * c * _SHARE[k]))
			q += dir * float(bones[k])
			at[chain[k + 2]] = q
	var mirror := Vector3(-1.0 if side < 0 else 1.0, 1.0, 1.0)
	for j in at.size():
		at[j] = palm * (at[j] * mirror * scale)
	return at
