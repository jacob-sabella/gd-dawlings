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
	if type == "builtin.scope":
		return SCOPE_WIDE
	var s := RackCatalogue.spec(type)
	if s.is_empty():
		return 1
	var knobs: int = (s["knobs"] as Array).size()
	var jacks: int = (s["ins"] as Array).size() + (s["outs"] as Array).size()
	return maxi(1, maxi(ceili(float(knobs) / KNOBS_PER_COLUMN), ceili(float(jacks) / JACKS_PER_COLUMN)))


## How many columns module `id` of `p` takes: its stored `w` where no mod here provides its type, else
## `width_of`.
static func width_in(p: Dictionary, id: String) -> int:
	var m: Dictionary = p["modules"][id]
	return int(m["w"]) if m.get("missing", false) else width_of(m["type"])


static func _spot(p: Dictionary, id: String) -> Vector2i:
	var at: Array = p["modules"][id]["at"]
	return Vector2i(int(at[0]), int(at[1]))


## Whether a module of `type` fits with its left edge at `at`, ignoring module `ignore`. `wide` is its
## width where the type is no one's (a module kept for a missing mod); the ignored module's own width
## counts when it is one of `p`'s.
static func fits(p: Dictionary, type: String, at: Vector2i, ignore := "", wide := -1) -> bool:
	var w := wide if wide > 0 else (width_in(p, ignore) if (p["modules"] as Dictionary).has(ignore) else width_of(type))
	if at.x < 0 or at.y < 0 or at.y >= ROWS or at.x + w > COLS:
		return false
	for id in p["modules"]:
		if id == ignore:
			continue
		var o := _spot(p, id)
		var ow := width_in(p, id)
		if o.y == at.y and at.x < o.x + ow and o.x < at.x + w:
			return false
	return true


## The first place a `type` fits, scanning along each row; (-1, -1) when the case is full.
static func free_slot(p: Dictionary, type: String, wide := -1) -> Vector2i:
	for row in ROWS:
		for col in COLS:
			if fits(p, type, Vector2i(col, row), "", wide):
				return Vector2i(col, row)
	return Vector2i(-1, -1)


## A patch where nothing overlaps or hangs off the case: the modules that do not fit are put in the
## next free place, and any that nowhere fits are dropped (their cables with them).
static func tidy(p: Dictionary) -> void:
	var placed := {"modules": {}, "cables": []}
	for id in (p["modules"] as Dictionary).keys():
		var type: String = p["modules"][id]["type"]
		var wide := width_in(p, id)
		var at := _spot(p, id)
		if not fits(placed, type, at, "", wide):
			at = free_slot(placed, type, wide)
		if at.x < 0:
			continue
		placed["modules"][id] = {"type": type, "at": [at.x, at.y], "w": wide, "missing": p["modules"][id].get("missing", false)}
		p["modules"][id]["at"] = [at.x, at.y]
	for id in (p["modules"] as Dictionary).keys():
		if not placed["modules"].has(id):
			RackPatch.remove(p, id)


## The modules laid out as the signal flows: sources at the left, the OUT at the right, each stage a
## band of columns with its modules stacked in the rows, the whole centred in the case. Cables then run
## mostly left to right and short, and a patch reads like its own diagram. A module with no cable into
## it sits just before the first thing it feeds. False (nothing moved) if it will not fit the case.
static func flow(p: Dictionary) -> bool:
	var ids: Array = (p["modules"] as Dictionary).keys()
	ids.sort()
	if ids.is_empty():
		return true
	var depth := {}
	var feeds := {}
	var fed := {}
	for id in ids:
		depth[id] = 0
		feeds[id] = []
	for c: Array in p["cables"]:
		var a := String(c[0]).get_slice(".", 0)
		var b := String(c[1]).get_slice(".", 0)
		if depth.has(a) and depth.has(b) and a != b:
			(feeds[a] as Array).append(b)
			fed[b] = true
	# Longest way in from a source, within as many passes as there are modules (a loop ends there).
	for _pass in ids.size():
		var moved := false
		for a in ids:
			for b in feeds[a]:
				if depth[b] < depth[a] + 1 and depth[a] + 1 < ids.size():
					depth[b] = depth[a] + 1
					moved = true
		if not moved:
			break
	# A source with nothing into it waits beside what it feeds, not at the far end.
	for a in ids:
		if not fed.has(a) and not (feeds[a] as Array).is_empty():
			var first := ids.size()
			for b in feeds[a]:
				first = mini(first, int(depth[b]))
			depth[a] = maxi(first - 1, 0)
	var layers := {}
	for id in ids:
		var d: int = depth[id]
		if not layers.has(d):
			layers[d] = []
		(layers[d] as Array).append(id)
	var keys: Array = layers.keys()
	keys.sort()
	# Bands: a layer of more than ROWS modules goes on into a second band.
	var bands: Array = []
	var row_of := {}
	for d in keys:
		var members: Array = layers[d]
		members.sort_custom(func(x: String, y: String) -> bool:
			var rx := _mean_row(p, x, row_of)
			var ry := _mean_row(p, y, row_of)
			return rx < ry if rx != ry else x < y)
		var at := 0
		while at < members.size():
			var chunk := members.slice(at, at + ROWS)
			var band := {"ids": chunk, "wide": 0}
			for n in chunk.size():
				band["wide"] = maxi(int(band["wide"]), width_in(p, chunk[n]))
				row_of[chunk[n]] = n
			bands.append(band)
			at += ROWS
	var total := 0
	for band in bands:
		total += int(band["wide"])
	var gap := 1 if total + bands.size() - 1 <= COLS else 0
	total += gap * (bands.size() - 1)
	if total > COLS:
		return false
	var col := (COLS - total) / 2
	var placed := {}
	for band in bands:
		for n in (band["ids"] as Array).size():
			var id: String = band["ids"][n]
			placed[id] = [col, n]
		col += int(band["wide"]) + gap
	for id in placed:
		p["modules"][id]["at"] = placed[id]
	return true


## The mean row, so far placed, of what feeds `id`: a module sits level with what it is fed by.
static func _mean_row(p: Dictionary, id: String, row_of: Dictionary) -> float:
	var sum := 0.0
	var n := 0
	for c: Array in p["cables"]:
		if String(c[1]).get_slice(".", 0) == id:
			var a := String(c[0]).get_slice(".", 0)
			if row_of.has(a):
				sum += float(row_of[a])
				n += 1
	return sum / n if n > 0 else 99.0
