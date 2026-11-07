class_name PieceCatalogue
extends RefCounted

## Which single items a player may take out of a room and put into one (docs/layouts.md 4.2 and 7). Only
## single items are here: a piece the shell or a zone supplies (the wheel on the bricks table, the drums on
## their riser, the venue's own instrument), the prop shelf that carries the toys and the Tour case that
## starts a run are part of the room and stay; the modular room is room-scale and not an edit of this kind.
##
## Two sorts of entry. A piece the layout already stands (the cassette rack, the sampler, the hoop) may be
## `REMOVABLE` and put back by `add`, one of each. A piece the layout does not stand may be added as many
## times as its `limit`, each a copy built by the same builder the venue uses (`ADDABLE`): the basketball
## hoop, `Hoop.new`, on a trolley of the hoop's `PieceDef`. Both are built by `RoomSync`.

## Kinds that can be added as copies, and the most of them in one room (the room's own included).
const ADDABLE := {&"hoop": {"title": "BASKETBALL HOOP", "limit": 4}}
## Layout pieces a room may do without. Each can be put back with `add`.
const REMOVABLE: Array[StringName] = [&"cassette_rack", &"sampler", &"hoop"]


## Every kind the ADD list offers, in the order it shows them.
static func kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in REMOVABLE:
		out.append(k)
	return out


## Whether `kind` may be added as another copy.
static func copies(kind: StringName) -> bool:
	return ADDABLE.has(kind)


## The most of `kind` a room holds: its copies' limit, or one.
static func limit(kind: StringName) -> int:
	return int(ADDABLE[kind]["limit"]) if ADDABLE.has(kind) else 1


## What the player sees for `kind`.
static func title(kind: StringName) -> String:
	return String(ADDABLE[kind]["title"]) if ADDABLE.has(kind) else String(kind).replace("_", " ").to_upper()


## Whether `id` (a layout piece's id) may be removed.
static func removable(id: StringName) -> bool:
	return id in REMOVABLE


## Whether `id` names a copy a room added, not a piece of the layout: `<kind>_<n>` of a kind in ADDABLE.
static func is_copy(id: StringName) -> bool:
	return kind_of_copy(id) != &""


## The kind of copy `id` is (`hoop_2` -> `hoop`), or &"" for an id that is not a copy's.
static func kind_of_copy(id: StringName) -> StringName:
	var text := String(id)
	var cut := text.rfind("_")
	if cut < 0 or not text.substr(cut + 1).is_valid_int():
		return &""
	var kind := StringName(text.substr(0, cut))
	return kind if ADDABLE.has(kind) else &""


## The next unused id for a copy of `kind` among `taken` (ids already in the room): `hoop_2`, `hoop_3`, ...
static func next_id(kind: StringName, taken: Array) -> StringName:
	var n := 2
	while "%s_%d" % [kind, n] in taken:
		n += 1
	return StringName("%s_%d" % [kind, n])
