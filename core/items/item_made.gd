class_name ItemMade
extends RefCounted

## The items a player made: minting one from its row, building the real item, applying the host's list of them,
## unmaking and forgetting. Moved out of `core/items/item_room.gd` without change of behaviour.

var room: ItemRoom


func _init(of: ItemRoom) -> void:
	room = of


## On the host: a made item of `kind` carrying `data`, made by `maker` (a peer id), under the next
## free id (`cassette1`, ...), its row kept in `made` and said (`minted`), and spawned at its home.
## Null, and `mint_refusal` saying why, past MADE_MOST, MADE_TOTAL or MADE_BYTES, or for no data.
func mint(kind: StringName, data: Dictionary, maker := 1) -> Item:
	room.mint_refusal = ""
	if not (kind in ItemRoom.MADE_KINDS) or data.is_empty():
		room.mint_refusal = "There is nothing there to make a %s of." % kind
		return null
	var bytes := var_to_bytes(data)
	room.mint_refusal = room.made_refusal(room.made, bytes.size())
	if not room.mint_refusal.is_empty():
		return null
	var n := int(room._made_after.get(kind, 0)) + 1
	while room.items.has(StringName("%s%d" % [kind, n])) or room.made.has(StringName("%s%d" % [kind, n])):
		n += 1
	room._made_after[kind] = n
	var id := StringName("%s%d" % [kind, n])
	room.made[id] = [kind, maker, bytes]
	var item := _make_real(id)
	room.minted.emit(item)
	return item


## Made item `id` real here, from its row in `made`: spawned at its home and given what it carries.
## Idempotent, as `spawn` is. Null without a row, or with one that does not read.
func _make_real(id: StringName) -> Item:
	if room.items.has(id):
		return room.items[id]
	var row: Variant = room.made.get(id)
	if not (row is Array) or (row as Array).size() != 3 or not ((row as Array)[2] is PackedByteArray):
		return null
	var data: Variant = bytes_to_var((row as Array)[2])
	if not (data is Dictionary):
		return null
	var kind := room.kind_of(id)
	var n := int(String(id).trim_prefix(String(kind)))
	room._made_after[kind] = maxi(int(room._made_after.get(kind, 0)), n)
	var item := room.spawn(kind, id, room.made_home.call(kind, n) if room.made_home.is_valid() else Transform3D.IDENTITY)
	if item != null and item.has_method("read"):
		item.read(data)
	return item


## The made items the host's room names (`made_ids`), here: each one this machine has the row of
## and has not met made real, and each one here the room no longer names gone. Its row, if any,
## stays until the host says it is gone (`forget_made`): a row can arrive before the room names it.
func apply_made(ids: Array) -> void:
	for id in ids:
		_make_real(StringName(id))
	for id in room.made_ids():
		if not ids.has(id) and not ids.has(String(id)):
			room.despawn(id)


## Made item `id` gone for good, on the host: out of the room and out of `made`, and said.
func unmake(id: StringName) -> void:
	if not room.is_made(id):
		return
	room.despawn(id)
	room.made.erase(id)
	room.unmade.emit(id)


## The host said made item `id` is gone: here too, row and all.
func forget_made(id: StringName) -> void:
	room.despawn(id)
	room.made.erase(id)
