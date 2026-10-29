class_name Strike
extends Node

## Strikes on the instruments that stand still (InstrumentItem with `Item.fixed`, docs/spatial_loop.md
## part two, slice 38): a hand slapping a drum head, a fingertip on a pad, a controller brought down
## on a chime.
##
## Every physics frame it reads where this player's own striking points are: each tracked bare
## hand's five fingertips and the middle of its palm (HandGestures), each poke's fingertip
## (PokeInteractor), and each held controller's tip (XRRig.TIP_OFFSET) and grip point. A strike is
## one of them crossing a fixed instrument's face (InstrumentItem.faces) inward, from outside it to
## inside, faster than STRIKE_MIN along the face's normal (or the instrument's own least,
## InstrumentItem.strike_least: a venue's glass rings at a touch): as hard as it was fast
## (InstrumentItem.velocity_of), on the zone it crossed at (InstrumentItem.zone_at). Only a point
## seen with confidence on both frames counts: a bare hand's every joint seen (HandGestures.confident),
## a controller's pose tracked rather than guessed (XRPose's HIGH confidence). So a hand that drops
## out of tracking on one side of a head and comes back on the other plays nothing, and neither does
## a jump of more than MOST_STEP in one frame.
##
## One hand's fingers and palm landing together (a slap, a poke's fingertip and the same finger's
## joint) are one strike, the fastest of them, and the same hand strikes the same instrument again
## only after AGAIN_AFTER. A bandmate's strikes are not here: their hands have no joints on this
## machine, and their hits arrive as Session.item_hit, heard from where the instrument stands.
##
## The mouse strikes by a click instead (Item.struck_by, `click_velocity`), and so does a
## controller's trigger or a pinch aimed at one from across the room.

## Every fixed instrument in the tree, which joins this group as it enters it.
const GROUP := &"fixed_instruments"
## Slower than this (m/s, into the face) is a touch, not a strike.
const STRIKE_MIN := 0.4
## How hard a click strikes, and a Shift-click.
const CLICK := 96
const CLICK_SOFT := 64
## The least time (s) between two strikes by one hand on one instrument: a slap's fingers and palm
## cross over a frame or two, and are one.
const AGAIN_AFTER := 0.07
## Further than this (m) in one frame is not a movement but tracking jumping, and strikes nothing.
const MOST_STEP := 0.25
## How far past a face's edge a crossing still lands on it (m): a fingertip on the rim is on it.
const EDGE := 0.01

## `item` was struck here, `velocity` on `zone`, by `hand` (a hand's key: a tracker's name).
signal struck(item: InstrumentItem, velocity: int, zone: StringName, hand: StringName)

## Where each point was last frame, {[hand, part]: Vector3}: only those seen with confidence.
var _was: Dictionary = {}
## When each hand last struck each instrument, {[item id, hand]: seconds on `_clock`}.
var _last: Dictionary = {}
var _clock := 0.0


func _physics_process(delta: float) -> void:
	# Nothing standing to strike: no points read, and none kept to cross from when one stands.
	if get_tree().get_first_node_in_group(GROUP) == null:
		_was.clear()
		return
	step(points(get_tree()), delta)


## Which side a hand's key (a tracker's name, `points`) is: -1 for a left hand or controller, 1 for
## a right, 0 for one that says neither. A hit on the fast path is panned by it.
static func side_of(hand: StringName) -> int:
	var name := String(hand)
	if name.contains("left"):
		return -1
	return 1 if name.contains("right") else 0


## How hard a grab by `hand` strikes: CLICK, or CLICK_SOFT with its fine modifier held (Shift).
static func click_velocity(hand: Interactor) -> int:
	return CLICK_SOFT if hand != null and hand.fine() else CLICK


