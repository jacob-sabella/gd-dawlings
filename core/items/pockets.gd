class_name Pockets
extends RefCounted

## A person's pockets (docs/items_loop.md): a few places on them to carry things that are not
## their hand -- the left hip, the right hip, across the back. A person's, not a hand's: both of a
## headset's hands reach the same pockets, so every hand here shares one of these (`Interactor.
## pockets`).
##
## What is in a pocket is still this person's, held and claimed with the host like what is in a
## hand (Presence.claim_carries): the item is HELD, `carried_by` the hand that put it there, and
## its `pocket` says which. Others see it on their ghost (Avatar.pocket_pose); here it is seen only
## in a mirror, as a hat is, since nobody here draws their own body.

const COUNT := 3
## What each is called, as a hint says it.
const NAMES: Array[String] = ["left hip", "right hip", "back"]

var _slots: Array = [null, null, null]

static var _mine: Pockets = null


## This machine's person's: one person to a machine, whatever hands they have.
static func mine() -> Pockets:
	if _mine == null:
		_mine = Pockets.new()
	return _mine


## What is in pocket `slot`, or null. Only while it still is: an item sent home, taken by
## somebody else or freed is not in anybody's pocket any more, whatever was put here.
func at(slot: int) -> Item:
	if slot < 0 or slot >= COUNT:
		return null
	var item = _slots[slot]
	if item == null or not is_instance_valid(item) or (item as Item).state != Item.State.HELD \
			or (item as Item).pocket != slot or (item as Item).carried_by == null:
		_slots[slot] = null
		return null
	return item


func put(slot: int, item: Item) -> void:
	if slot >= 0 and slot < COUNT:
		_slots[slot] = item


## Every item in a pocket, by pocket.
func items() -> Array[Item]:
	var out: Array[Item] = []
	for slot in COUNT:
		var item := at(slot)
		if item != null:
			out.append(item)
	return out


## The first empty pocket, or -1.
func free_slot() -> int:
	for slot in COUNT:
		if at(slot) == null:
			return slot
	return -1


## The next pocket after `slot` with something in it, round and round; -1 if they are all empty.
func next_full(after: int, way := 1) -> int:
	for n in range(1, COUNT + 1):
		var slot := posmod(after + n * way, COUNT)
		if at(slot) != null:
			return slot
	return -1


## What is in them, for a hint: "1 duck · 2 — · 3 keytar".
func summary() -> String:
	var parts: PackedStringArray = []
	for slot in COUNT:
		var item := at(slot)
		parts.append("%d %s" % [slot + 1, item.item_title().to_lower() if item != null else "—"])
	return " · ".join(parts)
