class_name ItemPlacing
extends RefCounted

## Where an item may be put: wearing and pocketing, sending one home, putting one down along an aim, the ground
## under a point and what blocks it. Moved out of `core/items/item_room.gd` without change of behaviour.

var room: ItemRoom


func _init(of: ItemRoom) -> void:
	room = of


## Put `item` on a head here or take it off (`on`), and say so.
func wear(item: Item, on: bool) -> void:
	item.set_worn(on)
	room.asked.emit(&"wear_item", [item.id, on])


## Put `item` in pocket `slot` here, or out of it into the hand (-1), and say so.
func pocket(item: Item, slot: int) -> void:
	if item.fixed:
		return
	item.set_pocket(slot)
	room.asked.emit(&"pocket_item", [item.id, slot])


## Send `item` home from a hand here, and say so. "Home" for a personal copy is nowhere at all
## (`retire`): it is gone, not sent to a shelf spot two people's copies would have to share.
func send_home(item: Item) -> void:
	var id := item.id
	room.retire(item)
	room.asked.emit(&"home_item", [id])


## Put `item` down along `aim` (world space): where the aim meets the floor within reach, or at
## the aimer's feet when it does not. Home if neither is somewhere it can lie. A made item let go
## within SLOT_REACH of a slot, or aimed at a free one, goes into it instead (`slot_item`).
func put_down(item: Item, aim: Transform3D) -> void:
	if item.fixed:
		return
	# A made item let go by a slot goes into it -- or, the slot taken, stays in the hand and says
	# so -- and one aimed at a free slot within reach goes there.
	if room.is_made(item.id) and not room.holders.is_empty():
		var middle := item.middle()
		var near := room.slot_near(middle)
		if not near.is_empty():
			room.slotting._slot_or_tell(item, near[0], near[1])
			return
		var along := room.slotting.free_slot_along(item, aim)
		if not along.is_empty():
			room.slotting._slot_or_tell(item, along[0], along[1])
			return
	var local := room.global_transform.affine_inverse() * aim
	var origin := local.origin
	var toward := -local.basis.z.normalized()
	var spot := Vector2.INF
	if toward.y < -0.02:
		var along := -origin.y / toward.y
		if along > 0.0 and along < ItemRoom.PUT_REACH:
			var hit := origin + toward * along
			spot = Vector2(hit.x, hit.z)
			# Aimed at the floor through the gear: it was aimed at the gear.
			if _through_gear(origin, hit):
				item.go_home()
				room.asked.emit(&"home_item", [item.id])
				return
	if spot == Vector2.INF:
		var ahead := Vector2(toward.x, toward.z)
		ahead = ahead.normalized() if ahead.length() > 0.01 else Vector2(0, -1)
		spot = Vector2(origin.x, origin.z) + ahead * ItemRoom.AT_FEET
	# Facing the way you were looking, as if you had set it down in front of you.
	var yaw := atan2(-toward.x, -toward.z)
	if room.lay(item, spot, yaw):
		room.asked.emit(&"put_item", [item.id, spot.x, spot.y, yaw])
	else:
		room.asked.emit(&"home_item", [item.id])


## Whether the line from `from` to `to` passes through any gear below its top: a hand reaching
## past a console puts the thing on the console, not on the floor behind it.
func _through_gear(from: Vector3, to: Vector3) -> bool:
	if not room.gear.is_valid():
		return false
	var prints: Array = room.gear.call()
	var n := maxi(1, int(from.distance_to(to) / 0.05))
	for i in n + 1:
		var p := from.lerp(to, float(i) / n)
		if p.y >= Walker.SOLID_HEIGHT:
			continue
		for f: Dictionary in prints:
			if Walker._gap(f, Vector2(p.x, p.z)) <= 0.0:
				return true
	return false


## How high the floor is at `at` (this node's frame).
func ground(at: Vector2) -> float:
	return room.ground_at.call(at) if room.ground_at.is_valid() else 0.0


## Whether something flying at `p` (this node's frame) has hit something: a wall, which is the
## edge of the floor, or anything standing on the floor -- the venue's solids, the gear -- below
## its top. For the radio plane (RcPlaneItem), which flies where it is steered.
func blocked(p: Vector3) -> bool:
	var at := Vector2(p.x, p.z)
	var floor: Array = room.floor_rects.call() if room.floor_rects.is_valid() else []
	if not floor.is_empty() and not Flight._on_floor(floor, at):
		return true
	var standing: Array = room.solids.call() if room.solids.is_valid() else []
	for f: Dictionary in standing:
		if p.y < float(f.get("top", Walker.SOLID_HEIGHT)) and Walker._gap(f, at) <= 0.0:
			return true
	if room.gear.is_valid() and p.y < Walker.SOLID_HEIGHT:
		for f: Dictionary in room.gear.call():
			if Walker._gap(f, at) <= 0.0:
				return true
	return false


func _can_lie(at: Vector2) -> bool:
	if room.fits.is_valid():
		return room.fits.call(at)
	return true
