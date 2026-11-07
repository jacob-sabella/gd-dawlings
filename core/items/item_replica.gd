class_name ItemReplica
extends RefCounted

## The room's items as the host's row (`state`) and a guest's or a loaded room's application of it (`apply`), and
## laying an item on the floor. Moved out of `core/items/item_room.gd` without change of behaviour.

var room: ItemRoom


func _init(of: ItemRoom) -> void:
	room = of


## Every item that is not at home, as the room has it: {id: [x, y, z, yaw]} for one lying on
## the floor (and "stuck" and the quaternion it is turned by after, for one stuck in a board),
## {id: []} for one in a hand, {id: [true]} for one on a head, {id: ["pocket", n]} for one in a
## pocket, {id: ["slot", holder, n]} for one in a slot (`holders`). One left out is on the
## shelf, or, made, at its home (`made_home`). What a made item carries is never here.
func state() -> Dictionary:
	var out := {}
	for id in room.items:
		var item: Item = room.items[id]
		match item.state:
			Item.State.LOOSE:
				# In a slot: which holder's, and which slot; where that is, the holder's.
				if item.slot_in != &"":
					out[id] = ["slot", String(item.slot_in), item.slot_n]
					continue
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
				if item.pocket >= 0:
					out[id] = ["pocket", item.pocket]
				else:
					out[id] = [true] if item.on_head else []
	return out


## Make the items what the host's room says (`state`). Not one a hand here has, nor one this
## guest has put somewhere and not heard back about (`pending`, by id); nor one the room says is
## in a hand, which the holds put there (Presence). One the room has on the floor lands there;
## one it leaves out goes home -- unless it is a personal copy nobody here has met yet (spawned
## by another peer's pick-up, or already out there when this one joined), which is made real
## here too, the same way a Tour spill reaches a guest that was not there when it fell; or one
## nobody holds any more, which is retired rather than sent home.
func apply(room_items: Dictionary, pending: Dictionary = {}) -> void:
	for id in room_items:
		if room.items.has(id) or not room.is_personal_copy(id):
			continue
		var kind := room.kind_of(id)
		var item := room.spawn(kind, id, room.items[kind].home if room.items.has(kind) else Transform3D.IDENTITY)
		if item != null:
			item.bound_to = room.peer_of(id)
			room.personal_taken.emit(item)
	var gone: Array[StringName] = []
	for id in room.items:
		var item: Item = room.items[id]
		# A fixed instrument never leaves its station, whatever a room says.
		if pending.has(id) or item.carried_by != null or item.fixed:
			continue
		var entry: Variant = room_items.get(id)
		if entry == null:
			if room.is_personal_copy(id):
				gone.append(id)
			elif item.state != Item.State.HOME:
				item.go_home()
			continue
		var spot := entry as Array
		# On somebody's head: that it is worn is the room's; whose it is, the holds'.
		if spot.size() == 1:
			item.set_pocket(-1)
			item.set_worn(bool(spot[0]))
			continue
		# In a slot: laid there, unless it already is.
		if spot.size() == 3 and spot[0] is String and spot[0] == "slot":
			var holder := StringName(str(spot[1]))
			if item.slot_in != holder or item.slot_n != int(spot[2]) or item.state != Item.State.LOOSE:
				room.slotting._lay_in_slot(item, holder, int(spot[2]))
			continue
		# In somebody's pocket: which, the room's; whose, the holds'.
		if spot.size() == 2 and spot[0] is String and spot[0] == "pocket":
			item.set_worn(false)
			item.set_pocket(int(spot[1]))
			continue
		if spot.size() < 4:
			if spot.is_empty() and item.state == Item.State.HELD:
				item.set_worn(false)
				item.set_pocket(-1)
			continue
		var at := Vector3(float(spot[0]), float(spot[1]), float(spot[2]))
		# A throw this copy has not flown: flown here from the same launch, to where the room
		# says it lands.
		if spot.size() == 8 and int(spot[4]) > item.throws:
			item.throws = int(spot[4]) - 1
			room.fly(item, spot[5], spot[6], spot[7])
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
	for id in gone:
		room.despawn(id)


## Lay `item` on the floor at `at` (this node's frame), turned to `yaw`, if it can lie there;
## home if it cannot. True if it lies there. The host's answer to a put-down, and a hand's own.
## A personal copy never lies anywhere: putting it down retires it (`retire`), same as sending it
## home, since there is no floor spot that would mean anything once two people can each have one.
func lay(item: Item, at: Vector2, yaw: float) -> bool:
	# A fixed instrument lies nowhere but its station.
	if item.fixed:
		item.snap_home()
		return false
	if room.is_personal_copy(item.id):
		room.retire(item)
		return false
	if not room.placing._can_lie(at):
		room.retire(item)
		return false
	var y: float = room.ground_at.call(at) if room.ground_at.is_valid() else 0.0
	item.lay_down(Vector3(at.x, y, at.y), yaw)
	return true
