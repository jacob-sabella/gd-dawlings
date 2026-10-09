class_name ItemRoom
extends Node3D

## Every item in the room, and the rules for where one may be.
##
## Lives in the studio's set, the frame the floor plan and the walker's floor are measured in,
## so an item's place is a place on that floor. The venue says where the shelf is
## (`Venue.item_spots`); this keeps each item's home on it, sends everything at home to the new
## shelf when the venue changes, and sends anything left lying where the new room has no floor
## home too. Items in a hand are left in it.
##
## In a session the room is the host's (`Session.room["items"]`, see `state` and `apply`): a hand
## here that puts something down does it at once and says so (`asked`), and the host's word
## then stands, or puts it back.
##
## A put-down is judged here, not by the hand, because only the room knows its floor. An item
## lies only where a person could reach to pick it up again (`Walker.reachable`): on the floor or
## on something you step up onto, never on the gear or in a wall. Anywhere else, it goes home.

## The items there are, in the order they take the shelf's spots.
const KINDS: Array[StringName] = [&"duck", &"ball", &"plane", &"mic", &"headphones", &"tablet", &"shaker",
		&"tambourine", &"keytar", &"chips", &"cards", &"dart1", &"dart2", &"dart3"]
## How far in front of you a put-down can land; past this, it is put at your feet.
const PUT_REACH := 2.6
## Where it lands when the aim finds no floor in reach: this far in front of where you stand.
const AT_FEET := 0.45
## An aimed throw (`aim_point`) at a board no further than this; at nothing, this far along the aim.
const AIM_REACH := 8.0
const AIM_LENGTH := 2.5

## A hand here put `item` somewhere: `put_item` [id, x, z, yaw] or `home_item` [id], already
## done here. The studio sends it to the host as an ask.
signal asked(verb: StringName, args: Array)
## A hand here used `item`: for the session to tell everyone.
signal used(item: Item, down: bool)
## Something about where an item is changed: for a host to tell the room.
signal moved(item: Item)
## An instrument played by a hand here (InstrumentItem.played): for the session and the take.
signal played(item: InstrumentItem, velocity: int, struck: bool)

## {id: Item}.
var items: Dictionary = {}
## Says whether something lying at a floor spot (Vector2, this node's frame) could be picked up
## again and how high the floor is there: the walker's `reachable` and `ground_at`. Unset, the whole floor plan is floor.
var fits: Callable = Callable()
var ground_at: Callable = Callable()
## What a throw flies in: the walkable floor (Array of Rect2, walls at its edges) and the venue's
## solids (Walker.fixed), in this node's frame. The walker's, read when the throw is made.
var floor_rects: Callable = Callable()
var solids: Callable = Callable()
## The gear's footprints (the walker's `footprints`), for a put-down aimed through the gear at
## the floor behind it.
var gear: Callable = Callable()
## What a dart sticks in (Flight.fly's `boards`), in this node's frame: the venue's dartboard.
var boards: Array = []
var _spots: Array[Transform3D] = []
## Homes of their own, off the shelf's top, by kind: the mic's stand, the headphones' hook, the
## tablet's lower tier.
var _homes: Dictionary = {}


static func make(kind: StringName) -> Item:
	match kind:
		&"duck":
			return DuckItem.new()
		&"ball":
			return BallItem.new()
		&"plane":
			return PlaneItem.new()
		&"mic":
			return MicItem.new()
		&"headphones":
			return HeadphonesItem.new()
		&"tablet":
			return TabletItem.new()
		&"shaker":
			return ShakerItem.new()
		&"tambourine":
			return TambourineItem.new()
		&"keytar":
			return KeytarItem.new()
		&"chips":
			return ChipsItem.new()
		&"cards":
			return CardsItem.new()
		&"dart1":
			return DartItem.new(0)
		&"dart2":
			return DartItem.new(1)
		&"dart3":
			return DartItem.new(2)
	return null


