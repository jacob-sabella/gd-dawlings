class_name RackLayout
extends RefCounted

## Where modules sit in the case: a grid of COLS columns and ROWS rows (skiffs stacked), each module
## one or more columns wide by what it has to hold. Pure arithmetic, shared by the wall that draws it
## and the room that answers an ask to put a module somewhere.

const COLS := 40
const ROWS := 4
## A column holds this many knobs, or this many jacks, before the module needs another.
const KNOBS_PER_COLUMN := 8
const JACKS_PER_COLUMN := 6
## A SCOPE has a screen to hold.
const SCOPE_WIDE := 4


## How many columns a type's panel takes.
static func width_of(type: String) -> int:
	if type == "scope":
		return SCOPE_WIDE
	var s := RackCatalogue.spec(type)
	if s.is_empty():
		return 1
	var knobs: int = (s["knobs"] as Array).size()
	var jacks: int = (s["ins"] as Array).size() + (s["outs"] as Array).size()
	return maxi(1, maxi(ceili(float(knobs) / KNOBS_PER_COLUMN), ceili(float(jacks) / JACKS_PER_COLUMN)))


static func _spot(p: Dictionary, id: String) -> Vector2i:
	var at: Array = p["modules"][id]["at"]
	return Vector2i(int(at[0]), int(at[1]))


## Whether a module of `type` fits with its left edge at `at`, ignoring module `ignore`.
static func fits(p: Dictionary, type: String, at: Vector2i, ignore := "") -> bool:
	var w := width_of(type)
	if at.x < 0 or at.y < 0 or at.y >= ROWS or at.x + w > COLS:
		return false
	for id in p["modules"]:
		if id == ignore:
			continue
		var o := _spot(p, id)
		var ow := width_of(p["modules"][id]["type"])
		if o.y == at.y and at.x < o.x + ow and o.x < at.x + w:
			return false
	return true


## The first place a `type` fits, scanning along each row; (-1, -1) when the case is full.
static func free_slot(p: Dictionary, type: String) -> Vector2i:
	for row in ROWS:
		for col in COLS:
			if fits(p, type, Vector2i(col, row)):
				return Vector2i(col, row)
	return Vector2i(-1, -1)


## A patch where nothing overlaps or hangs off the case: the modules that do not fit are put in the
## next free place, and any that nowhere fits are dropped (their cables with them).
static func tidy(p: Dictionary) -> void:
	var placed := {"modules": {}, "cables": []}
	for id in (p["modules"] as Dictionary).keys():
		var type: String = p["modules"][id]["type"]
		var at := _spot(p, id)
		if not fits(placed, type, at):
			at = free_slot(placed, type)
		if at.x < 0:
			continue
		placed["modules"][id] = {"type": type, "at": [at.x, at.y]}
		p["modules"][id]["at"] = [at.x, at.y]
	for id in (p["modules"] as Dictionary).keys():
		if not placed["modules"].has(id):
			RackPatch.remove(p, id)