## Every striking point of this player's own in `tree` this frame, seen with confidence, as
## {[hand, part]: Vector3} (global space). `hand` is the tracker's name, the same for a bare hand's
## joints and its poke, so the two are one hand.
static func points(tree: SceneTree) -> Dictionary:
	var out := {}
	if tree == null:
		return out
	var sure: Dictionary = {}
	for node in tree.get_nodes_in_group(HandGestures.GROUP):
		var g := node as HandGestures
		if g == null or not g.tracked or not g.confident or g.joints.size() < XRHandTracker.HAND_JOINT_MAX:
			continue
		sure[g.tracker_name] = true
		out[[g.tracker_name, &"thumb"]] = g.joints[HandPose.THUMB_TIP]
		for i in HandPose.TIPS.size():
			out[[g.tracker_name, i]] = g.joints[HandPose.TIPS[i]]
		out[[g.tracker_name, &"palm"]] = g.joints[HandPose.PALM]
	for node in tree.get_nodes_in_group(Interactor.GROUP):
		if node is PokeInteractor:
			var poke := node as PokeInteractor
			# A fingertip's own reading has no confidence of its own: its hand's joints say.
			if poke.tracked() and sure.has(poke.tracker_name):
				out[[poke.tracker_name, &"poke"]] = poke.tip()
		elif node is XRInteractor:
			var hand := node as XRInteractor
			var c := hand.controller
			# A bare hand's controller pose is the hand's aim, read off its joints above.
			if c == null or not c.is_inside_tree() or hand.bare_hand() or not controller_sure(c):
				continue
			out[[c.tracker, &"tip"]] = c.global_transform * XRRig.TIP_OFFSET
			out[[c.tracker, &"grip"]] = c.global_position
	return out


## Whether `controller`'s pose this frame is tracked, not guessed.
static func controller_sure(controller: XRController3D) -> bool:
	if controller == null or not controller.get_has_tracking_data():
		return false
	var pose := controller.get_pose()
	return pose != null and pose.tracking_confidence == XRPose.XR_TRACKING_CONFIDENCE_HIGH


## Where a point going from `from` to `to` over `delta` crosses `face` (one of
## InstrumentItem.faces) inward: [its speed into the face (m/s), the point it crossed at], or [] for
## no crossing (outward, beside the face, or not across it at all).
static func crossing(face: Dictionary, from: Vector3, to: Vector3, delta: float) -> Array:
	if delta <= 0.0:
		return []
	var frame := (face["frame"] as Transform3D).orthonormalized()
	var out := frame.basis.y
	var before := (from - frame.origin).dot(out)
	var after := (to - frame.origin).dot(out)
	if before <= 0.0 or after > 0.0:
		return []
	var at := from.lerp(to, before / (before - after))
	var local := frame.affine_inverse() * at
	if face.has("radius"):
		if Vector2(local.x, local.z).length() > float(face["radius"]) + EDGE:
			return []
	else:
		var half: Vector2 = face.get("half", Vector2.ZERO)
		if absf(local.x) > half.x + EDGE or absf(local.z) > half.y + EDGE:
			return []
	return [(before - after) / delta, at]


## One frame, `delta` on from the last, of the points `now` ({[hand, part]: Vector3}, `points`):
## every fixed instrument in the tree struck by one of them. The suite gives its own.
func step(now: Dictionary, delta: float) -> void:
	_clock += delta
	var items: Array[InstrumentItem] = []
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(GROUP):
			var item := node as InstrumentItem
			if item != null and item.fixed and item.is_visible_in_tree():
				items.append(item)
	# The fastest crossing by each hand of each instrument this frame: [speed, at, item, hand].
	var best: Dictionary = {}
	for key: Array in now:
		var was: Variant = _was.get(key)
		if was == null:
			continue
		var to: Vector3 = now[key]
		if (was as Vector3).distance_to(to) > MOST_STEP:
			continue
		for item in items:
			for face: Dictionary in item.faces():
				var hit := crossing(face, was, to, delta)
				if hit.is_empty() or float(hit[0]) < item.strike_least():
					continue
				var who := [item.get_instance_id(), key[0]]
				if not best.has(who) or float(hit[0]) > float(best[who][0]):
					best[who] = [hit[0], hit[1], item, key[0]]
	_was = now.duplicate()
	for who: Array in best:
		var hit: Array = best[who]
		var item: InstrumentItem = hit[2]
		if _clock - float(_last.get(who, -INF)) < AGAIN_AFTER:
			continue
		_last[who] = _clock
		var velocity := item.velocity_of(float(hit[0]))
		var zone := item.zone_at(hit[1])
		item.strike(velocity, zone, side_of(StringName(str(hit[3]))))
		struck.emit(item, velocity, zone, StringName(str(hit[3])))