## What an item of `kind` looks like, and nothing else: no grip, no springs. For a ghost to
## carry, so a mirror or another person sees what is in your hand.
static func look_of(kind: StringName) -> Node3D:
	var item := make(kind)
	if item == null:
		return null
	var look := item.body
	item.remove_child(look)
	item.free()
	look.scale = Vector3.ONE
	return look


## The room an item is in, if any.
static func of(item: Item) -> ItemRoom:
	return item.get_parent() as ItemRoom if item != null and is_instance_valid(item) else null


func _ready() -> void:
	for kind in KINDS:
		if items.has(kind):
			continue
		var item := make(kind)
		item.name = "Item_" + String(kind)
		items[kind] = item
		add_child(item)
		item.used.connect(func(down: bool) -> void: used.emit(item, down))
		item.state_changed.connect(func(_s: Item.State) -> void: moved.emit(item))
		item.landed.connect(func() -> void: moved.emit(item))
		item.worn_changed.connect(func() -> void: moved.emit(item))
		if item is InstrumentItem:
			(item as InstrumentItem).played.connect(func(velocity: int, struck: bool) -> void:
				played.emit(item, velocity, struck))
	_rehome()


## The shelf's spots, from the venue: one per item, in KINDS order, in this node's frame. Items
## at home go to their new spot; loose ones stay where they lie if they still can.
func set_spots(spots: Array[Transform3D], homes: Dictionary = {}) -> void:
	_spots = spots
	_homes = homes
	_rehome()


func _rehome() -> void:
	# The shelf's spots go to the kinds with no home of their own, in KINDS order.
	var shelf := 0
	for i in KINDS.size():
		var item: Item = items.get(KINDS[i])
		if item != null:
			item.own_home = _homes.has(KINDS[i])
		if _homes.has(KINDS[i]):
			if item != null:
				item.home = _homes[KINDS[i]]
		else:
			if item != null:
				item.home = _spots[shelf] if shelf < _spots.size() else Transform3D.IDENTITY
			shelf += 1
		if item == null:
			continue
		match item.state:
			# A shelf that has moved under it: straight there, not floated across the map.
			Item.State.HOME:
				item.snap_home()
			Item.State.LOOSE:
				var at := Vector2(item.resting.origin.x, item.resting.origin.z)
				if not _can_lie(at):
					item.snap_home()


## Every item that is not at home, as the room has it: {id: [x, y, z, yaw]} for one lying on
## the floor (and "stuck" and the quaternion it is turned by after, for one stuck in a board),
## {id: []} for one in a hand, {id: [true]} for one on a head. One left out is on the
## shelf.
func state() -> Dictionary:
	var out := {}
	for id in items:
		var item: Item = items[id]
		match item.state:
			Item.State.LOOSE:
				var at := item.resting.origin
				var entry := [at.x, at.y, at.z, item.resting.basis.get_euler().y]
				# In the air: how it was thrown too, for a copy that has not flown it to fly.
				if item.is_flying() and item.launched_with.size() == 3:
					entry.append(item.throws)
					entry.append_array(item.launched_with)
				elif item.is_stuck():
					# Not lying flat -- stuck in a board: how it is turned, whole.
					var q := item.resting.basis.get_rotation_quaternion()
					entry.append_array(["stuck", q.x, q.y, q.z, q.w])
				out[id] = entry
			Item.State.HELD:
				out[id] = [true] if item.on_head else []
	return out


