class_name ItemFlight
extends RefCounted

## What happens to an item thrown or flown: the throw and the fly, a hoop struck or a basket made, a target hit, and
## the aim point a throw is lobbed to. Moved out of `core/items/item_room.gd` without change of behaviour.

var room: ItemRoom


func _init(of: ItemRoom) -> void:
	room = of


## Something in flight hit a hoop's rim or board (Flight.RIM, Flight.BOARD) at `at` (world
## space): the nearest hoop sounds it. Whether there was one to.
func hoop_struck(on: int, speed: float, at: Vector3) -> bool:
	var hoop := _nearest_hoop(at)
	if hoop == null:
		return false
	hoop.struck(on == Flight.RIM, speed)
	return true


## `item` has just dropped through hoop `index`, touching nothing on the way if `clean`.
func basket(item: Item, index: int, clean: bool) -> void:
	if index < 0 or index >= room.hoops.size():
		return
	var hoop = room.hoops[index].get("node")
	if hoop is Hoop and is_instance_valid(hoop):
		(hoop as Hoop).sink(clean, item)


## Something in flight hit furniture registered in `targets` at `at` (world space), going at
## `speed`, thrown by `thrown_by` (its peer id, item.gd's `thrown_by`): the nearest one within
## its own radius takes it (`struck`, the same duck-typed call `hoop_struck` makes on a Hoop).
## Whether there was one close enough to.
func target_struck(speed: float, at: Vector3, thrown_by: int) -> bool:
	var best: Node = null
	var nearest := INF
	for t: Dictionary in room.targets:
		var node = t.get("node")
		if not is_instance_valid(node):
			continue
		var d := (node as Node3D).global_position.distance_to(at)
		if d < float(t.get("radius", 0.3)) and d < nearest:
			nearest = d
			best = node
	if best == null:
		return false
	best.struck(speed, thrown_by)
	return true


func _nearest_hoop(at: Vector3) -> Hoop:
	var best: Hoop = null
	var nearest := INF
	for h: Dictionary in room.hoops:
		var node = h.get("node")
		if not (node is Hoop) or not is_instance_valid(node):
			continue
		var d := (node as Hoop).global_position.distance_to(at)
		if d < nearest:
			nearest = d
			best = node
	return best


## What `aim` (world space) is aimed at, for a thrown thing that is aimed (Item.aim_scatter):
## where it meets a board in front of it, or a throw's length along it. World space.
func aim_point(aim: Transform3D) -> Vector3:
	var origin := aim.origin
	var toward := -aim.basis.z.normalized()
	for b: Dictionary in room.boards:
		var frame: Transform3D = room.global_transform * (b["at"] as Transform3D)
		var normal := frame.basis.z.normalized()
		var facing := toward.dot(normal)
		if facing > -0.05:
			continue
		var along := (frame.origin - origin).dot(normal) / facing
		if along <= 0.0 or along > ItemRoom.AIM_REACH:
			continue
		var hit := origin + toward * along
		var local := frame.affine_inverse() * hit
		if Vector2(local.x, local.y).length() < float(b.get("radius", b.get("half", 0.0))) * 1.6:
			return hit
	return origin + toward * ItemRoom.AIM_LENGTH


## Throw `item` from a hand here: from `origin` at `velocity` (world space), spinning at `spin`
## (rad/s, world axes). Flown at once, and said, for the host to fly too.
func throw(item: Item, origin: Vector3, velocity: Vector3, spin: Vector3) -> void:
	if item.fixed:
		return
	var into := room.global_transform.affine_inverse()
	var from := into * origin
	var v := into.basis * velocity
	var w := into.basis * spin
	fly(item, from, v, w, int(room.local_peer.call()) if room.local_peer.is_valid() else 1)
	room.asked.emit(&"throw_item", [item.id, from, v, w])


## Fly `item` from `origin` at `velocity`, spinning at `spin` -- all in this node's frame -- the
## same flight on every machine. `thrown_by` is whoever's throw this is (their peer id, 1 for
## the host): carried only for a registered target (the Tour case) to tell a host's own throw
## from a guest's; nothing else here reads it. Where it comes down, it stays if it can lie
## there; if not, it goes home when it has.
func fly(item: Item, origin: Vector3, velocity: Vector3, spin: Vector3, thrown_by: int = 1) -> void:
	if item.fixed:
		return
	var floor: Array = room.floor_rects.call() if room.floor_rects.is_valid() else []
	var start := room._onto(floor, origin)
	var how := item.flies()
	# Facing the way it was thrown, not the way it sat in the hand: the hand is not the same on
	# every machine, and the throw has to be.
	var facing := Quaternion(Basis(Vector3.UP, atan2(-velocity.x, -velocity.z)))
	var f := Flight.fly(start, velocity, spin, facing, floor,
			room.solids.call() if room.solids.is_valid() else [], how.get("bounce", 0.35), how.get("roll", 3.0),
			how.get("drag", 0.08), how.get("wing", {}), room.boards, how.get("point", 0.0),
			room.hoops if how.has("radius") else [], how.get("radius", 0.0))
	item.thrown_by = thrown_by
	# A personal copy never stays where a throw lands, same as a put-down (`lay`): there is no
	# floor spot that would mean anything once two people can each have their own, so it always
	# goes home after -- which `retire` turns into "gone" rather than "back on the shelf".
	var stays := (f.stuck or room.placing._can_lie(Vector2(f.rest.x, f.rest.z))) and not room.is_personal_copy(item.id)
	item.launch(f, [origin, velocity, spin], stays)
