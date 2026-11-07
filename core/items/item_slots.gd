class_name ItemSlots
extends RefCounted

## The slots of a holder (a shelf, a rack, a hook): which item is in which, what a slot refuses, laying one in,
## finding the slots near a point or along an aim. Moved out of `core/items/item_room.gd` without change of behaviour; the
## state stays on the room, which keeps a one-line delegate for each name reached from elsewhere.

var room: ItemRoom


func _init(of: ItemRoom) -> void:
	room = of


## Holder `holder`'s slots are `slots` now (this node's frame): what is in them is laid there again.
func set_holder(holder: StringName, slots: Array[Transform3D]) -> void:
	room.holders[holder] = slots
	for id in room.items:
		var item: Item = room.items[id]
		if item.slot_in == holder and item.slot_n >= 0 and item.slot_n < slots.size():
			_lay_in_slot(item, holder, item.slot_n)


## Whatever is in `holder`'s slot `n`, or null. A bin's is never taken: it swallows.
func in_slot(holder: StringName, n: int) -> Item:
	if room.is_bin(holder):
		return null
	for id in room.items:
		var item: Item = room.items[id]
		if item.slot_in == holder and item.slot_n == n and item.state == Item.State.LOOSE:
			return item
	return null


## Why `item` may not go into `holder`'s slot `n`, or "".
func slot_refusal(item: Item, holder: StringName, n: int) -> String:
	var why := kind_refusal(item, holder)
	if not why.is_empty():
		return why
	var slots: Array = room.holders.get(holder, [])
	if n < 0 or n >= slots.size():
		return "There is no slot %d there." % (n + 1)
	var there := in_slot(holder, n)
	if there != null and there != item:
		return "That slot has %s in it." % there.item_title().to_lower()
	return ""


## Why `item` may not go into `holder` at all, whichever slot, or "": it was not made while
## playing, or it is not of a kind the holder takes (HOLDS).
func kind_refusal(item: Item, holder: StringName) -> String:
	if not room.is_made(item.id):
		return "Only things made while playing go on the %s." % holder
	var kind := room.kind_of(item.id)
	if ItemRoom.HOLDS.has(holder) and not kind in ItemRoom.HOLDS[holder]:
		return "Only %s go on the %s." % [" and ".join(PackedStringArray((ItemRoom.HOLDS[holder] as Array).map(
				func(k): return ItemRoom.HOLDS_SAID.get(k, String(k))))), holder]
	return ""


## The room's word: `item` into `holder`'s slot `n`, if it may go there. The bin, on the host,
## retires it. Whether it went.
func slot(item: Item, holder: StringName, n: int) -> bool:
	if not slot_refusal(item, holder, n).is_empty():
		return false
	if room.is_bin(holder) and (not room.authority.is_valid() or room.authority.call()):
		room.unmake(item.id)
		return true
	_lay_in_slot(item, holder, n)
	return true


## A hand here put `item` into `holder`'s slot `n`: done at once, and said; or refused, and told.
func slot_item(item: Item, holder: StringName, n: int) -> bool:
	var why := slot_refusal(item, holder, n)
	if not why.is_empty():
		room.told.emit(why)
		return false
	var id := item.id
	slot(item, holder, n)
	room.asked.emit(&"slot_item", [id, holder, n])
	return true


## `item` into `holder`'s slot `n` (`slot_item`), or, with no slot free there (-1), told so; it stays
## in the hand.
func _slot_or_tell(item: Item, holder: StringName, n: int) -> void:
	if n < 0:
		room.told.emit("The %s is full: bin one first." % holder)
		return
	slot_item(item, holder, n)


func _lay_in_slot(item: Item, holder: StringName, n: int) -> void:
	var slots: Array = room.holders.get(holder, [])
	if n < 0 or n >= slots.size():
		return
	item.stick_at(slots[n])
	item.slot_in = holder
	item.slot_n = n


## The slot nearest `at` (global) within `reach`, [holder, n], taken or not; [] for none.
func slot_near(at: Vector3, reach := ItemRoom.SLOT_REACH) -> Array:
	var best: Array = []
	var nearest := reach
	var local := room.global_transform.affine_inverse() * at if room.is_inside_tree() else at
	for holder in room.holders:
		var slots: Array = room.holders[holder]
		for n in slots.size():
			var d := ((slots[n] as Transform3D) * Vector3(0, CassetteItem.SIZE.y * 0.5, 0)).distance_to(local)
			if d < nearest:
				nearest = d
				best = [holder, n]
	return best


## The free slot nearest the line `aim` (global) points along, within PUT_REACH, and within
## SLOT_REACH and a half of it: [holder, n], or [] for none.
func free_slot_along(item: Item, aim: Transform3D) -> Array:
	var inv := room.global_transform.affine_inverse() if room.is_inside_tree() else Transform3D.IDENTITY
	var local := inv * aim
	var origin := local.origin
	var toward := -local.basis.z.normalized()
	var best: Array = []
	var nearest := ItemRoom.SLOT_REACH * 1.5
	for holder in room.holders:
		var slots: Array = room.holders[holder]
		for n in slots.size():
			var at := (slots[n] as Transform3D) * Vector3(0, CassetteItem.SIZE.y * 0.5, 0)
			var along := (at - origin).dot(toward)
			if along <= 0.0 or along > ItemRoom.PUT_REACH:
				continue
			var off := (origin + toward * along).distance_to(at)
			var fits := slot_refusal(item, holder, n).is_empty()
			if off < nearest and fits:
				nearest = off
				best = [holder, n]
	return best