## Make the items what the host's room says (`state`). Not one a hand here has, nor one this
## guest has put somewhere and not heard back about (`pending`, by id); nor one the room says is
## in a hand, which the holds put there (Presence). One the room has on the floor lands there;
## one it leaves out goes home.
func apply(room_items: Dictionary, pending: Dictionary = {}) -> void:
	for id in items:
		var item: Item = items[id]
		if pending.has(id) or item.carried_by != null:
			continue
		var entry: Variant = room_items.get(id)
		if entry == null:
			if item.state != Item.State.HOME:
				item.go_home()
			continue
		var spot := entry as Array
		# On somebody's head: that it is worn is the room's; whose it is, the holds'.
		if spot.size() == 1:
			item.set_worn(bool(spot[0]))
			continue
		if spot.size() < 4:
			if spot.is_empty() and item.state == Item.State.HELD:
				item.set_worn(false)
			continue
		var at := Vector3(float(spot[0]), float(spot[1]), float(spot[2]))
		# A throw this copy has not flown: flown here from the same launch, to where the room
		# says it lands.
		if spot.size() == 8 and int(spot[4]) > item.throws:
			item.throws = int(spot[4]) - 1
			fly(item, spot[5], spot[6], spot[7])
			if not item.resting.origin.is_equal_approx(at):
				item.resting = Transform3D(Basis(Vector3.UP, float(spot[3])), at)
			continue
		if item.state == Item.State.LOOSE and item.resting.origin.is_equal_approx(at):
			continue
		if spot.size() == 9 and spot[4] is String:
			item.stick_at(Transform3D(Basis(Quaternion(float(spot[5]), float(spot[6]), float(spot[7]),
					float(spot[8])).normalized()), at))
			continue
		item.lay_down(at, float(spot[3]))


## Lay `item` on the floor at `at` (this node's frame), turned to `yaw`, if it can lie there;
## home if it cannot. True if it lies there. The host's answer to a put-down, and a hand's own.
func lay(item: Item, at: Vector2, yaw: float) -> bool:
	if not _can_lie(at):
		item.go_home()
		return false
	var y: float = ground_at.call(at) if ground_at.is_valid() else 0.0
	item.lay_down(Vector3(at.x, y, at.y), yaw)
	return true


## Throw `item` from a hand here: from `origin` at `velocity` (world space), spinning at `spin`
## (rad/s, world axes). Flown at once, and said, for the host to fly too.
func throw(item: Item, origin: Vector3, velocity: Vector3, spin: Vector3) -> void:
	var into := global_transform.affine_inverse()
	var from := into * origin
	var v := into.basis * velocity
	var w := into.basis * spin
	fly(item, from, v, w)
	asked.emit(&"throw_item", [item.id, from, v, w])


## Fly `item` from `origin` at `velocity`, spinning at `spin` -- all in this node's frame -- the
## same flight on every machine. Where it comes down, it stays if it can lie there; if not, it
## goes home when it has.
func fly(item: Item, origin: Vector3, velocity: Vector3, spin: Vector3) -> void:
	var floor: Array = floor_rects.call() if floor_rects.is_valid() else []
	var start := _onto(floor, origin)
	var how := item.flies()
	# Facing the way it was thrown, not the way it sat in the hand: the hand is not the same on
	# every machine, and the throw has to be.
	var facing := Quaternion(Basis(Vector3.UP, atan2(-velocity.x, -velocity.z)))
	var f := Flight.fly(start, velocity, spin, facing, floor,
			solids.call() if solids.is_valid() else [], how.get("bounce", 0.35), how.get("roll", 3.0),
			how.get("drag", 0.08), how.get("wing", {}), boards, how.get("point", 0.0))
	item.launch(f, [origin, velocity, spin], f.stuck or _can_lie(Vector2(f.rest.x, f.rest.z)))


## What `aim` (world space) is aimed at, for a thrown thing that is aimed (Item.aim_scatter):
## where it meets a board in front of it, or a throw's length along it. World space.
func aim_point(aim: Transform3D) -> Vector3:
	var origin := aim.origin
	var toward := -aim.basis.z.normalized()
	for b: Dictionary in boards:
		var frame: Transform3D = global_transform * (b["at"] as Transform3D)
		var normal := frame.basis.z.normalized()
		var facing := toward.dot(normal)
		if facing > -0.05:
			continue
		var along := (frame.origin - origin).dot(normal) / facing
		if along <= 0.0 or along > AIM_REACH:
			continue
		var hit := origin + toward * along
		var local := frame.affine_inverse() * hit
		if Vector2(local.x, local.y).length() < float(b.get("radius", b.get("half", 0.0))) * 1.6:
			return hit
	return origin + toward * AIM_LENGTH


## The velocity that takes a thing from `from` to `to` at about `speed`, falling as it goes:
## the time it takes is the distance over the speed, and it is thrown up by as much as it falls.
static func lob(from: Vector3, to: Vector3, speed: float) -> Vector3:
	var gap := to - from
	var t := maxf(0.05, gap.length() / maxf(0.5, speed))
	# And half a step of gravity more: a flight falls by its speed at the end of each step.
	return gap / t + Vector3.UP * 0.5 * Flight.GRAVITY * (t + Flight.STEP)


## `at`, or the nearest point to it on the floor: a hand held out over a wall throws from this
## side of it.
static func _onto(floor: Array, at: Vector3) -> Vector3:
	if floor.is_empty():
		return at
	var flat := Vector2(at.x, at.z)
	var best := flat
	var best_d := INF
	for r: Rect2 in floor:
		var inner := r.grow(-0.02)
		var c := Vector2(clampf(flat.x, inner.position.x, inner.end.x), clampf(flat.y, inner.position.y, inner.end.y))
		var d := c.distance_to(flat)
		if d < best_d:
			best_d = d
			best = c
	return Vector3(best.x, at.y, best.y)


## Put `item` on a head here or take it off (`on`), and say so.
func wear(item: Item, on: bool) -> void:
	item.set_worn(on)
	asked.emit(&"wear_item", [item.id, on])


## Send `item` home from a hand here, and say so.
func send_home(item: Item) -> void:
	item.go_home()
	asked.emit(&"home_item", [item.id])


## Put `item` down along `aim` (world space): where the aim meets the floor within reach, or at
## the aimer's feet when it does not. Home if neither is somewhere it can lie.
func put_down(item: Item, aim: Transform3D) -> void:
	var local := global_transform.affine_inverse() * aim
	var origin := local.origin
	var toward := -local.basis.z.normalized()
	var spot := Vector2.INF
	if toward.y < -0.02:
		var along := -origin.y / toward.y
		if along > 0.0 and along < PUT_REACH:
			var hit := origin + toward * along
			spot = Vector2(hit.x, hit.z)
			# Aimed at the floor through the gear: it was aimed at the gear.
			if _through_gear(origin, hit):
				item.go_home()
				asked.emit(&"home_item", [item.id])
				return
	if spot == Vector2.INF:
		var ahead := Vector2(toward.x, toward.z)
		ahead = ahead.normalized() if ahead.length() > 0.01 else Vector2(0, -1)
		spot = Vector2(origin.x, origin.z) + ahead * AT_FEET
	# Facing the way you were looking, as if you had set it down in front of you.
	var yaw := atan2(-toward.x, -toward.z)
	if lay(item, spot, yaw):
		asked.emit(&"put_item", [item.id, spot.x, spot.y, yaw])
	else:
		asked.emit(&"home_item", [item.id])


## Whether the line from `from` to `to` passes through any gear below its top: a hand reaching
## past a console puts the thing on the console, not on the floor behind it.
func _through_gear(from: Vector3, to: Vector3) -> bool:
	if not gear.is_valid():
		return false
	var prints: Array = gear.call()
	var n := maxi(1, int(from.distance_to(to) / 0.05))
	for i in n + 1:
		var p := from.lerp(to, float(i) / n)
		if p.y >= Walker.SOLID_HEIGHT:
			continue
		for f: Dictionary in prints:
			if Walker._gap(f, Vector2(p.x, p.z)) <= 0.0:
				return true
	return false


func _can_lie(at: Vector2) -> bool:
	if fits.is_valid():
		return fits.call(at)
	return true

